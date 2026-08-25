###############################################################################
# eks.tf — the Kubernetes cluster
###############################################################################
#
#   +---------------------------------------------------------+
#   |  EKS CONTROL PLANE  (AWS-managed, you never SSH to it)   |
#   |  api-server | etcd | scheduler | controller-manager      |
#   |  Runs in an AWS-owned VPC. $0.10/hour, always.           |
#   +---------------------------+-----------------------------+
#                               | manages
#                               v
#   +---------------------------------------------------------+
#   |  MANAGED NODE GROUP  (EC2 in YOUR private subnets)       |
#   |  +-------------------+      +-------------------+        |
#   |  |  node 1  t3.small |      |  node 2  t3.small |        |
#   |  |  kubelet          |      |  kubelet          |        |
#   |  |  containerd       |      |  containerd       |        |
#   |  |  +-----+ +-----+  |      |  +-----+ +-----+  |        |
#   |  |  | pod | | pod |  |      |  | pod | | pod |  |        |
#   |  |  +-----+ +-----+  |      |  +-----+ +-----+  |        |
#   |  +-------------------+      +-------------------+        |
#   +---------------------------------------------------------+
#
# Division of labour: AWS runs and patches the control plane. You own the
# worker nodes — their AMI, their size, their count, and their IAM role.
###############################################################################

# -----------------------------------------------------------------------------
# Control-plane log group, created BEFORE the cluster
# -----------------------------------------------------------------------------
# EKS will create /aws/eks/<cluster>/cluster automatically if it does not
# exist — with retention set to "never expire". By creating it ourselves first
# we get to control retention and encryption.
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/${local.name}/cluster"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.main.arn

  tags = { Name = "${local.name}-eks-logs" }
}

# -----------------------------------------------------------------------------
# The cluster
# -----------------------------------------------------------------------------

resource "aws_eks_cluster" "main" {
  name     = local.name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.cluster_version

  vpc_config {
    # Control-plane ENIs are placed in BOTH public and private subnets so the
    # API server can reach nodes and so we can reach the API from the internet.
    subnet_ids = concat(
      aws_subnet.public[*].id,
      aws_subnet.private[*].id,
    )

    # Public endpoint ON so `kubectl` works from your laptop without a bastion.
    # Private endpoint ALSO on so in-cluster traffic to the API server stays
    # inside the VPC rather than hairpinning out through the NAT Gateway.
    endpoint_public_access  = true
    endpoint_private_access = true

    # -------------------------------------------------------------------------
    # HARDENING NOTE, and be ready for this question in an interview:
    # 0.0.0.0/0 means the Kubernetes API endpoint is reachable from anywhere on
    # the internet. It is still authenticated (IAM + OIDC) and TLS-protected,
    # so this is not "open" in the sense of unauthenticated — but a real
    # environment would restrict it to office/VPN CIDRs:
    #
    #   public_access_cidrs = ["203.0.113.4/32"]
    #
    # We leave it open because your home IP changes and locking yourself out of
    # your own cluster mid-project is a miserable way to learn.
    # -------------------------------------------------------------------------
    public_access_cidrs = ["0.0.0.0/0"]
  }

  # ---------------------------------------------------------------------------
  # Control-plane audit logging
  # ---------------------------------------------------------------------------
  #   api           : requests to the Kubernetes API server
  #   audit         : WHO did WHAT in Kubernetes — the k8s equivalent of
  #                   CloudTrail. This is the interesting one.
  #   authenticator : IAM-to-Kubernetes identity mapping decisions
  #
  # COST WARNING: `audit` is chatty — expect a few hundred MB/month at
  # $0.50/GB ingestion. If your bill surprises you, drop to ["api"].
  # ---------------------------------------------------------------------------
  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  access_config {
    # API_AND_CONFIG_MAP is the modern default. It lets you grant cluster access
    # with IAM "access entries" instead of hand-editing the aws-auth ConfigMap,
    # which was famously easy to corrupt and lock everyone out.
    authentication_mode = "API_AND_CONFIG_MAP"

    # Grants YOU (whoever runs `terraform apply`) cluster-admin. Without this
    # you would create a cluster you cannot talk to. This is why
    # `aws eks update-kubeconfig` just works in Phase 4.
    bootstrap_cluster_creator_admin_permissions = true
  }

  # Do not let Terraform create the cluster before the log group and IAM
  # permissions exist, or control-plane logging silently fails to start.
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_cloudwatch_log_group.eks_cluster,
  ]

  tags = { Name = local.name }
}

###############################################################################
# OIDC PROVIDER — the foundation of IRSA
###############################################################################
#
# Every EKS cluster publishes an OpenID Connect discovery document at a URL
# like:
#   https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE
#
# Registering that URL as an IAM identity provider tells IAM: "tokens signed by
# this issuer are trustworthy; roles may be granted to subjects it names."
#
# Without this resource, IRSA does not work at all and every AssumeRoleWith-
# WebIdentity call fails with "Invalid identity token".
###############################################################################

# Fetch the TLS certificate the OIDC endpoint presents, so we can pin its
# thumbprint. IAM requires the SHA-1 fingerprint of the CA certificate.
data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer

  # The only audience we accept. STS tokens minted for anything else are
  # rejected — see the "aud" conditions in iam.tf.
  client_id_list = ["sts.amazonaws.com"]

  # Thumbprint of the root CA. AWS rotates this occasionally; reading it from
  # the live certificate rather than hardcoding means it stays correct.
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]

  tags = { Name = "${local.name}-oidc" }
}

