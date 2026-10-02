"""Order flow: watch orders travel through the lab, and break it on purpose.

Runs on your machine, not in the lab. It plays two roles:

  the customer  -- places orders through the ALB stand-in (localhost:8000),
                   exactly as `curl` would
  the operator  -- reads what AWS would show you: the orders table (via the
                   API), both CloudWatch log groups, the queue and DLQ
                   attributes, the Lambda's event source mapping, the alarms

Nothing is simulated. Every state on the page is derived from one of those
sources, and each order's timeline is stitched together the way the README
describes: by grepping its trace id across the API's and the Lambda's logs.

Standard library plus boto3 (already installed for the lab). Started by
scripts/flow.sh, which passes the Terraform outputs in.
"""

import json
import os
import subprocess
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import boto3
from botocore.config import Config

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PORT = int(os.environ.get("FLOW_PORT", "8020"))
API = os.environ.get("ORDER_API", "http://localhost:8000")
ENDPOINT = os.environ.get("AWS_ENDPOINT", "http://localhost:4566")

VISIBILITY_TIMEOUT = 60   # aws_sqs_queue.orders.visibility_timeout_seconds
MAX_RECEIVES = 3          # redrive_policy.maxReceiveCount
REFRESH_SECONDS = 2
LOOKBACK_MS = 6 * 3600 * 1000  # how far back to read logs on first load


def terraform_outputs():
    out = subprocess.run(
        ["terraform", f"-chdir={os.path.join(ROOT, 'terraform')}", "output", "-json"],
        capture_output=True, text=True, check=True,
    ).stdout
    return {k: v["value"] for k, v in json.loads(out).items()}


TF = terraform_outputs()
NAME = TF["notify_function_name"].removesuffix("-notify")
QUEUE_URL = TF["orders_queue_url"]
DLQ_URL = TF["orders_dlq_url"]
FUNCTION = TF["notify_function_name"]
APP_LOGS = TF["app_log_group"]
FN_LOGS = f"/aws/lambda/{FUNCTION}"

session = boto3.session.Session(
    aws_access_key_id="test", aws_secret_access_key="test", region_name="us-east-1"
)
cfg = Config(retries={"max_attempts": 2}, connect_timeout=3, read_timeout=10)
sqs = session.client("sqs", endpoint_url=ENDPOINT, config=cfg)
logs = session.client("logs", endpoint_url=ENDPOINT, config=cfg)
lam = session.client("lambda", endpoint_url=ENDPOINT, config=cfg)
cw = session.client("cloudwatch", endpoint_url=ENDPOINT, config=cfg)


# --- reading the system -------------------------------------------------------

def http_json(method, path, body=None, timeout=10):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.status, json.loads(resp.read() or b"null")


def queue_depth(url):
    a = sqs.get_queue_attributes(
        QueueUrl=url,
        AttributeNames=["ApproximateNumberOfMessages", "ApproximateNumberOfMessagesNotVisible"],
    )["Attributes"]
    return {"waiting": int(a.get("ApproximateNumberOfMessages", 0)),
            "in_flight": int(a.get("ApproximateNumberOfMessagesNotVisible", 0))}


def log_events(group, since_ms):
    """All events in a log group since a time, each parsed to (ts_ms, dict)."""
    events, token = [], None
    while True:
        kw = {"logGroupName": group, "startTime": since_ms, "limit": 1000}
        if token:
            kw["nextToken"] = token
        page = logs.filter_log_events(**kw)
        for e in page.get("events", []):
            msg = e["message"]
            # The API logs bare JSON (awslogs driver); the Lambda runtime
            # prefixes its own fields: "[INFO]\t<ts>\t<request id>\t{...}".
            start = msg.find("{")
            if start < 0:
                continue
            try:
                events.append((e["timestamp"], json.loads(msg[start:])))
            except ValueError:
                continue
        token = page.get("nextToken")
        if not token or not page.get("events"):
            return events


def dlq_trace_ids():
    """Peek at the DLQ without taking anything out of it.

    VisibilityTimeout=0 hands every message straight back. The DLQ has no
    redrive of its own, so reading it has no consequence beyond its
    receive count.
    """
    seen = {}
    for _ in range(5):
        msgs = sqs.receive_message(
            QueueUrl=DLQ_URL, MaxNumberOfMessages=10, VisibilityTimeout=0,
            WaitTimeSeconds=0, MessageAttributeNames=["All"],
        ).get("Messages", [])
        if not msgs:
            break
        for m in msgs:
            try:
                seen[json.loads(m["Body"])["trace_id"]] = m["MessageId"]
            except (ValueError, KeyError):
                continue
    return seen


