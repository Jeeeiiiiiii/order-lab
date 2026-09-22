#!/usr/bin/env bash
# Build the API image and push it to the ECR repository Terraform created.
#
# Runs after `terraform apply` (the repository must exist) and before the
# instance can come up healthy (it pulls this image at boot). If you change
# the app: re-run this, then restart the container on the instance, or
# taint the instance so it bootstraps again.
set -euo pipefail
cd "$(dirname "$0")/.."

TAG="${1:-latest}"
REPO=$(terraform -chdir=terraform output -raw ecr_repository_url)

# The emulator names its registry <account>.dkr.ecr.<region>.localhost:5100,
# and Windows does not reliably resolve *.localhost. It is the same registry
# as localhost:5100 (the proxyEndpoint ECR reports), so push there. Only the
# repository path matters to the instance, which pulls by a third name anyway.
case "$REPO" in
  *.localhost:*) REPO="localhost:${REPO#*.localhost:}" ;;
esac

echo "==> building"
docker build -q -t "${REPO}:${TAG}" ./app

echo "==> pushing ${REPO}:${TAG}"
# Locally the registry is unauthenticated plain HTTP on localhost, which
# Docker allows without an insecure-registries entry. In AWS, log in first:
#   aws ecr get-login-password | docker login --username AWS --password-stdin "${REPO%%/*}"
docker push -q "${REPO}:${TAG}"
