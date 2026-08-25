###############################################################################
# github-oidc.tf — let GitHub Actions into AWS without any stored credentials
###############################################################################
#
# THE PROBLEM THIS SOLVES
#
# The usual way to give CI access to AWS is to mint an IAM user, create an
# access key, and paste it into GitHub repository secrets. That key:
#   - never expires until somebody remembers to rotate it
#   - is readable by anyone with write access to the repo settings
#   - leaks permanently if it ever reaches a log, a fork, or a screenshot
#   - is completely detached from WHICH workflow, branch or commit used it
#
# OIDC federation removes the key entirely:
#
#   GitHub Actions job  (permissions: id-token: write)
#         |  asks GitHub's OIDC provider for a signed JWT describing itself
#         v
#   JWT claims include:
#       iss = https://token.actions.githubusercontent.com
#       aud = sts.amazonaws.com
#       sub = repo:OWNER/REPO:ref:refs/heads/main
#         |
#         |  sts:AssumeRoleWithWebIdentity
#         v
#   STS verifies the signature against the registered provider, then evaluates
#   the role's trust policy conditions below
#         |
#         v
#   temporary credentials, ~1 hour, auto-expiring, tied to that exact run
#
# There is no secret in the repository. There is nothing to rotate. And the
# `sub` claim means access is scoped to a specific repo AND a specific branch.
###############################################################################

variable "github_repo" {
  description = "GitHub repository allowed to assume the CI role, as owner/name."
  type        = string
  default     = "dollarsmoney/Kubernetes-Deployment-Order-Hub"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repo))
    error_message = "github_repo must be in owner/name form."
  }
}

variable "github_deploy_ref" {
  description = <<-EOT
    The single git ref permitted to assume the CI role.

    Deliberately NOT "*". On a PUBLIC repository anyone can fork and open a pull
    request; pinning the ref means a token minted for a fork, or for any branch
    other than this one, fails the trust policy at STS.
  EOT
  type        = string
  default     = "refs/heads/main"
}

# -----------------------------------------------------------------------------
# Register GitHub as an OpenID Connect identity provider
# -----------------------------------------------------------------------------
# One per AWS account. If you already federate another repo from this account,
# import the existing provider rather than creating a second one:
#   terraform import aws_iam_openid_connect_provider.github \
#     arn:aws:iam::<account>:oidc-provider/token.actions.githubusercontent.com
# -----------------------------------------------------------------------------

data "tls_certificate" "github_oidc" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  # The ONLY audience accepted. The official aws-actions/configure-aws-credentials
  # action requests exactly this. Leaving it open would let a token minted for a
  # different relying party be replayed against AWS.
  client_id_list = ["sts.amazonaws.com"]

  # AWS validates GitHub's certificate against its own trusted CA store and no
  # longer strictly depends on this value, but the argument is still required.
  # Reading it from the live certificate keeps it correct across CA rotations
  # instead of pinning a hardcoded hex string that silently goes stale.
  thumbprint_list = [data.tls_certificate.github_oidc.certificates[0].sha1_fingerprint]

  tags = { Name = "${local.name}-github-oidc" }
}

# -----------------------------------------------------------------------------
# The trust policy — the security boundary
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "github_actions_assume" {
  statement {
    effect = "Allow"

    # AssumeRoleWithWebIdentity, not AssumeRole: the caller presents a signed
    # JWT rather than existing AWS credentials.
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    # -------------------------------------------------------------------------
    # THE LINE THAT MATTERS.
    #
    # "sub" identifies the workflow run:
    #     repo:dollarsmoney/Kubernetes-Deployment-Order-Hub:ref:refs/heads/main
    #
    # StringEquals, not StringLike, and a full ref rather than a wildcard.
    #
    # Getting this wrong is the classic OIDC misconfiguration:
    #   sub = "repo:*"              -> ANY repo on GitHub can assume this role
    #   sub = "repo:owner/repo:*"   -> any branch, tag, or PR in the repo can
    #
    # That second one looks harmless and is not. On a public repo, a pull
    # request from a fork runs with a `sub` of
    # `repo:owner/repo:pull_request`, and a wildcard would match it.
    # -------------------------------------------------------------------------
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:ref:${var.github_deploy_ref}"]
    }

    # Proves the token was minted for AWS specifically.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name        = "${local.name}-github-actions"
  description = "Assumed by GitHub Actions via OIDC to push images to ECR and roll Deployments in the ${local.name} namespace."

  assume_role_policy = data.aws_iam_policy_document.github_actions_assume.json

  # Cap the session at one hour. The workflow needs minutes; there is no reason
  # for a credential to outlive the job that requested it.
  max_session_duration = 3600

  tags = { Name = "${local.name}-github-actions" }
}