def notifier_mapping():
    maps = lam.list_event_source_mappings(FunctionName=FUNCTION).get("EventSourceMappings", [])
    return maps[0] if maps else None


def alarms():
    return [{"name": a["AlarmName"].removeprefix(NAME + "-"), "state": a["StateValue"],
             "metric": f'{a["Namespace"]}/{a["MetricName"]}'}
            for a in cw.describe_alarms(AlarmNamePrefix=NAME)["MetricAlarms"]]


# --- turning evidence into a journey --------------------------------------------

def journey(order, api_by_trace, fn_by_trace, dead, notifier_on, now_ms):
    """Where one order is, and the evidence for every step.

    The database never learns whether the customer was notified (the API
    writes 'accepted' and never touches the row again), so everything after
    'queued' comes from the Lambda's logs and the DLQ.
    """
    trace = order["trace_id"]
    steps = []
    accepted = next((ts for ts, e in api_by_trace.get(trace, []) if e.get("msg") == "order accepted"), None)
    steps.append({"step": "accepted", "ts": accepted,
                  "proof": f'{APP_LOGS}: "order accepted" (row status: {order["status"]})'})

    attempts, sent_at = [], None
    for ts, e in sorted(fn_by_trace.get(trace, []), key=lambda x: x[0]):
        if e.get("msg") == "notification failed":
            attempts.append(ts)
            steps.append({"step": "failed", "ts": ts, "attempt": len(attempts),
                          "proof": f'{FN_LOGS}: "notification failed" - {e.get("error")} '
                                   f'(receive {e.get("receive_count")})'})
        elif e.get("msg") == "notification sent":
            sent_at = ts
            steps.append({"step": "sent", "ts": ts,
                          "proof": f'{FN_LOGS}: "notification sent"'})

    if sent_at:
        state = "departed"
    elif trace in dead:
        state = "diverted"
        steps.append({"step": "dead-lettered", "ts": None,
                      "proof": f"found in the DLQ (message {dead[trace][:8]}...)"})
    elif attempts:
        # A failed receive keeps the message invisible until its visibility
        # timeout runs out. The Lambda fails fast, so that is ~60s after the
        # failure was logged.
        retry_at = attempts[-1] + VISIBILITY_TIMEOUT * 1000
        if len(attempts) >= MAX_RECEIVES:
            state = "diverting"  # third failure logged, SQS moving it to the DLQ
        elif now_ms < retry_at:
            state = "delayed"
        else:
            state = "held" if not notifier_on else "boarding"
        steps.append({"step": "invisible", "ts": attempts[-1], "until": retry_at,
                      "proof": f"visibility timeout {VISIBILITY_TIMEOUT}s after receive {len(attempts)}"})
    else:
        state = "held" if not notifier_on else "at-gate"

    return {
        "id": order["id"], "trace_id": trace, "customer": order["customer"],
        "item": order["item"], "quantity": order["quantity"],
        "created_at": order["created_at"], "state": state,
        "attempts": len(attempts), "steps": steps,
    }


class Snapshot:
    """Refreshed every REFRESH_SECONDS in the background; requests read it."""

    def __init__(self):
        self.lock = threading.Lock()
        self.data = {"ready": False}
        self.since_ms = int(time.time() * 1000) - LOOKBACK_MS

    def refresh(self):
        now_ms = int(time.time() * 1000)
        errors = []

        def attempt(label, fn, default):
            try:
                return fn()
            except Exception as e:  # show the operator what failed, keep going
                errors.append(f"{label}: {e}")
                return default

        status, orders = attempt("orders (API via :8000)", lambda: http_json("GET", "/orders"), (0, []))
        mapping = attempt("event source mapping", notifier_mapping, None)
        notifier_on = bool(mapping) and mapping.get("State") in ("Enabled", "Enabling", "Updating")

        api_by_trace, fn_by_trace = {}, {}
        for ts, e in attempt("API logs", lambda: log_events(APP_LOGS, self.since_ms), []):
            if "trace_id" in e:
                api_by_trace.setdefault(e["trace_id"], []).append((ts, e))
        for ts, e in attempt("Lambda logs", lambda: log_events(FN_LOGS, self.since_ms), []):
            if "trace_id" in e:
                fn_by_trace.setdefault(e["trace_id"], []).append((ts, e))
        dead = attempt("DLQ", dlq_trace_ids, {})

        data = {
            "ready": True,
            "now": now_ms,
            "orders": [journey(o, api_by_trace, fn_by_trace, dead, notifier_on, now_ms)
                       for o in (orders or [])],
            "queue": attempt("orders queue", lambda: queue_depth(QUEUE_URL), None),
            "dlq": attempt("DLQ", lambda: queue_depth(DLQ_URL), None),
            "notifier": {"on": notifier_on, "state": mapping.get("State") if mapping else "missing",
                         "batch_size": mapping.get("BatchSize") if mapping else None},
            "alarms": attempt("alarms", alarms, []),
            "config": {"visibility_timeout": VISIBILITY_TIMEOUT, "max_receives": MAX_RECEIVES,
                       "api": API, "function": FUNCTION},
            "errors": errors,
        }
        with self.lock:
            self.data = data

    def loop(self):
        while True:
            try:
                self.refresh()
            except Exception as e:
                with self.lock:
                    self.data = {**self.data, "errors": [f"refresh: {e}"]}
            time.sleep(REFRESH_SECONDS)

    def get(self):
        with self.lock:
            return self.data


