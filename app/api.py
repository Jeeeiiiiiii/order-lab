"""Order API.

POST /orders       accept an order: write it to Postgres, enqueue it, return 201
GET  /orders       list recent orders
GET  /orders/<id>  one order
GET  /health       for the load balancer

Deliberately small. The interesting part is what it does not do: it never
sends the notification itself. It records the order, hands a message to the
queue, and answers the customer. Whatever happens after that is somebody
else's problem -- the Lambda's -- and cannot slow down or fail this request.
"""

import json
import logging
import os
import sys
import time
import uuid
from datetime import datetime, timezone

import boto3
import psycopg
from flask import Flask, g, jsonify, request
from psycopg.rows import dict_row

# --- configuration -----------------------------------------------------

DB_DSN = (
    f"host={os.environ['DB_HOST']} port={os.environ.get('DB_PORT', '5432')} "
    f"dbname={os.environ['DB_NAME']} user={os.environ['DB_USER']} "
    f"password={os.environ['DB_PASSWORD']} connect_timeout=5"
)
QUEUE_URL = os.environ["QUEUE_URL"]
METRIC_NAMESPACE = os.environ.get("METRIC_NAMESPACE", "order-lab")
ENDPOINT = os.environ.get("ORDER_LAB_ENDPOINT") or None  # None = real AWS

sqs = boto3.client("sqs", endpoint_url=ENDPOINT)
cloudwatch = boto3.client("cloudwatch", endpoint_url=ENDPOINT)

# --- logging: one JSON object per line ----------------------------------
# CloudWatch Logs Insights can then filter on any field, and a trace_id
# grep works across this log group and the Lambda's.


class JsonFormatter(logging.Formatter):
    def format(self, record):
        entry = {
            "ts": datetime.now(timezone.utc).isoformat(timespec="milliseconds"),
            "level": record.levelname,
            "logger": record.name,
            "msg": record.getMessage(),
        }
        if hasattr(record, "fields"):
            entry.update(record.fields)
        if record.exc_info:
            entry["exc"] = self.formatException(record.exc_info)
        return json.dumps(entry)


handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(JsonFormatter())
logging.basicConfig(level=logging.INFO, handlers=[handler])
log = logging.getLogger("order-api")


def log_event(msg, **fields):
    log.info(msg, extra={"fields": fields})


# --- database --------------------------------------------------------------

SCHEMA = """
CREATE TABLE IF NOT EXISTS orders (
    id          UUID PRIMARY KEY,
    trace_id    TEXT NOT NULL,
    customer    TEXT NOT NULL,
    item        TEXT NOT NULL,
    quantity    INTEGER NOT NULL CHECK (quantity > 0),
    status      TEXT NOT NULL DEFAULT 'accepted',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
"""


def wait_for_db(attempts=30, delay=2):
    """RDS comes up after the instance does. Keep trying rather than crash-looping."""
    for attempt in range(1, attempts + 1):
        try:
            with psycopg.connect(DB_DSN) as conn:
                conn.execute(SCHEMA)
            log_event("database ready", attempt=attempt)
            return
        except psycopg.OperationalError as e:
            log_event("database not ready", attempt=attempt, error=str(e).strip())
            time.sleep(delay)
    raise SystemExit("database never became reachable")


def db():
    if "db" not in g:
        g.db = psycopg.connect(DB_DSN, row_factory=dict_row)
    return g.db


# --- app -------------------------------------------------------------------

app = Flask(__name__)


@app.teardown_appcontext
def close_db(_exc):
    conn = g.pop("db", None)
    if conn is not None:
        conn.close()


@app.before_request
def start_timer():
    g.t0 = time.perf_counter()
    # Honour an upstream trace id (a real tracer would propagate its own
    # header here); otherwise this request starts a trace.
    g.trace_id = request.headers.get("X-Trace-Id") or uuid.uuid4().hex[:16]


@app.after_request
def access_log(resp):
    if request.path != "/health":
        log_event(
            "request",
            trace_id=g.trace_id,
            method=request.method,
            path=request.path,
            status=resp.status_code,
            ms=round((time.perf_counter() - g.t0) * 1000, 1),
        )
    resp.headers["X-Trace-Id"] = g.trace_id
    return resp


@app.get("/health")
def health():
    db().execute("SELECT 1")
    return jsonify(status="ok")


@app.post("/orders")
def create_order():
    body = request.get_json(silent=True) or {}
    try:
        customer = str(body["customer"]).strip()
        item = str(body["item"]).strip()
        quantity = int(body.get("quantity", 1))
        if not customer or not item or quantity < 1:
            raise ValueError
    except (KeyError, ValueError, TypeError):
        return jsonify(error="customer, item and a positive quantity are required"), 400

    order = {
        "id": str(uuid.uuid4()),
        "trace_id": g.trace_id,
        "customer": customer,
        "item": item,
        "quantity": quantity,
    }

    # 1. System of record. If this fails the request fails; nothing else has
    #    happened yet, so there is nothing to undo.
    with db() as conn:
        conn.execute(
            "INSERT INTO orders (id, trace_id, customer, item, quantity) "
            "VALUES (%(id)s, %(trace_id)s, %(customer)s, %(item)s, %(quantity)s)",
            order,
        )

    # 2. Hand-off. The trace id rides along as a message attribute so the
    #    consumer can log it without parsing the body.
    sqs.send_message(
        QueueUrl=QUEUE_URL,
        MessageBody=json.dumps(order),
        MessageAttributes={"trace_id": {"DataType": "String", "StringValue": g.trace_id}},
    )

    # 3. A metric, not a log line: the dashboard wants a number per minute,
    #    not a search over text.
    cloudwatch.put_metric_data(
        Namespace=METRIC_NAMESPACE,
        MetricData=[{"MetricName": "OrdersCreated", "Value": 1, "Unit": "Count"}],
    )

    log_event("order accepted", trace_id=g.trace_id, order_id=order["id"], item=item, quantity=quantity)
    return jsonify(order), 201


@app.get("/orders")
def list_orders():
    rows = db().execute(
        "SELECT id, trace_id, customer, item, quantity, status, created_at "
        "FROM orders ORDER BY created_at DESC LIMIT 50"
    ).fetchall()
    return jsonify(rows)


@app.get("/orders/<order_id>")
def get_order(order_id):
    row = db().execute("SELECT * FROM orders WHERE id = %s", (order_id,)).fetchone()
    if row is None:
        return jsonify(error="not found"), 404
    return jsonify(row)


wait_for_db()
