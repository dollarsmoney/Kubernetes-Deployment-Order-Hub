###############################################################################
# cloudwatch.tf — metrics, logs, alarms, dashboards
###############################################################################
#
# FOUR CONCEPTS. Keep them separate in your head:
#
#   METRIC     a time series of numbers. "ALB RequestCount was 412 at 14:05."
#              Namespace + MetricName + Dimensions identifies one uniquely.
#              e.g. AWS/ApplicationELB / RequestCount / LoadBalancer=app/k8s-...
#
#   LOG        a timestamped line of text. "GET /restaurants 200 12ms"
#              Lives in a LOG GROUP, split into LOG STREAMS (one per source).
#              Queried with Logs Insights.
#
#   ALARM      watches ONE metric and changes state when a threshold is
#              breached for N consecutive periods. States: OK,
#              ALARM, INSUFFICIENT_DATA. An alarm can notify (SNS) or act
#              (autoscaling). An alarm firing is not an outage; it is an
#              opinion about a number.
#
#   DASHBOARD  a saved arrangement of metric widgets. Costs $3/month each,
#              which is why we build exactly one.
#
# The relationship: services emit METRICS and LOGS automatically. You create
# ALARMS on metrics and read LOGS when the alarm tells you where to look. The
# DASHBOARD is where you look first.
###############################################################################

###############################################################################
# SNS — how alarms reach you
###############################################################################

resource "aws_sns_topic" "alerts" {
  name = "${local.name}-alerts"

  # Server-side encryption for messages at rest.
  kms_master_key_id = aws_kms_key.main.id

  tags = { Name = "${local.name}-alerts" }
}

resource "aws_sns_topic_subscription" "email" {
  # Only create the subscription if an address was supplied.
  count = var.alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email

  # -------------------------------------------------------------------------
  # YOU MUST CONFIRM THIS BY EMAIL.
  #
  # AWS sends "AWS Notification - Subscription Confirmation" to the address.
  # Until you click the link, the subscription sits in PendingConfirmation and
  # delivers NOTHING. Terraform will still report success — it created the
  # subscription request, which is all it can do.
  #
  # Check status with:
  #   aws sns list-subscriptions-by-topic --topic-arn <arn>
  # -------------------------------------------------------------------------
}

###############################################################################
# APPLICATION LOG GROUPS
###############################################################################
# Container Insights writes container stdout/stderr into
# /aws/containerinsights/<cluster>/application automatically. We create the
# group ourselves first so that retention is 7 days rather than "forever".
###############################################################################

resource "aws_cloudwatch_log_group" "container_application" {
  count = var.enable_container_insights ? 1 : 0

  name              = "/aws/containerinsights/${local.name}/application"
  retention_in_days = var.log_retention_days

  # NOTE: deliberately NOT KMS-encrypted. The CloudWatch agent running under
  # the node role would need kms:GenerateDataKey on our CMK, which means
  # widening the node role — and the node role is inherited by every pod. The
  # trade-off is not worth it for application stdout. Encrypt the things that
  # carry secrets (CloudTrail, WAF, flow logs); do not reflexively encrypt
  # everything.

  tags = { Name = "${local.name}-app-logs" }
}

###############################################################################
# ALARMS — EKS / nodes
###############################################################################
# These metrics come from the amazon-cloudwatch-observability addon. If
# enable_container_insights is false they never appear and these alarms sit in
# INSUFFICIENT_DATA forever.
###############################################################################

resource "aws_cloudwatch_metric_alarm" "node_cpu_high" {
  count = var.enable_container_insights ? 1 : 0

  alarm_name        = "${local.name}-node-cpu-high"
  alarm_description = "Worker node CPU above 80% for 10 minutes. Nodes are saturated — scale out or size up."

  namespace   = "ContainerInsights"
  metric_name = "node_cpu_utilization"
  dimensions  = { ClusterName = local.name }

  statistic           = "Average"
  period              = 300 # 5-minute buckets
  evaluation_periods  = 2   # ...must breach twice in a row (= 10 minutes)
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"

  # WHY evaluation_periods = 2 AND NOT 1:
  # A single 5-minute spike above 80% during an image pull or a rolling update
  # is normal. Requiring two consecutive periods filters transients. This is
  # the difference between an alarm you act on and an alarm you mute.

  # What to do when there is no data at all (e.g. the addon is still starting).
  # "notBreaching" avoids a flood of INSUFFICIENT_DATA notifications on a
  # freshly built cluster.
  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = { Name = "${local.name}-node-cpu-high" }
}