SNAPSHOT = Snapshot()


# --- actions ------------------------------------------------------------------

CUSTOMERS = ["ada", "grace", "linus", "margaret", "ken", "barbara", "dennis", "frances"]
ITEMS = ["keyboard", "monitor", "headset", "webcam", "dock", "mouse", "cable", "stand"]


def place(kind, count):
    count = max(1, min(20, count))

    def one(i):
        body = ({"customer": "mallory", "item": "poison", "quantity": 1} if kind == "poison" else
                {"customer": CUSTOMERS[(int(time.time()) + i) % len(CUSTOMERS)],
                 "item": ITEMS[(int(time.time() * 7) + i) % len(ITEMS)], "quantity": 1 + i % 3})
        t0 = time.monotonic()
        try:
            status, order = http_json("POST", "/orders", body)
        except urllib.error.HTTPError as e:
            status, order = e.code, None
        except Exception as e:
            return {"status": 0, "error": str(e)}
        return {"status": status, "ms": round((time.monotonic() - t0) * 1000), "order": order}

    with ThreadPoolExecutor(max_workers=10) as pool:
        results = list(pool.map(one, range(count)))
    threading.Thread(target=SNAPSHOT.refresh, daemon=True).start()
    return {"placed": results}


def set_notifier(on):
    mapping = notifier_mapping()
    if not mapping:
        raise RuntimeError("the notifier has no event source mapping")
    lam.update_event_source_mapping(UUID=mapping["UUID"], Enabled=bool(on))
    SNAPSHOT.refresh()
    return SNAPSHOT.get()["notifier"]


# --- HTTP ---------------------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    def send(self, status, body, ctype="application/json"):
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path in ("/", "/index.html"):
            with open(os.path.join(HERE, "index.html"), "rb") as f:
                self.send(200, f.read(), "text/html; charset=utf-8")
        elif path == "/api/state":
            self.send(200, SNAPSHOT.get())
        elif path.startswith("/fonts/") and "/" not in path[7:] and ".." not in path:
            # Self-hosted Barlow, so the board renders the same offline.
            f = os.path.join(HERE, "fonts", path[7:])
            if not os.path.isfile(f):
                return self.send(404, {"error": "no such font"})
            ctype = "text/css" if f.endswith(".css") else "font/woff2"
            with open(f, "rb") as fh:
                self.send(200, fh.read(), ctype)
        else:
            self.send(404, {"error": f"no route for {path}"})

    def do_POST(self):
        path = self.path.split("?")[0]
        try:
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"{}")
        except ValueError:
            return self.send(400, {"error": "body is not JSON"})
        try:
            if path == "/api/orders":
                kind = body.get("kind", "normal")
                if kind not in ("normal", "poison"):
                    return self.send(400, {"error": "kind must be normal or poison"})
                self.send(200, place(kind, int(body.get("count", 1))))
            elif path == "/api/notifier":
                self.send(200, set_notifier(body.get("on")))
            else:
                self.send(404, {"error": f"no route for {path}"})
        except Exception as e:
            self.send(502, {"error": str(e)})

    def log_message(self, fmt, *args):
        if "/api/state" not in self.path:
            print(f"{self.command} {self.path} -> {args[1] if len(args) > 1 else ''}", flush=True)


if __name__ == "__main__":
    threading.Thread(target=SNAPSHOT.loop, daemon=True).start()
    print(f"order flow on http://localhost:{PORT}  (API {API}, emulator {ENDPOINT})", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
