#!/usr/bin/env bash

set -euo pipefail

CRDS=(
  backendpolicies.gateway.networking.k8s.io
  backendtlspolicies.gateway.networking.k8s.io
  gatewayclasses.gateway.networking.k8s.io
  gateways.gateway.networking.k8s.io
  grpcroutes.gateway.networking.k8s.io
  httproutes.gateway.networking.k8s.io
  referencegrants.gateway.networking.k8s.io
  tcproutes.gateway.networking.k8s.io
  tlsroutes.gateway.networking.k8s.io
  udproutes.gateway.networking.k8s.io
  xbackendtrafficpolicies.gateway.networking.x-k8s.io
  xlistenersets.gateway.networking.x-k8s.io
  xmeshes.gateway.networking.x-k8s.io
)

# This can now be a release-name source string or a zarf-<hash>
CLI_ARG_RELEASE_NAME="${1:-}"

# I've never used this, but Helm still records which namespace “owns” the release in the annotations meta.helm.sh/release-namespace
CLI_ARG_RELEASE_NAMESPACE="${2:-}"

RELEASE_NAME="${RELEASE_NAME:-}"
RELEASE_NAME_SOURCE="${RELEASE_NAME_SOURCE:-${TARGET_RELEASE_SOURCE:-${HELM_RELEASE_SOURCE:-}}}"
RELEASE_SUPPLIED=false
RELEASE_NAMESPACE_SUPPLIED=false

if [[ -n "${CLI_ARG_RELEASE_NAMESPACE}" ]]; then
  RELEASE_NAMESPACE="${CLI_ARG_RELEASE_NAMESPACE}"
  RELEASE_NAMESPACE_SUPPLIED=true
elif [[ -n "${RELEASE_NAMESPACE:-}" ]]; then
  RELEASE_NAMESPACE_SUPPLIED=true
else
  for candidate in "${TARGET_RELEASE_NAMESPACE:-}" "${ZARF_HELM_RELEASE_NAMESPACE:-}" "${HELM_RELEASE_NAMESPACE:-}"; do
    if [[ -n "${candidate}" ]]; then
      RELEASE_NAMESPACE="${candidate}"
      RELEASE_NAMESPACE_SUPPLIED=true
      break
    fi
  done

  if [[ -z "${RELEASE_NAMESPACE:-}" ]]; then
    RELEASE_NAMESPACE="default"
  fi
fi

if [[ -n "${CLI_ARG_RELEASE_NAME}" ]]; then
  # Parsing wheather or not you are already supplying a zarf-<hash> release name vs a source string
  if [[ "${CLI_ARG_RELEASE_NAME}" == zarf-* ]]; then
    RELEASE_NAME="${CLI_ARG_RELEASE_NAME}"
  else
    RELEASE_NAME_SOURCE="${CLI_ARG_RELEASE_NAME}"
  fi
  RELEASE_SUPPLIED=true
elif [[ -n "${RELEASE_NAME}" ]]; then
  RELEASE_SUPPLIED=true
else
  for candidate in "${TARGET_RELEASE_NAME:-}" "${ZARF_HELM_RELEASE_NAME:-}" "${HELM_RELEASE_NAME:-}"; do
    if [[ -n "${candidate}" ]]; then
      RELEASE_NAME="${candidate}"
      RELEASE_SUPPLIED=true
      break
    fi
  done
fi

# Supply this either through env var or script arg $1
if [[ -n "${RELEASE_NAME}" ]]; then
  RELEASE_SUPPLIED=true
fi

detect_release_metadata() {
  if [[ -z "${RELEASE_NAME}" && -n "${RELEASE_NAME_SOURCE}" ]]; then
    if ! command -v shasum >/dev/null 2>&1; then
      echo "ERROR: shasum command is required to derive release name from RELEASE_NAME_SOURCE." >&2
      exit 1
    fi
    # produces the zarf-<SHA-1> release name used by Zarf internally for the helm ownership annotation
    RELEASE_NAME="zarf-$(printf '%s' "${RELEASE_NAME_SOURCE}" | shasum | awk '{print $1}')"
    echo "Derived release name from source '${RELEASE_NAME_SOURCE}': ${RELEASE_NAME}"
    RELEASE_SUPPLIED=true
  fi

  if [[ "${RELEASE_SUPPLIED}" == true && "${RELEASE_NAMESPACE_SUPPLIED}" == true && -n "${RELEASE_NAMESPACE}" ]]; then
    echo "Using supplied release metadata: ${RELEASE_NAME}/${RELEASE_NAMESPACE}"
    return
  fi

  local probe_crd
  probe_crd="gateways.gateway.networking.k8s.io"

  if ! kubectl get crd "${probe_crd}" >/dev/null 2>&1; then
    echo "WARNING: Unable to locate ${probe_crd}; Gateway API CRDs may not be installed yet." >&2
    return 1
  fi

  local detected_name
  local detected_namespace
  detected_name="$(kubectl get crd "${probe_crd}" -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-name}' || true)"
  detected_namespace="$(kubectl get crd "${probe_crd}" -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-namespace}' || true)"

  if [[ -z "${RELEASE_NAME}" && -n "${detected_name}" ]]; then
    RELEASE_NAME="${detected_name}"
    RELEASE_SUPPLIED=true
  fi

  if [[ "${RELEASE_NAMESPACE_SUPPLIED}" != true && -n "${detected_namespace}" ]]; then
    RELEASE_NAMESPACE="${detected_namespace}"
    RELEASE_NAMESPACE_SUPPLIED=true
  fi

  if [[ -z "${RELEASE_NAME}" || -z "${RELEASE_NAMESPACE}" ]]; then
    echo "WARNING: Unable to determine Helm release metadata from ${probe_crd}." >&2
    echo "Set RELEASE_NAME and RELEASE_NAMESPACE environment variables to override autodetection." >&2
    return 1
  fi

  echo "Using release metadata: ${RELEASE_NAME}/${RELEASE_NAMESPACE}"
}

remove_last_applied_annotation() {
  local crd="$1"
  if kubectl get crd "${crd}" >/dev/null 2>&1; then
    kubectl annotate crd "${crd}" kubectl.kubernetes.io/last-applied-configuration- --overwrite >/dev/null 2>&1 || true
  fi
}

patch_helm_metadata() {
  echo "Ensuring Helm ownership metadata on Gateway API CRDs..."
  local found_at_least_one=false

  for crd in "${CRDS[@]}"; do
    if ! kubectl get crd "${crd}" >/dev/null 2>&1; then
      echo "Skipping ${crd} (not present in cluster)."
      continue
    fi

    found_at_least_one=true

    remove_last_applied_annotation "${crd}"

    kubectl label crd "${crd}" app.kubernetes.io/managed-by=Helm --overwrite
    kubectl annotate crd "${crd}" meta.helm.sh/release-name="${RELEASE_NAME}" --overwrite
    kubectl annotate crd "${crd}" meta.helm.sh/release-namespace="${RELEASE_NAMESPACE}" --overwrite
  done

  if [[ "${found_at_least_one}" == false ]]; then
    echo "No Gateway API CRDs detected; nothing to patch."
  fi
}

detect_release_metadata || exit 0
patch_helm_metadata || true

echo "Gateway API CRDs updated and Helm ownership restored (release ${RELEASE_NAME}/${RELEASE_NAMESPACE})."
