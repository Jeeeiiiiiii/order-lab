#!/usr/bin/env bash
# The order flow view: place orders, break the notifier, and watch each order
# travel through the lab on a departures board.
#
#   bash scripts/flow.sh           # http://localhost:8020, Ctrl+C to stop
#
# Runs on this machine, not in the lab: it reads the emulator on :4566 with
# boto3 and places orders through the ALB stand-in on :8000. Assumes
# terraform applied and scripts/alb-local.sh running.
set -euo pipefail
cd "$(dirname "$0")/.."

python -c "import boto3" 2>/dev/null || { echo "needs boto3: python -m pip install boto3" >&2; exit 1; }
exec python flow/server.py
