# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Stack

Static HTML/CSS/JS in one file, served by a standard-library Python server on the operator's machine that talks to the Floci emulator with boto3 (already installed) and to the ALB stand-in on :8000. No build step, nothing new deployed into AWS. Chosen by the user.

## Users

One DevOps engineer learning the async order pipeline in this lab, on their own Windows laptop, with the lab running locally. They know Kubernetes, Helm and CloudWatch from work; they want to *see* what each AWS piece does rather than read it in logs. They prefer plain-language explanations and cause → effect they can trigger themselves.

## Product Purpose

The order flow view lets them place orders and trigger failures, then watch each order travel through the real system — ALB, API, Postgres, SQS, Lambda, dead-letter queue, CloudWatch — with timestamps read from the real logs, queues and alarms. Success: they can explain, from what they watched, why the API answers before the customer is notified, what the 60-second invisible wait is, why a failing message ends up in the DLQ after three attempts, and why pausing the notifier does not stop orders being accepted.

Scenarios in scope: normal order, poison order → DLQ, pause/resume the notifier (disable the Lambda's SQS event source mapping), burst of orders. Out of scope for now: replaying the DLQ.

## Positioning

Every state shown is read from the running emulator (queue attributes, log events by trace id, the event source mapping, alarm state) — nothing is simulated in the page. Where the emulator differs from AWS (no AWS/SQS metrics, so `dlq-not-empty` stays OK; the ALB is a socat stand-in), the view says so rather than hiding it.

## Constraints

- Must work with the lab's timing: visibility timeout 60s, maxReceiveCount 3, batch size 5, Lambda timeout 10s. A poison order takes about 2–3 minutes to reach the DLQ; the view must make that waiting legible, not look stuck.
- The API never updates an order's `status` after `accepted`; the database does not know whether the notification went out. The view must not imply otherwise.
- Sibling tool: mesh-lab's traffic console (cool grey-blue, bench-instrument). This one is a separate lab with its own identity.
