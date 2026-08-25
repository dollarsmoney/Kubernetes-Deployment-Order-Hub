#!/usr/bin/env bash
# =============================================================================
# waf-test.sh — verify AWS WAF is blocking SQL-injection-shaped requests
# =============================================================================
#
# SCOPE AND AUTHORISATION
#
# This tests YOUR OWN infrastructure, in YOUR OWN AWS account. It sends a
# handful of requests carrying payloads that WAF's managed rules recognise, and
# checks that they are rejected at the edge.
#
# It is NOT an attack tool. Nothing here attempts to exploit anything:
#   - no automated fuzzing, no evasion, no encoding tricks
#   - the payloads are the textbook examples WAF rules are written against
#   - even if one reached the application, db.py uses bound parameters, so the
#     value would be searched for as literal text
#
# Only ever point this at a host you own.
#
# Usage:
#   ./scripts/waf-test.sh                        # auto-detect the ALB
#   ./scripts/waf-test.sh k8s-jollof-xxx.us-east-1.elb.amazonaws.com
# =============================================================================

set -uo pipefail   # NOT -e: we expect non-2xx responses and must not abort

REGION="${AWS_REGION:-us-east-1}"

# -----------------------------------------------------------------------------
# Resolve the ALB hostname
# -----------------------------------------------------------------------------
HOST="${1:-}"

if [[ -z "$HOST" ]]; then
  echo "==> Finding the ALB created by the Ingress"
  HOST="$(kubectl get ingress jollof-run-ingress -n jollof-run \
            -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
fi

if [[ -z "$HOST" ]]; then
  echo "ERROR: could not determine the ALB hostname."
  echo "  Pass it explicitly:  ./scripts/waf-test.sh <alb-dns-name>"
  echo "  Or check:            kubectl get ingress -n jollof-run"
  exit 1
fi

BASE="http://${HOST}"
echo "    target: $BASE"
echo ""

# -----------------------------------------------------------------------------
# probe <label> <expected-status> <path>
# -----------------------------------------------------------------------------
probe() {
  local label="$1" expected="$2" path="$3"

  # -s silent, -o /dev/null discard body, -w print only the status code
  # --max-time so a hung request cannot stall the whole script
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "${BASE}${path}" || echo 000)"

  if [[ "$code" == "$expected" ]]; then
    printf '  \033[32mPASS\033[0m  %-46s got %s (expected %s)\n' "$label" "$code" "$expected"
  else
    printf '  \033[31mFAIL\033[0m  %-46s got %s (expected %s)\n' "$label" "$code" "$expected"
  fi
}

echo "============================================================"
echo " PART 1 — legitimate traffic must still work"
echo "============================================================"
echo " These prove WAF is not simply blocking everything, which is"
echo " the failure mode nobody checks for."
echo ""

probe "homepage"                      200 "/"
probe "health endpoint"               200 "/api/health"
probe "restaurant list"               200 "/api/restaurants"
probe "single restaurant"             200 "/api/restaurants/1"
probe "food list"                     200 "/api/foods"
probe "benign search (jollof)"        200 "/api/restaurants?search=jollof"
probe "benign search with space"      200 "/api/restaurants?search=mama%20nkechi"

echo ""
echo "============================================================"
echo " PART 2 — SQL-injection payloads must be BLOCKED (403)"
echo "============================================================"
echo " A 403 here is returned BY WAF, at the edge. The ALB, the"
echo " cluster, and the application never see these requests."
echo ""

# The classic tautology. Intended to make a WHERE clause always true.
probe "' OR 1=1--"                    403 "/api/restaurants?search=%27%20OR%201%3D1--"

# UNION-based extraction, the standard data-exfiltration shape.
probe "UNION SELECT"                  403 "/api/restaurants?search=%27%20UNION%20SELECT%20NULL,NULL--"

# Stacked statement. This is what people picture when they hear "SQL injection".
probe "; DROP TABLE"                  403 "/api/restaurants?search=1%3B%20DROP%20TABLE%20foods--"

# Blind/time-based probing.
probe "SLEEP() timing probe"          403 "/api/restaurants?search=1%27%20AND%20SLEEP(5)--"

# Reading database metadata.
probe "information_schema"            403 "/api/restaurants?search=%27%20UNION%20SELECT%20table_name%20FROM%20information_schema.tables--"

# Comment-based filter evasion.
probe "inline comment evasion"        403 "/api/restaurants?search=%27%2F%2A%2A%2FOR%2F%2A%2A%2F1%3D1--"

echo ""
echo "============================================================"
echo " PART 3 — other managed rule groups"
echo "============================================================"

# CommonRuleSet: reflected XSS.
probe "XSS <script> tag"              403 "/api/restaurants?search=%3Cscript%3Ealert(1)%3C%2Fscript%3E"

# CommonRuleSet: path traversal.
probe "path traversal"                403 "/api/restaurants?search=..%2F..%2F..%2Fetc%2Fpasswd"

# KnownBadInputs: Log4Shell.
probe "Log4Shell JNDI"                403 "/api/restaurants?search=%24%7Bjndi%3Aldap%3A%2F%2Fx.com%2Fa%7D"

echo ""
echo "============================================================"
echo " WHAT A FAILURE MEANS"
echo "============================================================"
cat <<'EOF'

  PART 1 fails (blocked when it should not be)
    A managed rule is producing a FALSE POSITIVE on legitimate traffic.
    Find out which rule:
      AWS Console -> WAF -> Web ACLs -> jollof-run-web-acl
        -> Sampled requests
    Then downgrade that specific rule to count-only with a
    rule_action_override block in terraform/waf.tf.

  PART 2 or 3 fails with 200 (allowed when it should be blocked)
    Almost always: the WAF is not actually attached to the ALB.
    Check the annotation is present and uncommented:
      kubectl get ingress jollof-run-ingress -n jollof-run \
        -o jsonpath='{.metadata.annotations}' | tr ',' '\n' | grep wafv2
    Then confirm the association from the AWS side:
      aws wafv2 get-web-acl-for-resource --resource-arn <alb-arn> \
        --region us-east-1

  Everything returns 000
    curl could not connect at all. The ALB may still be provisioning
    (allow 3 minutes), or the target group has no healthy targets:
      kubectl get pods -n jollof-run
      kubectl get ingress -n jollof-run

  -----------------------------------------------------------------
  THE POINT TO TAKE AWAY

  WAF blocking these payloads is defence in depth, not the fix.
  backend/db.py passes every value as a BOUND PARAMETER, so the
  database never parses user input as SQL. Turn WAF off entirely and
  the application is still not injectable.

  Relying on WAF instead of parameterization would be a vulnerability
  with a speed bump in front of it.
  -----------------------------------------------------------------
EOF

echo ""
echo "==> See the blocks in CloudWatch:"
echo "    aws logs tail aws-waf-logs-jollof-run --region ${REGION} --since 5m --format short"
