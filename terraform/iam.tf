###############################################################################
# iam.tf — every identity in the project
###############################################################################
#
# Five distinct identities live here. Keep them straight:
#
#   1. eks-cluster-role   the EKS CONTROL PLANE assumes this to manage ENIs,
#                         load balancers, and logging on your behalf.
#   2. eks-node-role      each worker EC2 INSTANCE assumes this. Node-wide.
#                         Every pod on the node inherits it unless IRSA
#                         overrides — which is exactly why we use IRSA.
#   3. alb-controller     an IRSA role for the ALB controller POD, so it can
#                         create load balancers.
#   4. backend-irsa       an IRSA role for the backend POD, scoped to exactly
#                         one secret and one KMS key. This is the centrepiece.
#   5. flow-logs /        service roles so VPC Flow Logs and CloudTrail can
#      cloudtrail-logs    write to CloudWatch Logs.
#
# NOTHING here uses AdministratorAccess. Nothing uses Resource = "*" except
# where the AWS API genuinely requires it (and those are commented).
###############################################################################

###############################################################################
# 1. EKS CLUSTER ROLE — assumed by the EKS control plane
###############################################################################

data "aws_iam_policy_document" "eks_cluster_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    # "Service" principal = an AWS service, not a human or an EC2 instance.
    # This says: the EKS service itself is allowed to become this role.
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = "${local.name}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume.json

  tags = { Name = "${local.name}-eks-cluster-role" }
}

# AWS-managed policy. Grants the control plane permission to create the ENIs
# it needs in your subnets, manage security groups, and describe EC2/ELB
# resources. Using the managed policy is correct here — AWS updates it when
# EKS gains new capabilities.
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

###############################################################################
# 2. NODE GROUP ROLE — assumed by the worker EC2 instances
###############################################################################
#
# CRITICAL CONCEPT: every pod on a node can reach the EC2 Instance Metadata
# Service and borrow this role's credentials unless you stop it. So whatever
# you attach here is effectively granted to EVERY pod in the cluster.
#
# That is the entire argument for IRSA. We keep this role limited to what the
# KUBELET needs to function, and give application permissions per-pod instead.
###############################################################################

data "aws_iam_policy_document" "eks_node_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_node" {
  name               = "${local.name}-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.eks_node_assume.json

  tags = { Name = "${local.name}-eks-node-role" }
}