resource "aws_cloudwatch_metric_alarm" "node_memory_high" {
  count = var.enable_container_insights ? 1 : 0

  alarm_name        = "${local.name}-node-memory-high"
  alarm_description = "Worker node memory above 80% for 10 minutes. Pods risk OOMKill / eviction."

  namespace   = "ContainerInsights"
  metric_name = "node_memory_utilization"
  dimensions  = { ClusterName = local.name }

  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = { Name = "${local.name}-node-memory-high" }
}

###############################################################################
# ALARMS — ALB
###############################################################################
# CHICKEN AND EGG: the ALB is created by the AWS Load Balancer Controller in
# Phase 6, so Terraform cannot know its ARN suffix on the first apply. These
# alarms are created only once you pass -var="alb_arn_suffix=..." — see the
# variable's description for how to find it.
###############################################################################

locals {
  alb_alarms_enabled = var.alb_arn_suffix != ""
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  count = local.alb_alarms_enabled ? 1 : 0

  alarm_name        = "${local.name}-alb-5xx"
  alarm_description = "More than 10 HTTP 5xx responses from targets in 5 minutes. The application is erroring."

  namespace   = "AWS/ApplicationELB"
  metric_name = "HTTPCode_Target_5XX_Count"
  dimensions  = { LoadBalancer = var.alb_arn_suffix }

  # Sum, not Average. This metric is a COUNT — averaging counts is meaningless.
  # Knowing which statistic fits which metric is a real skill:
  #   counts      -> Sum
  #   utilisation -> Average
  #   latency     -> p95 / p99, almost never Average
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 10
  comparison_operator = "GreaterThanThreshold"

  # No 5xx at all means the metric is not published — that is GOOD, not
  # missing data. Without this the alarm would sit in INSUFFICIENT_DATA
  # whenever the app is perfectly healthy, which is exactly backwards.
  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = { Name = "${local.name}-alb-5xx" }
}

resource "aws_cloudwatch_metric_alarm" "alb_latency" {
  count = local.alb_alarms_enabled ? 1 : 0

  alarm_name        = "${local.name}-alb-latency"
  alarm_description = "p95 target response time above 2 seconds for 10 minutes."

  namespace   = "AWS/ApplicationELB"
  metric_name = "TargetResponseTime"
  dimensions  = { LoadBalancer = var.alb_arn_suffix }

  # extended_statistic instead of statistic: p95 means "95% of requests were
  # faster than this". An AVERAGE hides the slow tail completely — a service
  # where 5% of requests take 30 seconds can have a healthy-looking average.
  extended_statistic  = "p95"
  period              = 300
  evaluation_periods  = 2
  threshold           = 2 # seconds
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = { Name = "${local.name}-alb-latency" }
}

resource "aws_cloudwatch_metric_alarm" "alb_4xx" {
  count = local.alb_alarms_enabled ? 1 : 0

  alarm_name        = "${local.name}-alb-4xx"
  alarm_description = "More than 50 HTTP 4xx in 5 minutes. Could be scanning, a broken client, or WAF-adjacent noise."

  namespace   = "AWS/ApplicationELB"
  metric_name = "HTTPCode_Target_4XX_Count"
  dimensions  = { LoadBalancer = var.alb_arn_suffix }

  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 50
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = { Name = "${local.name}-alb-4xx" }
}

###############################################################################
# ALARMS — RDS
###############################################################################

resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  alarm_name        = "${local.name}-rds-cpu-high"
  alarm_description = "RDS CPU above 80% for 10 minutes. On a t3.micro this also burns CPU credits."

  namespace   = "AWS/RDS"
  metric_name = "CPUUtilization"
  dimensions  = { DBInstanceIdentifier = aws_db_instance.main.identifier }

  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "breaching" # RDS always publishes CPU. Missing data
  # here means the instance is gone or
  # unreachable, which IS a problem.

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = { Name = "${local.name}-rds-cpu-high" }
}

resource "aws_cloudwatch_metric_alarm" "rds_connections_high" {
  alarm_name        = "${local.name}-rds-connections-high"
  alarm_description = "Database connections above 40. db.t3.micro's max_connections is ~85; a connection leak will exhaust it."

  namespace   = "AWS/RDS"
  metric_name = "DatabaseConnections"
  dimensions  = { DBInstanceIdentifier = aws_db_instance.main.identifier }

  # Maximum, not Average: a brief exhaustion spike is the failure. Averaging it
  # away means you find out from users instead of from the alarm.
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 2
  threshold           = 40
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = { Name = "${local.name}-rds-connections-high" }
}

