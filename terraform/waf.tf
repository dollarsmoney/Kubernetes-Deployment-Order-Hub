###############################################################################
# waf.tf — AWS WAFv2 Web ACL in front of the ALB
###############################################################################
#
#   Request arrives
#        |
#        v
#   +---------------------------------------------------------------+
#   |  WEB ACL  "jollof-run-web-acl"                                 |
#   |                                                                |
#   |  Rules are evaluated IN PRIORITY ORDER, lowest number first.   |
#   |  The FIRST rule that returns a terminating action (Block or    |
#   |  Allow) ends evaluation. Count never terminates.               |
#   |                                                                |
#   |   p1  AWSManagedRulesCommonRuleSet      XSS, LFI, bad paths    |
#   |   p2  AWSManagedRulesSQLiRuleSet        SQL injection  <-- key |
#   |   p3  AWSManagedRulesKnownBadInputsRuleSet  Log4Shell etc.     |
#   |   p4  RateLimitPerIP                    2000 req / 5 min / IP  |
#   |                                                                |
#   |  DEFAULT ACTION: ALLOW                                         |
#   |  (nothing matched -> the request proceeds)                     |
#   +---------------------------------------------------------------+
#        |                                    |
#     ALLOW                                 BLOCK
#        v                                    v
#      ALB                            403 returned by WAF.
#        v                            The ALB, the cluster, and the
#   Kubernetes Ingress                application never see the request.
#
# ATTACHMENT: this Web ACL is NOT associated with the ALB here. The ALB is
# created by the AWS Load Balancer Controller, not by Terraform, so its ARN
# does not exist at plan time. Instead Terraform OUTPUTS the ACL ARN and
# kubernetes/ingress.yaml references it with:
#
#   alb.ingress.kubernetes.io/wafv2-acl-arn: <arn>
#
# Being able to explain that ordering problem is worth a lot in an interview.
###############################################################################