# The three policies every EKS managed node group requires.
resource "aws_iam_role_policy_attachment" "node_worker" {
  # Lets the kubelet register the node with the cluster and describe resources.
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  # Lets the VPC CNI plugin attach ENIs and assign pod IPs. Without this,
  # every pod stays stuck in ContainerCreating with a network error.
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  # ReadOnly, not full access — nodes PULL images, they never push.
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Required by the amazon-cloudwatch-observability addon (Container Insights)
# so the CloudWatch agent on each node can publish metrics and logs.
# This is a node-level concern, so a node-level role is the right place.
resource "aws_iam_role_policy_attachment" "node_cloudwatch" {
  count      = var.enable_container_insights ? 1 : 0
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Lets you open a shell on a node without SSH keys or a bastion host:
#   aws ssm start-session --target i-xxxxx
# Extremely useful for debugging in Phase 12, and strictly safer than opening
# port 22 to the world.
resource "aws_iam_role_policy_attachment" "node_ssm" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

###############################################################################
# 3. AWS LOAD BALANCER CONTROLLER — IRSA role
###############################################################################
#
# The controller pod needs broad ELB permissions because it genuinely creates
# and destroys load balancers, target groups, listeners, and security groups.
#
# The policy JSON is the OFFICIAL one, downloaded verbatim from the project at
# a PINNED version and committed to this repo:
#
#   curl -o terraform/alb-controller-policy.json \
#     https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.17.1/docs/install/iam_policy.json
#
# Do not hand-write this policy. It is ~200 lines, AWS changes it between
# controller versions, and a missing action produces an error message that
# points nowhere useful.
###############################################################################

data "aws_iam_policy_document" "alb_controller_assume" {
  statement {
    effect = "Allow"

    # Note the action: AssumeRoleWithWebIdentity, not AssumeRole. This is OIDC
    # federation — the caller presents a signed JWT rather than AWS credentials.
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    # THE MOST IMPORTANT LINE IN IRSA.
    #
    # "sub" (subject) in the ServiceAccount token is always:
    #     system:serviceaccount:<namespace>:<serviceaccount-name>
    #
    # By requiring an exact match, this role can ONLY be assumed by a pod
    # running as the aws-load-balancer-controller SA in kube-system. A pod in
    # any other namespace, or with any other SA, is refused by STS.
    #
    # Omit this condition and ANY pod in the cluster could assume the role.
    # That is a real, common, and severe misconfiguration.
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_host}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    # "aud" (audience) must be sts.amazonaws.com — this proves the token was
    # minted for AWS specifically and is not a token borrowed from elsewhere.
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "alb_controller" {
  name               = "${local.name}-alb-controller-irsa"
  assume_role_policy = data.aws_iam_policy_document.alb_controller_assume.json

  tags = { Name = "${local.name}-alb-controller-irsa" }
}

resource "aws_iam_policy" "alb_controller" {
  name        = "${local.name}-alb-controller-policy"
  description = "Official AWS Load Balancer Controller policy, v2.17.1"
  policy      = file("${path.module}/alb-controller-policy.json")
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}

###############################################################################
# 4. BACKEND IRSA ROLE — the least-privilege centrepiece
###############################################################################
#
#   Backend Pod
#       |  runs as ServiceAccount "backend-sa" in namespace "jollof-run"
#       v
#   projected ServiceAccount token (a signed JWT, rotated hourly by kubelet)
#       |
#       v
#   sts:AssumeRoleWithWebIdentity
#       |  STS validates the JWT signature against the cluster's OIDC provider,
#       |  then checks the two conditions below
#       v
#   temporary IAM credentials for THIS role, valid ~1 hour
#       |
#       v
#   secretsmanager:GetSecretValue on ONE secret ARN
#   kms:Decrypt                   on ONE key ARN
#
# Compare with the alternative: attaching SecretsManagerReadWrite to the node
# role. That would let every pod in the cluster read every secret in the
# account. This role can read exactly one secret, and only from one namespace.
###############################################################################

data "aws_iam_policy_document" "backend_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_host}:sub"
      # namespace "jollof-run", ServiceAccount "backend-sa".
      # These MUST match kubernetes/serviceaccount.yaml exactly. A typo here
      # produces "AccessDenied: Not authorized to perform sts:AssumeRole-
      # WithWebIdentity" and no hint about which field is wrong.
      values = ["system:serviceaccount:${local.name}:backend-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backend" {
  name               = "${local.name}-backend-irsa"
  assume_role_policy = data.aws_iam_policy_document.backend_assume.json

  tags = { Name = "${local.name}-backend-irsa" }
}

data "aws_iam_policy_document" "backend_secrets" {

  # --- Read exactly one secret ----------------------------------------------
  statement {
    sid    = "ReadDatabaseCredentialsOnly"
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
      # DescribeSecret is needed by the Secrets Store CSI Driver to resolve
      # metadata before fetching. Read-only, no value exposure.
      "secretsmanager:DescribeSecret",
    ]

    # A SPECIFIC ARN. Not "*". Not "arn:aws:secretsmanager:*:*:secret:*".
    # This role cannot read any other secret in the account, even by accident.
    resources = [aws_secretsmanager_secret.db.arn]
  }

  # --- Decrypt using exactly one key ----------------------------------------
  statement {
    sid    = "DecryptWithProjectKeyOnly"
    effect = "Allow"

    # GetSecretValue alone is not enough. The secret is encrypted with our CMK,
    # so Secrets Manager must call kms:Decrypt on the CALLER's behalf. Without
    # this statement you get:
    #   AccessDeniedException: ... is not authorized to perform: kms:Decrypt
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.main.arn]

    # Belt and braces: even for this key, only allow decryption in the context
    # of Secrets Manager. The same key encrypts CloudTrail and log data, and
    # the backend has no business reading those.
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${local.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "backend_secrets" {
  name        = "${local.name}-backend-secrets-policy"
  description = "Least-privilege: read one secret, decrypt with one key."
  policy      = data.aws_iam_policy_document.backend_secrets.json
}

resource "aws_iam_role_policy_attachment" "backend_secrets" {
  role       = aws_iam_role.backend.name
  policy_arn = aws_iam_policy.backend_secrets.arn
}

###############################################################################
# 5a. VPC FLOW LOGS service role
###############################################################################

data "aws_iam_policy_document" "flow_logs_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  name               = "${local.name}-flow-logs-role"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume.json

  tags = { Name = "${local.name}-flow-logs-role" }
}

data "aws_iam_policy_document" "flow_logs" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]

    # Resource "*" is required here: the flow-logs service creates log STREAMS
    # with names it chooses (one per ENI), so the ARNs cannot be predicted at
    # policy-writing time. The service principal in the trust policy is what
    # constrains this.
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  name   = "${local.name}-flow-logs-policy"
  role   = aws_iam_role.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs.json
}

###############################################################################
# 5b. CLOUDTRAIL -> CLOUDWATCH LOGS service role
###############################################################################
# CloudTrail always writes to S3. Sending a SECOND copy to CloudWatch Logs is
# optional but is what lets us query events with Logs Insights in Phase 11
# instead of downloading gzipped JSON from S3 by hand.
###############################################################################

data "aws_iam_policy_document" "cloudtrail_logs_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cloudtrail_logs" {
  name               = "${local.name}-cloudtrail-logs-role"
  assume_role_policy = data.aws_iam_policy_document.cloudtrail_logs_assume.json

  tags = { Name = "${local.name}-cloudtrail-logs-role" }
}

data "aws_iam_policy_document" "cloudtrail_logs" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    # Scoped to our trail's log group only.
    resources = ["${aws_cloudwatch_log_group.cloudtrail.arn}:*"]
  }
}

resource "aws_iam_role_policy" "cloudtrail_logs" {
  name   = "${local.name}-cloudtrail-logs-policy"
  role   = aws_iam_role.cloudtrail_logs.id
  policy = data.aws_iam_policy_document.cloudtrail_logs.json
}
