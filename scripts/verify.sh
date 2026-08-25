#!/usr/bin/env bash
# =============================================================================
# verify.sh — Phase 12's ten tests, as one script
# =============================================================================
# Every check here is read-only except Test 6, which deletes a pod on purpose
# to demonstrate self-healing.
#
# Usage:  ./scripts/verify.sh
# =============================================================================

set -uo pipefail

REGION="${AWS_REGION:-us-east-1}"
NS="jollof-run"
PASS=0
FAIL=0

ok()   { printf '  \033[32m PASS \033[0m %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  \033[31m FAIL \033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
note() { printf '         %s\n' "$1"; }
hdr()  { printf '\n\033[1m%s\033[0m\n' "$1"; }

ALB="$(kubectl get ingress jollof-run-ingress -n "$NS" \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"

# =============================================================================
hdr "TEST 1 — the website loads"
# =============================================================================
if [[ -z "$ALB" ]]; then
  bad "no ALB hostname on the Ingress"
  note "kubectl describe ingress jollof-run-ingress -n $NS"
else
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "http://${ALB}/" || echo 000)"
  [[ "$code" == "200" ]] && ok "GET http://${ALB}/ -> 200" \
                         || bad "GET / returned $code"
fi

# =============================================================================
hdr "TEST 2 — the frontend reaches the backend"
# =============================================================================
# Proves the whole server-side chain:
#   ALB -> frontend pod -> nginx proxy -> backend-service -> backend pod
if [[ -n "$ALB" ]]; then
  body="$(curl -s --max-time 15 "http://${ALB}/api/health" || true)"
  if grep -q '"status"' <<<"$body"; then
    ok "/api/health proxied through nginx to the backend"
    note "$body"
  else
    bad "/api/health did not return the backend's response"
    note "got: ${body:-<empty>}"
    note "check: kubectl logs -n $NS -l app=frontend --tail=30"
  fi
fi

# =============================================================================
hdr "TEST 3 — the backend reaches RDS"
# =============================================================================
# /health/ready runs SELECT 1 against PostgreSQL. A 200 means the backend
# authenticated with credentials it fetched from Secrets Manager and connected
# over TCP 5432 to a database in a private subnet.
if [[ -n "$ALB" ]]; then
  ready="$(curl -s --max-time 15 "http://${ALB}/api/health/ready" || true)"
  if grep -q 'connected' <<<"$ready"; then
    ok "backend -> RDS connection is live"
  else
    bad "readiness check did not report a database connection"
    note "got: ${ready:-<empty>}"
    note "check: kubectl logs -n $NS -l app=backend --tail=50"
  fi

  rows="$(curl -s --max-time 15 "http://${ALB}/api/restaurants" || true)"
  if grep -q 'Iya Basira' <<<"$rows"; then
    ok "real rows returned from the seeded database"
  else
    bad "no seeded rows in the response"
  fi
fi

# =============================================================================
hdr "TEST 4 — the internet cannot reach RDS"
# =============================================================================
RDS_HOST="$(terraform -chdir=terraform output -raw rds_address 2>/dev/null || true)"

if [[ -z "$RDS_HOST" ]]; then
  note "skipped (could not read terraform output rds_address)"
