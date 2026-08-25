#!/usr/bin/env bash
# =============================================================================
# build-and-push.sh — build both images and push them to ECR
# =============================================================================
# Usage:
#   ./scripts/build-and-push.sh              # build + push both, tag :latest
#   ./scripts/build-and-push.sh v1.2.0       # tag with a version as well
#
# Run from the repo root (or anywhere — it resolves its own location).
# =============================================================================

# -e  exit on any command failure
# -u  treat an unset variable as an error (catches typos in $VARNAMES)
# -o pipefail  a pipeline fails if ANY stage fails, not just the last one
#
# These three lines are the difference between a script that stops at the
# problem and one that carries on and does something worse.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

REGION="${AWS_REGION:-us-east-1}"
EXTRA_TAG="${1:-}"

echo "==> Resolving account and registry"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
echo "    account:  $ACCOUNT_ID"
echo "    registry: $REGISTRY"

# -----------------------------------------------------------------------------
# ECR login.
#
# The token is valid for 12 hours. When a push suddenly fails with
# "no basic auth credentials", this is almost always why — just run it again.
# -----------------------------------------------------------------------------
echo "==> Logging Docker in to ECR"
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

build_and_push() {
  local name="$1"       # frontend | backend
  local context="$2"    # ./frontend | ./backend
  local repo="${REGISTRY}/jollof-run/${name}"

  echo ""
  echo "==> Building ${name}"

  # --platform linux/amd64 is IMPORTANT and easy to miss.
  #
  # If you are on an Apple Silicon Mac, Docker defaults to linux/arm64. The
  # image builds and runs perfectly on your laptop, then every pod on your
  # x86 EKS nodes fails with:
  #     exec /usr/bin/... : exec format error
  # which gives no hint whatsoever that it is an architecture mismatch.
  #
  # On Windows/Intel this flag is a no-op, so it is safe to always pass.
  docker build \
    --platform linux/amd64 \
    -t "${name}:local" \
    -t "${repo}:latest" \
    ${EXTRA_TAG:+-t "${repo}:${EXTRA_TAG}"} \
    "$context"

  echo "==> Pushing ${repo}:latest"
  docker push "${repo}:latest"

  if [[ -n "$EXTRA_TAG" ]]; then
    echo "==> Pushing ${repo}:${EXTRA_TAG}"
    docker push "${repo}:${EXTRA_TAG}"
  fi
}

build_and_push frontend ./frontend
build_and_push backend  ./backend

echo ""
echo "============================================================"
echo " Images pushed."
echo ""
echo " Roll the deployments so the new images are pulled:"
echo "   kubectl rollout restart deployment/frontend -n jollof-run"
echo "   kubectl rollout restart deployment/backend  -n jollof-run"
echo ""
echo " Watch the rollout:"
echo "   kubectl rollout status deployment/frontend -n jollof-run"
echo "============================================================"
