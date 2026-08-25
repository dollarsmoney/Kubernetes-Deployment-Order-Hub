###############################################################################
# cloudtrail.tf — the audit log: WHO did WHAT, WHEN, and FROM WHERE
###############################################################################
#
#   Any AWS API call, from anywhere
#     (console click, aws CLI, Terraform, SDK, another AWS service)
#              |
#              v
#   +---------------------------------------------+
#   |  CLOUDTRAIL                                  |
#   |  captures the call as a JSON event           |
#   +----------------+-------------+---------------+
#                    |             |
#         (durable)  v             v  (queryable)
#            S3 bucket        CloudWatch Logs
#         gzipped JSON       Logs Insights queries
#         cheap, forever     ~$0.50/GB, 7 days
#
# Why BOTH destinations? S3 is the system of record: cheap, immutable,
# suitable for compliance. CloudWatch Logs is for humans in a hurry — you can
# run a query against it in 15 seconds instead of downloading and unzipping
# hundreds of objects. Phase 11 uses the CloudWatch side.
#
# THE DISTINCTION THAT MATTERS:
#   CloudTrail logs the AWS CONTROL PLANE — "someone called DeleteDBInstance".
#   It does NOT log what happens INSIDE your resources — a SQL query against
#   RDS, or an HTTP request to your app, is invisible to CloudTrail.
#   For those you need database logs, ALB access logs, or application logs.
###############################################################################

# A globally unique suffix. S3 bucket names share ONE namespace across every
# AWS account on earth, so "jollof-run-cloudtrail" is almost certainly taken.
resource "random_id" "bucket_suffix" {
  byte_length = 4 # 8 hex characters
}

###############################################################################
# S3 BUCKET — the durable copy
###############################################################################

resource "aws_s3_bucket" "cloudtrail" {
  bucket = "${local.name}-cloudtrail-${random_id.bucket_suffix.hex}"

  # Allows `terraform destroy` to empty and delete the bucket. Without it,
  # destroy fails with BucketNotEmpty and you delete objects by hand — and
  # with versioning on, you must delete every VERSION, not just every object.
  #
  # NEVER set this on a real audit-log bucket. The entire point of an audit
  # log is that it survives the person trying to remove it.
  force_destroy = true

  tags = { Name = "${local.name}-cloudtrail" }
}

# Block every form of public access. Four separate settings because AWS added
# them at different times; you want all four, always, on every bucket that is
# not deliberately a public website.
resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versioning means an overwrite or delete creates a new version rather than
# destroying data. For an audit log this is close to mandatory: it is what
# stops "delete the evidence" from being a single API call.
resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }

    # S3 Bucket Keys cut KMS API calls (and therefore KMS cost) by up to 99%
    # by caching a bucket-level data key instead of calling KMS per object.
    # Free to enable, no downside.
    bucket_key_enabled = true
  }
}

# Expire old logs. Without this, audit logs accumulate forever — correct for
# compliance, wasteful for a learning project.
resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter {} # apply to all objects

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# -----------------------------------------------------------------------------
# BUCKET POLICY — lets the CloudTrail service write here
# -----------------------------------------------------------------------------
# CloudTrail is a service, not a user. It needs explicit permission on the
# bucket, and the required shape is prescribed by AWS. If you get this wrong,
# trail creation fails with:
#   InsufficientS3BucketPolicyException: Incorrect S3 bucket policy is detected
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "cloudtrail_bucket" {

  # CloudTrail checks the bucket's ACL before writing, to confirm it can.
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail.arn]

    # Confused-deputy protection: only OUR trail may use this permission,
    # not some other account's trail that happens to know the bucket name.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudtrail:${local.region}:${local.account_id}:trail/${local.name}-trail"]
    }
  }

  # The actual log delivery.
  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions = ["s3:PutObject"]

    # CloudTrail writes to a fixed prefix structure:
    #   AWSLogs/<account-id>/CloudTrail/<region>/<yyyy>/<mm>/<dd>/<file>.json.gz
    resources = ["${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${local.account_id}/*"]

    # Require that delivered objects are owned by the bucket owner. Without
    # this, cross-account delivery could leave objects the bucket owner cannot
    # read — a classic S3 ownership trap.
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudtrail:${local.region}:${local.account_id}:trail/${local.name}-trail"]
    }
  }

  # Belt and braces: refuse any request that is not over TLS.
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.cloudtrail.arn,
      "${aws_s3_bucket.cloudtrail.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = data.aws_iam_policy_document.cloudtrail_bucket.json
}

