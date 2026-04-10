#!/usr/bin/env bash
set -euo pipefail

CHART_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/packages/istio-gateway-metrics/chart"

if ! command -v helm >/dev/null 2>&1; then
  echo "helm is required for this test" >&2
  exit 1
fi

# Render with PodMonitor CRD available.
out="$(helm template istio-gateway-metrics "$CHART_DIR" \
  --api-versions monitoring.coreos.com/v1)"

echo "$out" | grep -q "kind: PodMonitor" 
echo "$out" | grep -q "name: \"admin-gateway-envoy-prom\""
echo "$out" | grep -q "name: \"tenant-gateway-envoy-prom\""

# Render without PodMonitor CRD available (should produce no manifests).
out2="$(helm template istio-gateway-metrics "$CHART_DIR")"
if echo "$out2" | grep -q "kind: PodMonitor"; then
  echo "expected no PodMonitor output when CRD is not available" >&2
  exit 1
fi

echo "ok"