resource "aws_cloudwatch_metric_alarm" "rds_storage_low" {
  alarm_name        = "${local.name}-rds-storage-low"
  alarm_description = "Less than 2 GiB free storage. A full disk takes PostgreSQL down hard and recovery is slow."

  namespace   = "AWS/RDS"
  metric_name = "FreeStorageSpace"
  dimensions  = { DBInstanceIdentifier = aws_db_instance.main.identifier }

  statistic = "Average"
  period    = 300

  # FreeStorageSpace is reported in BYTES. 2 GiB = 2 * 1024^3.
  # Writing the arithmetic out is clearer than pasting 2147483648.
  threshold           = 2 * 1024 * 1024 * 1024
  evaluation_periods  = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = { Name = "${local.name}-rds-storage-low" }
}

###############################################################################
# ALARM — WAF
###############################################################################

resource "aws_cloudwatch_metric_alarm" "waf_blocked_spike" {
  alarm_name        = "${local.name}-waf-blocked-spike"
  alarm_description = "WAF blocked more than 20 requests in 5 minutes. Either someone is probing you, or a rule is producing false positives on legitimate traffic. Check the WAF sampled requests to tell which."

  namespace   = "AWS/WAFV2"
  metric_name = "BlockedRequests"

  # WAF metric dimensions are fixed and all three are required:
  #   WebACL = the ACL name
  #   Rule   = a specific rule name, or "ALL" for the ACL total
  #   Region = the region, lowercase, for REGIONAL scope ACLs
  dimensions = {
    WebACL = aws_wafv2_web_acl.main.name
    Rule   = "ALL"
    Region = local.region
  }

  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 20
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = { Name = "${local.name}-waf-blocked-spike" }
}

###############################################################################
# DASHBOARD — one place to look first
###############################################################################
# A dashboard is just a JSON document describing widgets on a 24-column grid.
# x/y/width/height are grid units, not pixels.
#
# We build it with jsonencode() rather than a heredoc so Terraform can
# interpolate resource names, and so a syntax error is caught at plan time.
###############################################################################


# -----------------------------------------------------------------------------
# WHY THIS IS BUILT WITH for/if AND NOT A TERNARY
# -----------------------------------------------------------------------------
# The obvious way to build a conditional widget list is:
#
#   widgets = concat(
#     var.enable_container_insights ? [widget_a, widget_b] : [],
#     ...
#   )
#
# That FAILS to validate:
#
#   Error: Inconsistent conditional result types
#   The 'true' tuple has length 2, but the 'false' tuple has length 0.
#
# HCL's ternary requires both branches to have the SAME type, and a 2-element
# tuple and a 0-element tuple are different types. (Lists would unify; tuples
# of literal objects do not.)
#
# The fix: never use a conditional. Build one flat list where every element
# carries a `show` flag, then filter with a for-expression. A for-expression
# over a tuple can drop elements freely, because it produces a new tuple
# rather than having to unify two branches.
#
# This bites people constantly. Worth recognising the error message on sight.
# -----------------------------------------------------------------------------

