#!/usr/bin/env bash
# Smoke-tests all exposed app routes. Exits non-zero on first failure.
# Run from the repo root after `make apply` + ArgoCD sync.

set -euo pipefail

PASS=0
FAIL=0

check() {
  local name=$1 url=$2
  local body
  if body=$(curl -fsL --max-time 5 "$url" 2>&1); then
    echo "PASS  $name  →  $(echo "$body" | head -c 120)"
    ((PASS++)) || true
  else
    echo "FAIL  $name  →  $url returned non-200 (exit $?)"
    ((FAIL++)) || true
  fi
}

echo "=== surf-ai-task smoke test ==="

check "echo-app"   "localhost/echo-app"
check "podinfo"    "localhost/podinfo"

# python-app requires `make build` first (image.repository is empty until then).
# Skip with SKIP_PYTHON_APP=1 if the image hasn't been pushed yet.
if [[ "${SKIP_PYTHON_APP:-0}" != "1" ]]; then
  check "python-app" "localhost/python-app"
else
  echo "SKIP  python-app  (SKIP_PYTHON_APP=1)"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
