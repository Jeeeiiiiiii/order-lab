#!/usr/bin/env bash
# Walk an order through the system and look at it from the observability side.
#
# Assumes: terraform applied, image pushed, alb-local.sh running.
set -euo pipefail
cd "$(dirname "$0")/.."

# Git Bash rewrites /aws/lambda/... into a Windows path before handing it to
# a native binary. Nothing here needs that.
export MSYS_NO_PATHCONV=1

URL="${URL:-http://localhost:8000}"
AWS="docker run --rm --network floci_default -e AWS_ACCESS_KEY_ID=test -e AWS_SECRET_ACCESS_KEY=test -e AWS_DEFAULT_REGION=us-east-1 amazon/aws-cli --endpoint-url=http://floci:4566"

NAME=$(terraform -chdir=terraform output -raw notify_function_name | sed 's/-notify$//')
QUEUE=$(terraform -chdir=terraform output -raw orders_queue_url)
DLQ=$(terraform -chdir=terraform output -raw orders_dlq_url)
APP_LOGS=$(terraform -chdir=terraform output -raw app_log_group)
FN_LOGS="/aws/lambda/${NAME}-notify"

hr() { echo; echo "── $1"; echo; }

hr "1. Health, through the load balancer"
curl -s -m 5 "${URL}/health" || { echo "API not reachable at ${URL}. Is alb-local.sh running and the instance booted?"; exit 1; }
echo

hr "2. Place an order"
RESP=$(curl -s -X POST "${URL}/orders" -H 'Content-Type: application/json' \
  -d '{"customer": "ada", "item": "keyboard", "quantity": 2}')
echo "$RESP"
ORDER_ID=$(echo "$RESP" | sed -n 's/.*"id": *"\([^"]*\)".*/\1/p')
TRACE_ID=$(echo "$RESP" | sed -n 's/.*"trace_id": *"\([^"]*\)".*/\1/p')
echo
echo "    order   ${ORDER_ID}"
echo "    trace   ${TRACE_ID}"

hr "3. It is in the database (GET goes back to Postgres, not a cache)"
curl -s "${URL}/orders/${ORDER_ID}"; echo

hr "4. The queue handed it to the Lambda"
sleep 6
printf "    messages waiting in the queue: "
$AWS sqs get-queue-attributes --queue-url "$QUEUE" --attribute-names ApproximateNumberOfMessages --query 'Attributes.ApproximateNumberOfMessages' --output text
echo "    Lambda log, filtered on the trace id:"
$AWS logs filter-log-events --log-group-name "$FN_LOGS" --filter-pattern "\"${TRACE_ID}\"" \
  --query 'events[].message' --output text | sed 's/^/      /'

hr "5. One trace id, both log groups"
# The awslogs driver batches for a few seconds before shipping.
sleep 5
echo "    API log:"
$AWS logs filter-log-events --log-group-name "$APP_LOGS" --filter-pattern "\"${TRACE_ID}\"" \
  --query 'events[].message' --output text | sed 's/^/      /'

hr "6. Metrics"
$AWS cloudwatch list-metrics --namespace "$NAME" --query 'Metrics[].MetricName' --output text | tr '\t' '\n' | sed 's/^/    /'

hr "7. Failure path: an order the notifier cannot deliver"
curl -s -X POST "${URL}/orders" -H 'Content-Type: application/json' \
  -d '{"customer": "mallory", "item": "poison", "quantity": 1}' >/dev/null
echo "    accepted by the API (the customer never sees the notifier fail)."
echo "    Lambda retries it 3 times, then SQS moves it to the DLQ. Waiting..."
for _ in $(seq 1 30); do
  N=$($AWS sqs get-queue-attributes --queue-url "$DLQ" --attribute-names ApproximateNumberOfMessages --query 'Attributes.ApproximateNumberOfMessages' --output text)
  [ "$N" != "0" ] && break
  sleep 5
done
echo "    messages in the DLQ: ${N}"
echo
echo "    alarms:"
$AWS cloudwatch describe-alarms --alarm-name-prefix "$NAME" \
  --query 'MetricAlarms[].[AlarmName,StateValue]' --output text | sed 's/^/      /'
echo
echo "Console: http://localhost:4500   API: ${URL}/orders"
