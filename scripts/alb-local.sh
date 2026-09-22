#!/usr/bin/env bash
# Local stand-in for the ALB.
#
# Floci records the ALB but does not forward traffic through it, and the
# instance only publishes SSH to the host. So: a socat container on the
# emulator's network, listening on host port 8000 and forwarding to the
# API instance -- which is, functionally, what the ALB does.
#
#   http://localhost:8000  ->  order-lab-alb  ->  floci-ec2-<id>:8080
set -euo pipefail
cd "$(dirname "$0")/.."

PORT="${PORT:-8000}"
INSTANCE=$(terraform -chdir=terraform output -raw app_instance_id)
APP_PORT=8080

docker rm -f order-lab-alb >/dev/null 2>&1 || true
docker run -d --name order-lab-alb --network floci_default \
  -p "${PORT}:80" alpine/socat:1.8.0.0 \
  TCP-LISTEN:80,fork,reuseaddr "TCP:floci-ec2-${INSTANCE}:${APP_PORT}" >/dev/null

echo "ALB stand-in: http://localhost:${PORT}  ->  floci-ec2-${INSTANCE}:${APP_PORT}"
echo "(in AWS: http://$(terraform -chdir=terraform output -raw alb_dns))"
