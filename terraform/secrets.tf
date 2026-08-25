###############################################################################
# secrets.tf — KMS key + generated DB password + Secrets Manager
###############################################################################
#
#   random_password (generated at apply time, never written by a human)
#         |
#         +--> aws_secretsmanager_secret_version   <- the ONLY place the app reads
#         |        encrypted at rest with our own KMS key
#         |
#         +--> terraform.tfstate                   <- (!) it also lands here
#
# What we achieve: the password is never in source code, never in a .env file,
# never in a Kubernetes manifest, never in a container image, never in Git.
#
# What we are honest about: Terraform state records every value it manages.
# That is why .gitignore excludes *.tfstate and *.tfplan, and why a real team
# uses an S3 + KMS + DynamoDB backend. See the comment in provider.tf.
###############################################################################

# -----------------------------------------------------------------------------
# The KMS customer-managed key (CMK)
# -----------------------------------------------------------------------------
# We use ONE key for everything in this project: RDS storage, the Secrets
# Manager secret, CloudWatch log groups, and the CloudTrail S3 bucket.
#
# Why a customer-managed key rather than the free AWS-managed keys
# (aws/rds, aws/secretsmanager)?
#   - You control the key POLICY — who may use it, and for what.
#   - You control rotation.
#   - You can revoke access to encrypted data by disabling one key.
#   - Key usage shows up in CloudTrail with your key ID, so "who decrypted the
#     database credentials?" becomes an answerable question.
#
# Cost: $1/month per key, plus $0.03 per 10,000 requests. Effectively $1/month.
#
# A production setup would use SEPARATE keys per data domain so that revoking
# access to logs does not also revoke access to the database. One key here
# keeps the project readable; know why you would split them.
# -----------------------------------------------------------------------------

resource "aws_kms_key" "main" {
  description = "${local.name} — encrypts RDS storage, Secrets Manager, CloudWatch Logs, CloudTrail"

  # How long the key sits in PendingDeletion before AWS destroys it. AWS
  # enforces a 7-30 day window and it CANNOT be skipped — this is the reason a
  # `terraform destroy` leaves a key behind billing $1/month for a week.
  deletion_window_in_days = 7

  # Automatic annual rotation. AWS generates new key material and keeps the old
  # material so previously encrypted data still decrypts. Free, no downside.
  enable_key_rotation = true

  policy = data.aws_iam_policy_document.kms_main.json

  tags = {
    Name = "${local.name}-cmk"
  }
}

resource "aws_kms_alias" "main" {
  # An alias is a friendly pointer. Refer to "alias/jollof-run" instead of
  # memorising a UUID. Aliases can be repointed at a new key later.
  name          = "alias/${local.name}"
  target_key_id = aws_kms_key.main.key_id
}

# -----------------------------------------------------------------------------
# The key POLICY — who is allowed to use this key
# -----------------------------------------------------------------------------
# KMS is unusual: unlike almost every other AWS service, an IAM policy granting
# kms:Decrypt is NOT sufficient on its own. The KEY POLICY must also allow it.
# Both sides must agree. This catches people constantly.
#
# The first statement — giving the account root full control — is not optional
# in practice. Omit it and you can create a key that NOBODY, including you, can
# administer or delete. AWS will warn you. Do not ignore the warning.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "kms_main" {

  # --- 1. Account administrators keep control of the key ---------------------
  statement {
    sid    = "EnableIAMUserPermissions"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }

    # "root" here means "the account", not the root user. It delegates
    # authorisation to normal IAM policies within this account.
    actions   = ["kms:*"]
    resources = ["*"]
  }

  # --- 2. CloudWatch Logs may encrypt log groups -----------------------------
  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logs.${local.region}.amazonaws.com"]
    }

    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]
    resources = ["*"]

    # Scope this down: the Logs service may only use the key on behalf of log
    # groups in OUR account. Without this condition, any log group anywhere
    # that the service touches could theoretically use the key.
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${local.region}:${local.account_id}:log-group:*"]
    }
  }

  # --- 3. CloudTrail may encrypt log files -----------------------------------
  statement {
    sid    = "AllowCloudTrail"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions = [
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
      "kms:Decrypt",
    ]
    resources = ["*"]

    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:cloudtrail:arn"
      values   = ["arn:aws:cloudtrail:*:${local.account_id}:trail/*"]
    }
  }
}

# -----------------------------------------------------------------------------
# The database password
# -----------------------------------------------------------------------------
# random_password generates the value during `terraform apply` and stores it in
# state. It is marked sensitive, so Terraform redacts it from plan/apply output
# and from `terraform output` unless you explicitly ask with -raw.
#
# Note what is NOT here: there is no `variable "db_password"`. Adding one would
# invite somebody to write the password into a terraform.tfvars file. The
# variable does not exist, so the mistake is not available.
# -----------------------------------------------------------------------------

resource "random_password" "db" {
  length  = 32
  special = true

  # RDS rejects these characters in a master password. Excluding them here
  # avoids an InvalidParameterValue failure roughly one apply in twenty.
  override_special = "!#$%&*()-_=+[]{}<>:?"

  # Never regenerate on subsequent applies. Without this, any change to the
  # arguments above would roll the password and break the running application.
  lifecycle {
    ignore_changes = [length, special, override_special]
  }
}

# -----------------------------------------------------------------------------
# The Secrets Manager secret
# -----------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "db" {
  name        = "${local.name}/db-credentials"
  description = "PostgreSQL credentials for ${local.name}. Read by backend pods via the Secrets Store CSI Driver using IRSA."

  # Encrypt with OUR key rather than the free aws/secretsmanager key. This is
  # what makes kms:Decrypt on a specific key ARN a meaningful permission in
  # the backend's IRSA policy (see iam.tf).
  kms_key_id = aws_kms_key.main.arn

  # -------------------------------------------------------------------------
  # IMPORTANT for a learning project you will destroy and rebuild repeatedly.
  #
  # By default, deleting a secret puts it in a 30-day recovery window rather
  # than removing it. The name stays reserved, so the NEXT `terraform apply`
  # fails with:
  #   InvalidRequestException: You can't create this secret because a secret
  #   with this name is already scheduled for deletion.
  #
  # 0 = delete immediately, no recovery window.
  # Set this to 7 or 30 for anything you would be sad to lose.
  # -------------------------------------------------------------------------
  recovery_window_in_days = 0

  tags = {
    Name = "${local.name}-db-credentials"
  }
}

# -----------------------------------------------------------------------------
# The secret VALUE
# -----------------------------------------------------------------------------
# A "secret" is a container with metadata; a "secret version" holds the actual
# bytes. Rotation works by adding new versions and moving the AWSCURRENT label.
#
# We store JSON so the backend gets everything it needs from one API call —
# host, port, database name, username, password — rather than assembling a
# connection string from four different places.
#
# The RDS endpoint is only known after rds.tf creates the instance, so
# Terraform automatically orders this resource after it. That is the dependency
# graph doing its job; no depends_on needed.
# -----------------------------------------------------------------------------

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
    engine   = "postgres"
    host     = aws_db_instance.main.address # DNS name, no port
    port     = aws_db_instance.main.port    # 5432
    dbname   = var.db_name

    # This exact key set matches what RDS's own rotation Lambdas expect, so
    # you could bolt on automatic rotation later without changing the app.
  })
}