###############################################################################
# CLOUDWATCH LOG GROUP — the queryable copy
###############################################################################

resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/${local.name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.main.arn

  tags = { Name = "${local.name}-cloudtrail-logs" }
}

###############################################################################
# THE TRAIL
###############################################################################

resource "aws_cloudtrail" "main" {
  name           = "${local.name}-trail"
  s3_bucket_name = aws_s3_bucket.cloudtrail.id

  # ---------------------------------------------------------------------------
  # Capture events from EVERY region, not just us-east-1.
  #
  # This matters more than it sounds. If someone's credentials are stolen and
  # used to spin up mining instances in ap-south-1, a single-region trail sees
  # nothing at all. Multi-region trails cost the same for management events.
  # ---------------------------------------------------------------------------
  is_multi_region_trail = true

  # Include events from AWS services acting on your behalf (e.g. the EKS
  # control plane creating ENIs). Noisier, but without it there are
  # unexplained gaps in the story.
  include_global_service_events = true

  enable_logging = true

  # Adds a SHA-256 digest file every hour so you can prove the logs were not
  # tampered with after delivery. Free.
  enable_log_file_validation = true

  kms_key_id = aws_kms_key.main.arn

  # Second delivery destination, for Logs Insights.
  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_logs.arn

  # ---------------------------------------------------------------------------
  # MANAGEMENT vs DATA events — the biggest cost decision in CloudTrail
  # ---------------------------------------------------------------------------
  # MANAGEMENT events: control-plane operations. RunInstances, CreateBucket,
  #   AuthorizeSecurityGroupIngress, AssumeRole, GetSecretValue.
  #   The FIRST trail in an account gets these FREE.
  #
  # DATA events: object-level and item-level operations. s3:GetObject,
  #   lambda:Invoke, dynamodb:PutItem. Charged at $0.10 per 100,000 events,
  #   and a busy S3 bucket generates millions. This is how people accidentally
  #   run up four-figure CloudTrail bills.
  #
  # We log management events only. Everything Phase 11 asks you to find —
  # security group changes, EC2 stop/start, RDS modifications — is a
  # management event.
  # ---------------------------------------------------------------------------
  event_selector {
    read_write_type = "All" # "All" | "ReadOnly" | "WriteOnly"

    # true = log management events. Set to false and the trail records almost
    # nothing.
    include_management_events = true

    # No data_resource blocks = no data events = no per-event charges.
  }

  # The bucket policy must exist before CloudTrail will accept the bucket.
  depends_on = [
    aws_s3_bucket_policy.cloudtrail,
    aws_iam_role_policy.cloudtrail_logs,
  ]

  tags = { Name = "${local.name}-trail" }
}

###############################################################################
# METRIC FILTER + ALARM — turn a log pattern into a metric
###############################################################################
# This is a genuinely useful CloudWatch technique and it ties Phases 10 and 11
# together: scan a log group for a pattern, emit a metric when it matches,
# alarm on the metric.
#
# Here: alert on any security-group change. In Phase 11 you will deliberately
# modify a security group, and this alarm should fire.
###############################################################################

resource "aws_cloudwatch_log_metric_filter" "security_group_changes" {
  name           = "${local.name}-security-group-changes"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name

  # CloudWatch Logs filter-pattern syntax for JSON events. Each ($.field = "x")
  # tests one JSON path; || is OR.
  pattern = <<-PATTERN
    { ($.eventName = "AuthorizeSecurityGroupIngress") || ($.eventName = "AuthorizeSecurityGroupEgress") || ($.eventName = "RevokeSecurityGroupIngress") || ($.eventName = "RevokeSecurityGroupEgress") || ($.eventName = "CreateSecurityGroup") || ($.eventName = "DeleteSecurityGroup") }
  PATTERN

  metric_transformation {
    name      = "SecurityGroupChangeCount"
    namespace = "${local.name}/CloudTrail"
    value     = "1" # emit 1 per matching log event

    # Publish 0 when nothing matches, so the metric exists continuously and the
    # alarm has data rather than sitting in INSUFFICIENT_DATA.
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "security_group_changes" {
  alarm_name        = "${local.name}-security-group-changed"
  alarm_description = "A security group was created, deleted, or modified. Find the actor in CloudTrail: filter on eventName and read userIdentity.arn."

  namespace   = "${local.name}/CloudTrail"
  metric_name = "SecurityGroupChangeCount"

  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = { Name = "${local.name}-sg-change-alarm" }
}
