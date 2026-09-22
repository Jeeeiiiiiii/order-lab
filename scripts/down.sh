#!/usr/bin/env bash
# Tear everything down: the ALB stand-in, then every AWS resource.
set -euo pipefail
cd "$(dirname "$0")/.."

docker rm -f order-lab-alb >/dev/null 2>&1 || true
terraform -chdir=terraform destroy -auto-approve

echo "done. The emulator itself is still running: cd ../floci-ui && docker compose down"