# -----------------------------------------------------------------------------
# What CI is actually allowed to do
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "github_actions" {

  # --- Obtain an ECR login token -------------------------------------------
  statement {
    sid    = "ECRGetAuthToken"
    effect = "Allow"

    actions = ["ecr:GetAuthorizationToken"]

    # Resource "*" is REQUIRED here — GetAuthorizationToken is account-scoped
    # and the API rejects a resource ARN. It returns a token, not data; the
    # statement below is what governs which repositories that token can touch.
    resources = ["*"]
  }

  # --- Push to OUR two repositories, and nothing else -----------------------
  statement {
    sid    = "ECRPushToProjectReposOnly"
    effect = "Allow"

    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      # Read actions, so a build can reuse cached layers already in the registry.
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeImages",
    ]

    # Specific ARNs. Not "*". CI cannot push to any other repository in the
    # account, and cannot delete repositories or images at all.
    resources = [for r in aws_ecr_repository.app : r.arn]
  }

  # --- Read enough cluster metadata to build a kubeconfig -------------------
  statement {
    sid    = "EKSDescribeClusterForKubeconfig"
    effect = "Allow"

    # `aws eks update-kubeconfig` needs exactly this: the API endpoint and the
    # cluster CA certificate. It grants NO access to the Kubernetes API itself
    # — that is authorised separately by the access entry below.
    actions   = ["eks:DescribeCluster"]
    resources = [aws_eks_cluster.main.arn]
  }
}

resource "aws_iam_role_policy" "github_actions" {
  name   = "${local.name}-github-actions-policy"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions.json
}

###############################################################################
# KUBERNETES AUTHORISATION — separate from IAM, and scoped to one namespace
###############################################################################
#
# TWO DISTINCT PERMISSION SYSTEMS, and conflating them is a common mistake:
#
#   IAM           decides whether you may CALL the EKS API (DescribeCluster)
#   EKS access    decides what you may do INSIDE Kubernetes (get/patch/delete)
#
# An IAM role with full AdministratorAccess still cannot list pods until it is
# mapped to a Kubernetes identity. That mapping used to mean hand-editing the
# aws-auth ConfigMap — famously easy to corrupt and lock everyone out. Access
# entries replaced it, and are why eks.tf sets
# `authentication_mode = "API_AND_CONFIG_MAP"`.
###############################################################################

resource "aws_eks_access_entry" "github_actions" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.github_actions.arn
  type          = "STANDARD"

  tags = { Name = "${local.name}-github-actions" }
}

resource "aws_eks_access_policy_association" "github_actions" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.github_actions.arn

  # AmazonEKSEditPolicy: create/update/patch/delete ordinary workload objects.
  # It does NOT grant access to cluster-scoped resources, RBAC objects, or
  # anything in another namespace.
  #
  # The obvious alternative, AmazonEKSClusterAdminPolicy, would let a
  # compromised workflow read every Secret in the cluster — including the
  # database credentials the whole IRSA design exists to protect.
  policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"

  access_scope {
    # THE SCOPE. Without this block the policy applies cluster-wide.
    type       = "namespace"
    namespaces = [local.name] # "jollof-run" only
  }

  depends_on = [aws_eks_access_entry.github_actions]
}

###############################################################################
# NOTE ON ECR + KMS
###############################################################################
# ecr.tf encrypts both repositories with the project CMK. ECR performs that
# encryption server-side using a grant it holds on the key, so the principal
# doing the `docker push` normally needs no kms:* permission of its own — which
# is why none is granted above.
#
# If the first push fails with a KMS AccessDeniedException, the fix is one
# statement, scoped as tightly as the rest:
#
#   statement {
#     effect    = "Allow"
#     actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
#     resources = [aws_kms_key.main.arn]
#     condition {
#       test     = "StringEquals"
#       variable = "kms:ViaService"
#       values   = ["ecr.${local.region}.amazonaws.com"]
#     }
#   }
#
# Left commented rather than granted pre-emptively. Adding IAM permissions "just
# in case" is exactly how roles quietly accumulate privilege nobody can later
# justify removing.
###############################################################################