resource "aws_wafv2_web_acl" "main" {
  name        = "${local.name}-web-acl"
  description = "Managed protections for ${local.name}: SQLi, XSS, known-bad inputs, rate limiting"

  # REGIONAL = for ALB, API Gateway, AppSync, Cognito.
  # CLOUDFRONT = for CloudFront distributions, and MUST be created in
  # us-east-1 regardless of where the rest of your infrastructure lives.
  scope = "REGIONAL"

  # -------------------------------------------------------------------------
  # DEFAULT ACTION
  # -------------------------------------------------------------------------
  # allow = "permit anything no rule blocked"  (a blocklist / negative model)
  # block = "deny anything no rule allowed"    (an allowlist / positive model)
  #
  # Allowlisting is stronger but requires you to enumerate every legitimate
  # request shape up front. For a public website, blocklisting is the norm.
  # -------------------------------------------------------------------------
  default_action {
    allow {}
  }

  #############################################################################
  # PRIORITY 1 — Core rule set
  #############################################################################
  # AWS's baseline protections: cross-site scripting, local/remote file
  # inclusion, path traversal, oversized bodies, missing User-Agent, and a
  # long tail of generally-hostile request shapes.
  #############################################################################

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    # override_action vs action:
    #   - `action` applies to rules YOU write.
    #   - `override_action` applies to MANAGED RULE GROUPS.
    #
    # `none {}` means "let the rule group's own actions stand" — i.e. its rules
    # block when they say block.
    #
    # `count {}` would downgrade EVERY rule in the group to count-only. That is
    # the correct way to deploy a new rule group: run it in count mode, watch
    # the metrics for a week to see what it WOULD have blocked, then switch to
    # none{}. Skipping that step is how you take down your own site.
    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"

        # ---------------------------------------------------------------------
        # Per-rule overrides live here. Two common false positives:
        #
        #   rule_action_override {
        #     name = "SizeRestrictions_BODY"     # blocks bodies > 8KB
        #     action_to_use { count {} }         # breaks large form/file POSTs
        #   }
        #   rule_action_override {
        #     name = "NoUserAgent_HEADER"        # blocks curl -H "User-Agent:"
        #     action_to_use { count {} }         # and some health checkers
        #   }
        #
        # Our app posts nothing and our health checks send a User-Agent, so
        # neither is needed. Uncomment if legitimate traffic starts 403ing.
        # ---------------------------------------------------------------------
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-common-rules"
      sampled_requests_enabled   = true
    }
  }

  #############################################################################
  # PRIORITY 2 — SQL injection
  #############################################################################
  # The rule group you specifically asked for. It inspects query strings,
  # request bodies, cookies, and URI paths for SQL syntax patterns:
  #   ' OR 1=1--        UNION SELECT        ; DROP TABLE
  #   /**/ comments     sleep()/benchmark() timing payloads
  #   hex and URL-encoded variants of all of the above
  #
  # WHAT THIS IS NOT: a fix for SQL injection. It is a pattern matcher. It
  # blocks payloads that LOOK like attacks. A sufficiently novel encoding gets
  # through, and it cannot see an injection that does not resemble one.
  #
  # The actual fix is parameterized queries, which is what backend/db.py uses.
  # WAF is the outer layer. It is never the control.
  #############################################################################

  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-sqli-rules"
      sampled_requests_enabled   = true
    }
  }

  #############################################################################
  # PRIORITY 3 — Known bad inputs
  #############################################################################
  # Exploit payloads for specific published CVEs — Log4Shell (${jndi:ldap://}),
  # Spring4Shell, various deserialisation attacks. AWS updates this group as
  # new vulnerabilities appear, which is the main argument for using managed
  # groups over writing your own regexes.
  #############################################################################

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  #############################################################################
  # PRIORITY 4 — Rate limiting (a rule we write ourselves)
  #############################################################################
  # Counts requests per source IP over a rolling 5-minute window. Above the
  # limit, that IP is blocked until its rate falls back below it.
  #
  # This is the one rule here that defends AVAILABILITY rather than integrity —
  # it blunts brute-force and scraping. It is not DDoS protection; that is
  # AWS Shield's job.
  #
  # Note this is a rule WE authored, so it uses `action`, not `override_action`.
  #############################################################################

  rule {
    name     = "RateLimitPerIP"
    priority = 4

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit = var.waf_rate_limit # requests per 5 minutes per IP
        # IP = use the source IP as WAF sees it.
        # FORWARDED_IP = read X-Forwarded-For instead — correct if there is a
        # CDN or proxy in front of the ALB, dangerous otherwise since the
        # header is client-controlled and trivially spoofed.
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  #############################################################################
  # ACL-level visibility — the aggregate metrics for the whole Web ACL
  #############################################################################
  # Publishes AllowedRequests, BlockedRequests, CountedRequests, and
  # PassedRequests to the AWS/WAFV2 CloudWatch namespace. Phase 10's alarms
  # and dashboard read these.
  #
  # sampled_requests_enabled stores a rolling sample of matched requests,
  # viewable in the console under "Sampled requests". This is how you see the
  # ACTUAL payload that was blocked — indispensable when debugging a false
  # positive.
  #############################################################################

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name}-web-acl"
    sampled_requests_enabled   = true
  }

  tags = { Name = "${local.name}-web-acl" }
}

###############################################################################
# WAF LOGGING — full request records, not just counters
###############################################################################
# Metrics tell you 47 requests were blocked. Logs tell you which IPs, which
# URIs, which rule, and what the payload was.
#
# NAMING CONSTRAINT: a CloudWatch log group used as a WAF destination MUST be
# named with the prefix "aws-waf-logs-". This is enforced by the WAF API, not
# a convention. Get it wrong and you receive:
#   WAFInvalidParameterException: The ARN isn't valid.
###############################################################################

resource "aws_cloudwatch_log_group" "waf" {
  name              = "aws-waf-logs-${local.name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.main.arn

  tags = { Name = "${local.name}-waf-logs" }
}

resource "aws_wafv2_web_acl_logging_configuration" "main" {
  resource_arn            = aws_wafv2_web_acl.main.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]

  # Do not write these header values to the log. Logs are lower-security than
  # the traffic itself, and an auth token sitting in a log group for 7 days is
  # a real leak. Redacted fields appear as "REDACTED" in the log entry.
  redacted_fields {
    single_header {
      name = "authorization"
    }
  }

  redacted_fields {
    single_header {
      name = "cookie"
    }
  }

  # -------------------------------------------------------------------------
  # Log only what is interesting. Without a filter, WAF logs EVERY request,
  # which at any real traffic level dwarfs every other cost in this project.
  # Here: log everything WAF blocked, and drop the rest.
  #
  # Remove this block temporarily if you want to confirm that allowed requests
  # are flowing through — then put it back.
  # -------------------------------------------------------------------------
  logging_filter {
    default_behavior = "DROP"

    filter {
      behavior    = "KEEP"
      requirement = "MEETS_ANY"

      condition {
        action_condition {
          action = "BLOCK"
        }
      }

      condition {
        action_condition {
          action = "COUNT"
        }
      }
    }
  }
}