locals {
  # "oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE"
  #
  # IAM policy conditions address OIDC claims by the issuer host WITHOUT the
  # https:// scheme, e.g. "<host>:sub" and "<host>:aud". Getting this wrong is
  # the number-one cause of silent IRSA failure, so we compute it once here and
  # reuse it everywhere.
  oidc_provider_host = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")
}

###############################################################################
# MANAGED NODE GROUP — the worker EC2 instances
###############################################################################
#
# "Managed" means AWS handles: AMI selection and patching, instance
# registration with the cluster, graceful draining during updates, and an
# Auto Scaling Group behind the scenes. You still pay normal EC2 prices —
# there is no premium for the management.
###############################################################################

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.name}-nodes"
  node_role_arn   = aws_iam_role.eks_node.arn

  # PRIVATE subnets only. Nodes have no public IPs. They reach ECR and AWS APIs
  # through the NAT Gateway; nothing on the internet can reach them directly.
  subnet_ids = aws_subnet.private[*].id

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  # How many nodes may be unavailable at once during a version upgrade.
  # With 2 nodes, 1 means "replace them one at a time" — the cluster stays up.
  update_config {
    max_unavailable = 1
  }

  instance_types = [var.node_instance_type]
  disk_size      = var.node_disk_size

  # AL2023_x86_64_STANDARD is the current Amazon Linux 2023 EKS-optimised AMI
  # family. AL2 (the older one) is end-of-life for EKS 1.33+.
  ami_type      = "AL2023_x86_64_STANDARD"
  capacity_type = "ON_DEMAND" # SPOT is ~70% cheaper but can be reclaimed
  # with 2 minutes' notice. Fine for stateless
  # workloads; a confusing variable to add while
  # you are still learning why pods restart.

  labels = {
    role = "general"
  }

  # IAM policies must be attached BEFORE nodes launch, or the kubelet fails to
  # register and the node group creation times out after ~20 minutes with a
  # deeply unhelpful message.
  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
  ]

  lifecycle {
    # After the first apply, node count may be changed by the AWS CLI or an
    # autoscaler. Ignoring drift here stops Terraform from fighting them.
    # Remove this if you want Terraform to be the sole authority.
    ignore_changes = [scaling_config[0].desired_size]
  }

  tags = { Name = "${local.name}-nodes" }
}

###############################################################################
# EKS ADD-ONS — cluster components AWS installs and patches for you
###############################################################################
#
# These run as DaemonSets/Deployments in kube-system. You could install them
# yourself from YAML, but then you own upgrading them forever.
#
# VERSION SELECTION — a provider-version gotcha worth knowing:
# aws_eks_addon USED to accept `most_recent = true`. That argument was REMOVED
# in AWS provider v6. If you follow an older tutorial you will hit:
#
#   Error: Unsupported argument
#   An argument named "most_recent" is not expected here.
#
# The replacement is the aws_eks_addon_version DATA SOURCE, which looks up the
# newest version compatible with a given Kubernetes version. We resolve each
# addon's version once below and feed it to addon_version.
#
# In production you would pin these to literal strings so that an upgrade is a
# deliberate, reviewable commit rather than something that happens whenever
# AWS ships a new build.
###############################################################################

locals {
  eks_addons = ["vpc-cni", "kube-proxy", "coredns", "amazon-cloudwatch-observability"]
}

data "aws_eks_addon_version" "this" {
  for_each = toset(local.eks_addons)

  addon_name         = each.key
  kubernetes_version = aws_eks_cluster.main.version
  most_recent        = true
}

# The CNI plugin that gives every pod a real VPC IP address. This is why pod
# IPs are routable from the ALB, and why instance type caps pod count.
resource "aws_eks_addon" "vpc_cni" {
  cluster_name  = aws_eks_cluster.main.name
  addon_name    = "vpc-cni"
  addon_version = data.aws_eks_addon_version.this["vpc-cni"].version

  # What to do when the addon's Kubernetes objects have been modified outside
  # of EKS (by you, with kubectl). OVERWRITE = "EKS wins". The alternative,
  # NONE, makes the apply fail rather than clobber your change.
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

# kube-proxy programmes iptables/IPVS rules so ClusterIP Services actually
# route to pods. This is the machinery behind "Service discovery".
resource "aws_eks_addon" "kube_proxy" {
  cluster_name  = aws_eks_cluster.main.name
  addon_name    = "kube-proxy"
  addon_version = data.aws_eks_addon_version.this["kube-proxy"].version

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

# Cluster DNS. This is what resolves
#   backend-service.jollof-run.svc.cluster.local
# It runs as PODS, so it needs nodes to exist first — without the depends_on,
# CoreDNS installs, finds nowhere to schedule, and the addon reports DEGRADED.
resource "aws_eks_addon" "coredns" {
  cluster_name  = aws_eks_cluster.main.name
  addon_name    = "coredns"
  addon_version = data.aws_eks_addon_version.this["coredns"].version

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.main]
}

# Container Insights: node CPU/memory/disk, pod-level metrics, and container
# stdout/stderr shipped to CloudWatch. This is what makes Phase 10 worth doing.
# It authenticates using the node role's CloudWatchAgentServerPolicy.
resource "aws_eks_addon" "cloudwatch_observability" {
  count = var.enable_container_insights ? 1 : 0

  cluster_name  = aws_eks_cluster.main.name
  addon_name    = "amazon-cloudwatch-observability"
  addon_version = data.aws_eks_addon_version.this["amazon-cloudwatch-observability"].version

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_node_group.main,
    aws_iam_role_policy_attachment.node_cloudwatch,
  ]
}
