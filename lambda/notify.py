"""Order notification.

Invoked by Lambda with a batch of SQS messages. For each one, "send" the
notification (here: a log line -- an email or SMS provider would go in
notify()) and count it as a metric.

Two failure behaviours worth knowing about:

- One bad message does not fail the batch. With ReportBatchItemFailures the
  function returns the ids it could not process, and only those go back to
  the queue; the rest are deleted.
- A message that fails three times is moved to the dead-letter queue by
  SQS, not by this code. The alarm on that queue is how anyone finds out.

An order for item "poison" always fails, so the failure path can be
exercised on purpose.
"""

import json
import logging
import os

import boto3

METRIC_NAMESPACE = os.environ.get("METRIC_NAMESPACE", "order-lab")
ENDPOINT = os.environ.get("ORDER_LAB_ENDPOINT") or None  # None = real AWS

cloudwatch = boto3.client("cloudwatch", endpoint_url=ENDPOINT)

log = logging.getLogger()
log.setLevel(logging.INFO)


def log_event(msg, **fields):
    log.info(json.dumps({"msg": msg, **fields}))


def put_metric(name, value):
    cloudwatch.put_metric_data(
        Namespace=METRIC_NAMESPACE,
        MetricData=[{"MetricName": name, "Value": value, "Unit": "Count"}],
    )


def notify(order):
    if order.get("item") == "poison":
        raise RuntimeError("notification provider rejected the message")
    # A real provider call goes here.
    return f"order {order['id']} confirmed for {order['customer']}: {order['quantity']} x {order['item']}"


def handler(event, _context):
    failed = []
    sent = 0

    for record in event.get("Records", []):
        order = json.loads(record["body"])
        trace_id = (
            record.get("messageAttributes", {}).get("trace_id", {}).get("stringValue")
            or order.get("trace_id", "-")
        )
        try:
            message = notify(order)
            sent += 1
            log_event("notification sent", trace_id=trace_id, order_id=order["id"], message=message)
        except Exception as e:  # noqa: BLE001 - anything means "retry this one"
            failed.append({"itemIdentifier": record["messageId"]})
            log_event(
                "notification failed",
                trace_id=trace_id,
                order_id=order.get("id"),
                error=str(e),
                receive_count=record.get("attributes", {}).get("ApproximateReceiveCount"),
            )

    if sent:
        put_metric("NotificationsSent", sent)
    if failed:
        put_metric("NotificationsFailed", len(failed))

    return {"batchItemFailures": failed}
