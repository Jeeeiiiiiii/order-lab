#!/usr/bin/env bash
# EC2 user data for the API instance. Rendered by Terraform (templatefile);
# the dollar-brace placeholders are Terraform's. Shell substitutions like $(hostname) are fine as they are;
# only a literal dollar-brace would need escaping as $${...}.
#
# What it does: install Docker, log in to the registry, pull the API image,
# run it with the awslogs driver so the container's stdout lands in
# CloudWatch. No application code lives on the instance.
set -euo pipefail
exec > >(tee -a /var/log/app-bootstrap.log) 2>&1

echo "==> installing docker"
# The first boot sometimes runs before the network can reach the package
# repository; retry rather than leave an instance with no API on it.
for attempt in 1 2 3 4 5; do
  dnf install -y -q docker && break
  echo "dnf failed (attempt $attempt), retrying in 10s"
  sleep 10
done
command -v docker >/dev/null

mkdir -p /etc/docker
%{ if local_mode ~}
# Emulator: the registry is plain HTTP, and the Docker daemon needs static
# credentials for the awslogs driver because there is no instance metadata
# service to get them from.
echo '{"insecure-registries": ["${registry}"]}' > /etc/docker/daemon.json
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_REGION=${region}
%{ endif ~}

echo "==> starting docker"
if command -v systemctl >/dev/null 2>&1 && systemctl start docker 2>/dev/null; then
  systemctl enable docker
else
  # No systemd (the emulator runs the instance as a container).
  nohup dockerd >/var/log/dockerd.log 2>&1 &
fi
until docker info >/dev/null 2>&1; do sleep 1; done

%{ if !local_mode ~}
echo "==> logging in to ECR"
aws ecr get-login-password --region ${region} \
  | docker login --username AWS --password-stdin ${registry}
%{ endif ~}

echo "==> pulling ${image}"
docker pull ${image}

echo "==> starting the api"
docker rm -f order-api >/dev/null 2>&1 || true
# Host networking: one container per instance, so there is nothing to
# isolate it from. Docker drops a loopback resolver from a host-network
# container's resolv.conf, so hand it the instance's resolver explicitly --
# the VPC resolver in AWS, the emulator's embedded DNS locally. Without this
# the container cannot resolve the emulator's service names.
RESOLVER=$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf)
docker run -d --name order-api --restart unless-stopped \
  --network host --dns "$RESOLVER" \
  -e PORT='${app_port}' \
  --log-driver awslogs \
  --log-opt awslogs-region=${region} \
  --log-opt awslogs-group=${log_group} \
  --log-opt awslogs-stream=api-$(cat /proc/sys/kernel/hostname) \
%{ if endpoint_url != "" ~}
  --log-opt awslogs-endpoint=${endpoint_url} \
%{ endif ~}
  -e DB_HOST='${db_host}' \
  -e DB_PORT='${db_port}' \
  -e DB_NAME='${db_name}' \
  -e DB_USER='${db_user}' \
  -e DB_PASSWORD='${db_password}' \
  -e QUEUE_URL='${queue_url}' \
  -e METRIC_NAMESPACE='${metric_ns}' \
  -e AWS_DEFAULT_REGION='${region}' \
  -e ORDER_LAB_ENDPOINT='${endpoint_url}' \
%{ if local_mode ~}
  -e AWS_ACCESS_KEY_ID=test -e AWS_SECRET_ACCESS_KEY=test \
%{ endif ~}
  ${image}

echo "==> api started"
