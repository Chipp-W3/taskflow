#!/usr/bin/env bash
set -euo pipefail

# Deploy gate: refuse to run any image whose cosign signature doesn't verify.
#
# Real usage on a deploy host with a native cosign binary (keyless):
#   ./deploy.sh prod ghcr.io/OWNER/taskflow@sha256:<digest>
#   ./deploy.sh staging ghcr.io/OWNER/taskflow@sha256:<digest>
#
# Local testing against a manually generated key pair (see the pipeline
# walkthrough — cosign generate-key-pair):
#   ./deploy.sh staging localhost:5000/taskflow@sha256:<digest> --key cosign.pub
#
# If this machine has no cosign binary installed, falls back to running
# cosign via its official container image. In that fallback mode, GHCR
# credentials must be provided as a standalone docker config (not the
# host's credsStore-backed one — see COSIGN_DOCKER_CONFIG below), and
# GITHUB_REPOSITORY must be set for keyless verification (no default —
# a wrong guess would silently accept an unrelated repo's signature).

ENVIRONMENT="${1:?Usage: $0 <staging|prod> <image>@<digest> [--key <pubkey>]}"
shift
IMAGE_REF="${1:?Usage: $0 <staging|prod> <image>@<digest> [--key <pubkey>]}"
shift || true

case "$ENVIRONMENT" in
  staging)
    CONTAINER_NAME="taskflow-staging"
    HOST_PORT="8001"
    # Staging trusts builds from any branch — lets you test before merging to main.
    IDENTITY_REF_PATTERN="refs/heads/.*"
    ;;
  prod)
    CONTAINER_NAME="taskflow-prod"
    HOST_PORT="8000"
    # Prod trusts only images built from a merge to main.
    IDENTITY_REF_PATTERN="refs/heads/main"
    ;;
  *)
    echo "Unknown environment '$ENVIRONMENT' (expected: staging|prod)" >&2
    exit 1
    ;;
esac

if command -v cosign >/dev/null 2>&1; then
  COSIGN=(cosign)
else
  NETWORK_ARGS=()
  if [[ -n "${COSIGN_DOCKER_NETWORK:-}" ]]; then
    NETWORK_ARGS=(--network "$COSIGN_DOCKER_NETWORK")
  fi
  CONFIG_ARGS=()
  if [[ -n "${COSIGN_DOCKER_CONFIG:-}" ]]; then
    # Host docker config typically points at a credential helper (e.g.
    # Docker Desktop's credsStore) that doesn't exist inside this container,
    # so registry auth must come from a standalone config.json instead.
    # The cosign image runs as the distroless "nonroot" user (uid 65532),
    # whose $HOME is /home/nonroot — not /root.
    CONFIG_ARGS=(-v "${COSIGN_DOCKER_CONFIG}:/home/nonroot/.docker/config.json:ro")
  fi
  COSIGN=(docker run --rm "${NETWORK_ARGS[@]}" "${CONFIG_ARGS[@]}" -v "$PWD:/work" -w /work ghcr.io/sigstore/cosign/cosign:latest)
fi

COSIGN_VERIFY_ARGS=()
if [[ "${1:-}" == "--key" ]]; then
  COSIGN_VERIFY_ARGS+=(--key "$2")
else
  : "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set (e.g. export GITHUB_REPOSITORY=owner/repo) for keyless verification}"
  COSIGN_VERIFY_ARGS+=(
    --certificate-identity-regexp "^https://github.com/${GITHUB_REPOSITORY}/\.github/workflows/ci\.yml@${IDENTITY_REF_PATTERN}$"
    --certificate-oidc-issuer "https://token.actions.githubusercontent.com"
  )
fi

echo "==> [$ENVIRONMENT] Verifying signature for $IMAGE_REF"
if ! "${COSIGN[@]}" verify "${COSIGN_VERIFY_ARGS[@]}" "$IMAGE_REF" >/dev/null; then
  echo "REFUSED: signature verification failed — image will NOT be deployed to $ENVIRONMENT." >&2
  exit 1
fi

echo "==> Signature OK — deploying to $ENVIRONMENT"
docker pull "$IMAGE_REF"
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
docker run -d --name "$CONTAINER_NAME" -p "${HOST_PORT}:8000" "$IMAGE_REF"