locals {
  # Each entry: show = whether to include it, w = the widget itself.
  # Grid is 24 columns wide; x/y/width/height are grid units, not pixels.
  _dashboard_candidates = [

    # ---------------- Row 1 (y=0): EKS ---------------------------------------
    {
      show = var.enable_container_insights
      w = {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "EKS - Node CPU / Memory %"
          region = local.region
          view   = "timeSeries"
          stat   = "Average"
          period = 300
          metrics = [
            ["ContainerInsights", "node_cpu_utilization", "ClusterName", local.name],
            [".", "node_memory_utilization", ".", "."],
          ]
          yAxis       = { left = { min = 0, max = 100 } }
          annotations = { horizontal = [{ label = "Alarm threshold", value = 80 }] }
        }
      }
    },
    {
      show = var.enable_container_insights
      w = {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "EKS - Nodes & container restarts"
          region = local.region
          view   = "timeSeries"
          stat   = "Average"
          period = 300
          metrics = [
            ["ContainerInsights", "cluster_node_count", "ClusterName", local.name],
            [".", "cluster_failed_node_count", ".", "."],
            [".", "pod_number_of_container_restarts", ".", "."],
          ]
        }
      }
    },

    # ---------------- Row 2 (y=6): ALB ---------------------------------------
    {
      show = local.alb_alarms_enabled
      w = {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "ALB - Request count & HTTP status classes"
          region = local.region
          view   = "timeSeries"
          stat   = "Sum"
          period = 300
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix],
            [".", "HTTPCode_Target_2XX_Count", ".", "."],
            [".", "HTTPCode_Target_4XX_Count", ".", "."],
            [".", "HTTPCode_Target_5XX_Count", ".", "."],
          ]
        }
      }
    },
    {
      show = local.alb_alarms_enabled
      w = {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "ALB - Target response time (avg / p95 / p99)"
          region = local.region
          view   = "timeSeries"
          period = 300
          # "..." repeats the preceding metric's namespace/name/dimensions and
          # only overrides the statistic. Saves retyping the whole tuple.
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { stat = "Average" }],
            ["...", { stat = "p95" }],
            ["...", { stat = "p99" }],
          ]
          yAxis = { left = { label = "seconds", min = 0 } }
        }
      }
    },

    # ---------------- Row 3 (y=12): RDS --------------------------------------
    {
      show = true
      w = {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 8
        height = 6
        properties = {
          title       = "RDS - CPU %"
          region      = local.region
          view        = "timeSeries"
          stat        = "Average"
          period      = 300
          metrics     = [["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.main.identifier]]
          yAxis       = { left = { min = 0, max = 100 } }
          annotations = { horizontal = [{ label = "Alarm", value = 80 }] }
        }
      }
    },
    {
      show = true
      w = {
        type   = "metric"
        x      = 8
        y      = 12
        width  = 8
        height = 6
        properties = {
          title       = "RDS - Database connections"
          region      = local.region
          view        = "timeSeries"
          stat        = "Maximum"
          period      = 300
          metrics     = [["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", aws_db_instance.main.identifier]]
          annotations = { horizontal = [{ label = "Alarm", value = 40 }] }
        }
      }
    },
    {
      show = true
      w = {
        type   = "metric"
        x      = 16
        y      = 12
        width  = 8
        height = 6
        properties = {
          title   = "RDS - Free storage (bytes)"
          region  = local.region
          view    = "timeSeries"
          stat    = "Average"
          period  = 300
          metrics = [["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", aws_db_instance.main.identifier]]
        }
      }
    },

    # ---------------- Row 4 (y=18): WAF --------------------------------------
    {
      show = true
      w = {
        type   = "metric"
        x      = 0
        y      = 18
        width  = 12
        height = 6
        properties = {
          title  = "WAF - Allowed vs Blocked"
          region = local.region
          view   = "timeSeries"
          stat   = "Sum"
          period = 300
          metrics = [
            ["AWS/WAFV2", "AllowedRequests", "WebACL", aws_wafv2_web_acl.main.name, "Rule", "ALL", "Region", local.region],
            [".", "BlockedRequests", ".", ".", ".", ".", ".", "."],
          ]
        }
      }
    },
    {
      show = true
      w = {
        type   = "metric"
        x      = 12
        y      = 18
        width  = 12
        height = 6
        properties = {
          title  = "WAF - Blocks by rule group"
          region = local.region
          view   = "timeSeries"
          stat   = "Sum"
          period = 300
          metrics = [
            ["AWS/WAFV2", "BlockedRequests", "WebACL", aws_wafv2_web_acl.main.name, "Rule", "AWSManagedRulesSQLiRuleSet", "Region", local.region],
            [".", ".", ".", ".", ".", "AWSManagedRulesCommonRuleSet", ".", "."],
            [".", ".", ".", ".", ".", "AWSManagedRulesKnownBadInputsRuleSet", ".", "."],
            [".", ".", ".", ".", ".", "RateLimitPerIP", ".", "."],
          ]
        }
      }
    },

    # ---------------- Row 5 (y=24): live backend log tail --------------------
    {
      show = var.enable_container_insights
      w = {
        type   = "log"
        x      = 0
        y      = 24
        width  = 24
        height = 6
        properties = {
          title  = "Backend - most recent 50 log lines"
          region = local.region
          view   = "table"
          # A CloudWatch Logs Insights query embedded in the dashboard.
          # Identical syntax to the Logs Insights console.
          query = join("", [
            "SOURCE '/aws/containerinsights/${local.name}/application'",
            " | fields @timestamp, kubernetes.container_name, log",
            " | filter kubernetes.container_name = 'backend'",
            " | sort @timestamp desc",
            " | limit 50",
          ])
        }
      }
    },
  ]

  # Drop everything whose `show` is false, keep only the widget itself.
  dashboard_widgets = [for c in local._dashboard_candidates : c.w if c.show]
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.name}-overview"
  dashboard_body = jsonencode({ widgets = local.dashboard_widgets })
}
