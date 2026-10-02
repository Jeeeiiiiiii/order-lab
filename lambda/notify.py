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

SQS delivers at least once, so the same order can arrive twice: a message
redelivered after a crash between notify() and the delete, or two messages
for one order sent by racing API retries. A DynamoDB table of sent order ids
turns that into at most one notification per order. The one window left open
is a crash after notify() and before the id is recorded; closing it needs the
provider itself to accept an idempotency key, which a real one usually does.
"""

import json
import logging
import os
import time

import boto3
from botocore.exceptions import ClientError

METRIC_NAMESPACE = os.environ.get("METRIC_NAMESPACE", "order-lab")
SENT_TABLE = os.environ["SENT_TABLE"]
SENT_RETENTION_S = 7 * 24 * 3600  # longer than any redelivery: 3 receives x 60s visibility
ENDPOINT = os.environ.get("ORDER_LAB_ENDPOINT") or None  # None = real AWS

cloudwatch = boto3.client("cloudwatch", endpoint_url=ENDPOINT)
dynamodb = boto3.client("dynamodb", endpoint_url=ENDPOINT)

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


def already_sent(order_id):
    resp = dynamodb.get_item(
        TableName=SENT_TABLE,
        Key={"order_id": {"S": order_id}},
        ConsistentRead=True,
    )
    return "Item" in resp


def record_sent(order_id, message_id):
    """Returns False if another invocation recorded this order first."""
    now = int(time.time())
    try:
        dynamodb.put_item(
            TableName=SENT_TABLE,
            Item={
                "order_id": {"S": order_id},
                "message_id": {"S": message_id},
                "sent_at": {"N": str(now)},
                "expires_at": {"N": str(now + SENT_RETENTION_S)},
            },
            ConditionExpression="attribute_not_exists(order_id)",
        )
        return True
    except ClientError as e:
        if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
            return False
        raise


def handler(event, _context):
    failed = []
    sent = 0
    skipped = 0

    for record in event.get("Records", []):
        order = json.loads(record["body"])
        trace_id = (
            record.get("messageAttributes", {}).get("trace_id", {}).get("stringValue")
            or order.get("trace_id", "-")
        )
        try:
            # A failure here (table unreachable) is a retry, which is safe:
            # nothing has been sent yet.
            if already_sent(order["id"]):
                skipped += 1
                log_event("duplicate skipped", trace_id=trace_id, order_id=order["id"], message_id=record["messageId"])
                continue
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
            continue

        # Past this point the customer has been told. Failing the message now
        # would tell them twice, so a recording error is logged, not retried.
        try:
            if not record_sent(order["id"], record["messageId"]):
                log_event("duplicate sent concurrently", trace_id=trace_id, order_id=order["id"])
        except Exception as e:  # noqa: BLE001
            log_event("could not record sent order", trace_id=trace_id, order_id=order["id"], error=str(e))

    if sent:
        put_metric("NotificationsSent", sent)
    if skipped:
        put_metric("NotificationsDeduplicated", skipped)
    if failed:
        put_metric("NotificationsFailed", len(failed))

    return {"batchItemFailures": failed}
