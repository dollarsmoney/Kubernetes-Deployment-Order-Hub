#!/usr/bin/env bash
# =============================================================================
# generate-traffic.sh — drive load so CloudWatch metrics have something to show
# =============================================================================
# Phase 10 asks you to watch ALB RequestCount climb. An idle site publishes
# nothing, so there is nothing to watch. This produces a modest, steady stream
# of legitimate requests.
#
# Usage:
#   ./scripts/generate-traffic.sh              # 5 minutes, ~4 req/sec
#   ./scripts/generate-traffic.sh 600 10       # 10 minutes, ~10 req/sec
#
# DELIBERATELY MODEST. The rate stays well under the WAF rate-based rule
# (2000 requests per 5 minutes per IP, set by var.waf_rate_limit). At the
# default 4/sec you reach ~1200 in 5 minutes — enough to move the graphs,
# not enough to block your own IP.
#
# If you DO want to see the rate limiter fire, raise the rate to 10+/sec and
# run for a full 5 minutes. Your IP will then get 403s for a few minutes. That
# is a legitimate test of your own environment, and it recovers on its own.
# =============================================================================

set -uo pipefail

DURATION="${1:-300}"     # seconds
RATE="${2:-4}"           # requests per second (approximate)

echo "==> Finding the ALB"
HOST="$(kubectl get ingress jollof-run-ingress -n jollof-run \
          -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"

if [[ -z "$HOST" ]]; then
  echo "ERROR: no ALB found. Is the Ingress created?"
  echo "  kubectl get ingress -n jollof-run"
  exit 1
fi

BASE="http://${HOST}"

# A realistic mix: mostly page loads, some API calls, a few 404s so the
# HTTPCode_Target_4XX_Count metric is not flat either.
PATHS=(
  "/"
  "/"
  "/"
  "/api/restaurants"
  "/api/restaurants"
  "/api/foods"
  "/api/restaurants/1"
  "/api/restaurants/3"
  "/api/categories"
  "/api/health"
  "/api/restaurants?search=suya"
  "/api/restaurants/9999"     # 404 on purpose
)

END=$((SECONDS + DURATION))
COUNT=0
SLEEP_FOR="$(awk -v r="$RATE" 'BEGIN{printf "%.3f", 1/r}')"

echo "    target:   $BASE"
echo "    duration: ${DURATION}s at ~${RATE} req/s"
echo "    press Ctrl-C to stop early"
echo ""

# Report progress on Ctrl-C rather than dying silently.
trap 'echo ""; echo "==> Stopped after ${COUNT} requests."; exit 0' INT

while (( SECONDS < END )); do
  path="${PATHS[$((RANDOM % ${#PATHS[@]}))]}"

  curl -s -o /dev/null --max-time 10 "${BASE}${path}" &

  COUNT=$((COUNT + 1))

  # Progress line every 50 requests, overwriting itself.
  if (( COUNT % 50 == 0 )); then
    printf '\r    %d requests sent, %ds remaining   ' "$COUNT" "$((END - SECONDS))"
  fi

  sleep "$SLEEP_FOR"
done

wait
echo ""
echo ""
echo "==> Done. ${COUNT} requests sent."
echo ""
cat <<'EOF'
============================================================
 NOW GO AND LOOK

 CloudWatch metrics lag by 2-5 minutes. Wait, then:

 1. The dashboard
      terraform -chdir=terraform output -raw dashboard_url

 2. ALB request count from the CLI
      aws cloudwatch get-metric-statistics \
        --namespace AWS/ApplicationELB \
        --metric-name RequestCount \
        --dimensions Name=LoadBalancer,Value=<alb-arn-suffix> \
        --start-time  $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%S) \
        --end-time    $(date -u +%Y-%m-%dT%H:%M:%S) \
        --period 300 --statistics Sum --region us-east-1

 3. Application logs
      kubectl logs -n jollof-run -l app=backend --tail=50

 4. The same logs in CloudWatch Logs Insights
      Console -> CloudWatch -> Logs Insights
      Log group: /aws/containerinsights/jollof-run/application

        fields @timestamp, log
        | filter kubernetes.container_name = "backend"
        | filter log like /status=200/
        | stats count() by bin(1m)

 WHAT YOU SHOULD SEE
   RequestCount            a clear spike over the run window
   HTTPCode_Target_2XX     tracking just under RequestCount
   HTTPCode_Target_4XX     a small steady trickle (the /9999 requests)
   TargetResponseTime      low, p95 typically under 100ms
============================================================
EOF