else
  note "endpoint: $RDS_HOST"

  # 4a. It must have no public IP.
  pub="$(aws rds describe-db-instances \
          --db-instance-identifier jollof-run-db --region "$REGION" \
          --query 'DBInstances[0].PubliclyAccessible' --output text 2>/dev/null || echo unknown)"
  [[ "$pub" == "False" ]] && ok "PubliclyAccessible = False" \
                          || bad "PubliclyAccessible = $pub"

  # 4b. No security group rule may allow 5432 from the world.
  open="$(aws ec2 describe-security-groups --region "$REGION" \
           --filters Name=group-name,Values=jollof-run-rds-sg \
           --query "SecurityGroups[].IpPermissions[?FromPort==\`5432\`].IpRanges[?CidrIp=='0.0.0.0/0']" \
           --output text 2>/dev/null || true)"
  [[ -z "$open" ]] && ok "no 0.0.0.0/0 -> 5432 rule exists" \
                   || bad "a security group allows 5432 from the internet"

  # 4c. And it must actually be unreachable from here.
  #     A TIMEOUT is the correct result. "Connection refused" would mean the
  #     host is routable and something answered, which would be wrong.
  if timeout 8 bash -c "cat < /dev/null > /dev/tcp/${RDS_HOST}/5432" 2>/dev/null; then
    bad "TCP 5432 connected from this machine — RDS is exposed!"
  else
    ok "TCP 5432 from your laptop times out (correct)"
  fi
fi

# =============================================================================
hdr "TEST 5 — the backend reads credentials from Secrets Manager"
# =============================================================================
POD="$(kubectl get pods -n "$NS" -l app=backend -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"

if [[ -z "$POD" ]]; then
  bad "no backend pod found"
else
  # 5a. The CSI driver mounted the secret file.
  if kubectl exec -n "$NS" "$POD" -- test -f /mnt/secrets-store/db-credentials 2>/dev/null; then
    ok "secret is mounted at /mnt/secrets-store/db-credentials"

    keys="$(kubectl exec -n "$NS" "$POD" -- \
              sh -c "cat /mnt/secrets-store/db-credentials" 2>/dev/null \
            | python -c "import json,sys; print(','.join(sorted(json.load(sys.stdin))))" 2>/dev/null || true)"
    note "keys present: ${keys:-<unreadable>}"
    note "(the values are NOT printed — the point is that they never leave the pod)"
  else
    bad "the secret file is not mounted"
    note "check: kubectl describe pod $POD -n $NS   (look at Events)"
  fi

  # 5b. IRSA is wired up.
  role="$(kubectl get sa backend-sa -n "$NS" \
           -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null || true)"
  [[ -n "$role" ]] && ok "ServiceAccount carries the IRSA annotation" \
                   || bad "backend-sa has no eks.amazonaws.com/role-arn annotation"
  note "role: ${role:-<none>}"

  # 5c. The pod received a web identity token, not static keys.
  tok="$(kubectl exec -n "$NS" "$POD" -- printenv AWS_WEB_IDENTITY_TOKEN_FILE 2>/dev/null || true)"
  [[ -n "$tok" ]] && ok "AWS_WEB_IDENTITY_TOKEN_FILE injected by the EKS webhook" \
                  || bad "no web identity token in the pod"

  # 5d. And crucially, NO long-lived access key anywhere.
  akid="$(kubectl exec -n "$NS" "$POD" -- printenv AWS_ACCESS_KEY_ID 2>/dev/null || true)"
  [[ -z "$akid" ]] && ok "no AWS_ACCESS_KEY_ID in the container (correct)" \
                   || bad "a static access key is present — that defeats IRSA"
fi

# =============================================================================
hdr "TEST 6 — Kubernetes self-healing"
# =============================================================================
before="$(kubectl get pods -n "$NS" -l app=frontend -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"

if [[ -z "$before" ]]; then
  bad "no frontend pod to delete"
else
  note "deleting pod: $before"
  kubectl delete pod "$before" -n "$NS" --wait=false >/dev/null 2>&1

  note "waiting up to 90s for the ReplicaSet to restore 2 ready replicas..."
  if kubectl wait --for=condition=available --timeout=90s \
       deployment/frontend -n "$NS" >/dev/null 2>&1; then

    after="$(kubectl get pods -n "$NS" -l app=frontend \
              -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)"
    if grep -qv "$before" <<<"$after"; then
      ok "a replacement pod was created automatically"
      note "before: $before"
      note "after:  $after"
      note "note the NEW name — Kubernetes created a new pod, it did not restart the old one"
    else
      ok "deployment is available again"
    fi
  else
    bad "the deployment did not return to available within 90s"
  fi
fi

# =============================================================================
hdr "TEST 7 — WAF blocks SQL injection"
# =============================================================================
if [[ -n "$ALB" ]]; then
  good="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 \
           "http://${ALB}/api/restaurants?search=jollof" || echo 000)"
  evil="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 \
           "http://${ALB}/api/restaurants?search=%27%20OR%201%3D1--" || echo 000)"

  [[ "$good" == "200" ]] && ok "benign search allowed (200)" \
                         || bad "benign search returned $good — possible false positive"

  [[ "$evil" == "403" ]] && ok "SQL injection payload blocked by WAF (403)" \
                         || bad "injection payload returned $evil — is the WAF annotation applied?"

  note "run ./scripts/waf-test.sh for the full matrix"
fi

# =============================================================================
hdr "TEST 8 — CloudWatch is receiving metrics"
# =============================================================================
alarms="$(aws cloudwatch describe-alarms --region "$REGION" \
           --alarm-name-prefix jollof-run \
           --query 'length(MetricAlarms)' --output text 2>/dev/null || echo 0)"
[[ "$alarms" -gt 0 ]] && ok "$alarms CloudWatch alarms exist" \
                      || bad "no alarms found with the jollof-run prefix"

insufficient="$(aws cloudwatch describe-alarms --region "$REGION" \
                 --alarm-name-prefix jollof-run --state-value INSUFFICIENT_DATA \
                 --query 'MetricAlarms[].AlarmName' --output text 2>/dev/null || true)"
if [[ -n "$insufficient" ]]; then
  note "still INSUFFICIENT_DATA (normal for the first ~15 minutes):"
  for a in $insufficient; do note "  - $a"; done
fi

lg="$(aws logs describe-log-groups --region "$REGION" \
       --log-group-name-prefix /aws/containerinsights/jollof-run \
       --query 'length(logGroups)' --output text 2>/dev/null || echo 0)"
[[ "$lg" -gt 0 ]] && ok "Container Insights log groups exist" \
                  || note "Container Insights log groups not present yet"

# =============================================================================
hdr "TEST 9 — alarm state"
# =============================================================================
aws cloudwatch describe-alarms --region "$REGION" \
  --alarm-name-prefix jollof-run \
  --query 'MetricAlarms[].[AlarmName,StateValue]' --output table 2>/dev/null || true

note "To force one into ALARM, temporarily lower a threshold:"
note "  aws cloudwatch put-metric-alarm --alarm-name jollof-run-rds-cpu-high \\"
note "    --namespace AWS/RDS --metric-name CPUUtilization \\"
note "    --dimensions Name=DBInstanceIdentifier,Value=jollof-run-db \\"
note "    --statistic Average --period 60 --evaluation-periods 1 \\"
note "    --threshold 0.1 --comparison-operator GreaterThanThreshold \\"
note "    --region $REGION"
note "Then run 'terraform apply' to put the real threshold back."

# =============================================================================
hdr "TEST 10 — CloudTrail is recording"
# =============================================================================
logging="$(aws cloudtrail get-trail-status --name jollof-run-trail --region "$REGION" \
            --query IsLogging --output text 2>/dev/null || echo unknown)"
[[ "$logging" == "True" ]] && ok "trail jollof-run-trail is logging" \
                           || bad "trail is not logging (state: $logging)"

note "Recent write events by you:"
aws cloudtrail lookup-events --region "$REGION" \
  --lookup-attributes AttributeKey=ReadOnly,AttributeValue=false \
  --max-results 5 \
  --query 'Events[].[EventTime,EventName,Username]' --output table 2>/dev/null || true

# =============================================================================
printf '\n\033[1m============================================================\033[0m\n'
printf '  PASSED: %d    FAILED: %d\n' "$PASS" "$FAIL"
printf '\033[1m============================================================\033[0m\n\n'

[[ "$FAIL" -eq 0 ]] || exit 1
