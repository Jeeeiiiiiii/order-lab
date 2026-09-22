# Order Lab

An order processing system: an API on EC2 behind an ALB, Postgres as the
system of record, a queue between accepting an order and notifying the
customer, a Lambda that does the notifying, and CloudWatch watching all of it.

Everything runs locally against [Floci](https://github.com/floci-io/floci), an
AWS emulator. The Terraform is written for a real account; the `endpoints`
block in `terraform/providers.tf` and `local_mode = true` are what point it
at the emulator.

```
                                  VPC 10.1.0.0/16
   ┌───────────────────────────────────────────────────────────────────┐
   │  public (1a, 1b)                  private (1a, 1b)                │
   │  ┌───────────────┐   :8080   ┌──────────────────┐                 │
   │  │  ALB  :80     │──────────▶│  EC2  order-api  │                 │
   │  └───────────────┘           │  (Docker, ECR)   │                 │
   │         ▲                    └───┬──────────┬───┘                 │
   │         │ internet        :5432  │          │  SendMessage        │
   │         │                        ▼          ▼                     │
   │  ┌───────────────┐        ┌──────────┐  ┌───────────┐  3 fails   │
   │  │  NAT gateway  │        │   RDS    │  │ SQS orders│───────────┐ │
   │  └───────────────┘        │ Postgres │  └─────┬─────┘           │ │
   │                           └──────────┘        │ event source    ▼ │
   │                                               ▼          ┌─────────┐
   │                                     ┌──────────────────┐ │   DLQ   │
   │                                     │ Lambda  notify   │ └─────────┘
   │                                     └──────────────────┘   (alarm) │
   └───────────────────────────────────────────────────────────────────┘
                     │ logs (awslogs driver / Lambda)   │ metrics
                     ▼                                  ▼
             CloudWatch:  /order-lab/api   /aws/lambda/order-lab-notify
                          order-lab/OrdersCreated  NotificationsSent  NotificationsFailed
                          alarms: dlq-not-empty, notification-failures
```

## The decision

**Accepting an order and notifying the customer are separate.** The API
writes the order to Postgres, puts a message on the queue, and answers.
It never knows whether the notification went out. If the notifier is broken,
orders still get accepted, messages wait, and after three failed attempts
they land in a dead-letter queue -- where an alarm is watching.

Everything else in the diagram follows from that split.

| Component | Why it is where it is |
|---|---|
| **ALB** — public subnets | The only public address. Terminates HTTP, health-checks `/health`, forwards to the instance's security group and nothing else. |
| **EC2 + Docker** — private subnet | Runs the API image pulled from ECR. Has no public IP; reaches ECR, SQS and CloudWatch through the NAT gateway. |
| **RDS Postgres** — private subnets | The system of record. Its security group admits port 5432 from the API's group only. Has no egress rule at all. |
| **SQS** | The hand-off. Visibility timeout longer than the Lambda timeout; redrive to a DLQ after 3 receives. |
| **Lambda** | Pulled by an event source mapping, not called by the API. Reports per-message failures so one bad order does not fail its batch. |
| **CloudWatch** | Two log groups, one metric namespace, two alarms. The API container ships logs through Docker's `awslogs` driver; no agent on the instance. |

## What Terraform builds

| File | Resources |
|---|---|
| `network.tf` | VPC, 2 public + 2 private subnets across 2 AZs, IGW, NAT gateway + EIP, route tables |
| `security.tf` | `alb` → `app` → `db`, each admitting only the tier in front of it, by group reference |
| `iam.tf` | Instance role (pull image, send to queue, write logs/metrics) and Lambda role (consume queue, write logs/metrics) |
| `data.tf` | RDS subnet group + Postgres 16, orders queue + DLQ with redrive policy |
| `compute.tf` | ECR repository, EC2 instance with user-data bootstrap, ALB + target group + listener |
| `lambda.tf` | Notify function (zipped from `lambda/notify.py`) + SQS event source mapping |
| `observability.tf` | Log groups, DLQ alarm, failure-metric alarm |

## Running it

Prerequisites: Docker, Terraform. Commands are bash; on Windows run them
from Git Bash or `bash scripts/...` from PowerShell.

```powershell
# 1. Emulator + console (separate repo)
cd ..\floci-ui
docker compose up -d                  # emulator :4566, console :4500

# 2. Infrastructure. The instance pulls the image at boot, so the
#    repository has to exist and be populated before the instance is created.
cd ..\order-lab
terraform -chdir=terraform init
terraform -chdir=terraform apply -auto-approve -target=aws_ecr_repository.api
bash scripts/push-image.sh            # build app/, push to ECR
terraform -chdir=terraform apply -auto-approve
# ~2 min. The instance then installs Docker and starts the API: ~1 more min.

# 3. Local stand-in for the ALB (see "What is real")
bash scripts/alb-local.sh             # http://localhost:8000

# 4. Walk an order through
bash scripts/demo.sh

# 5. Tear down
bash scripts/down.sh
```

`scripts/demo.sh` places an order, reads it back from Postgres, finds the
Lambda's log line for it by trace id, shows the same trace id in the API's
log group, lists the metrics, then places an order the notifier rejects and
watches it reach the DLQ and trip the alarm.

To poke at it yourself:

```powershell
curl -X POST http://localhost:8000/orders -H "Content-Type: application/json" -d '{"customer":"ada","item":"keyboard","quantity":2}'
curl http://localhost:8000/orders

# Inside the instance (it is a container locally):
docker exec -it floci-ec2-$(terraform -chdir=terraform output -raw app_instance_id) bash
  cat /var/log/app-bootstrap.log
  docker logs order-api
```

Resources, logs and metrics are all visible in the console at http://localhost:4500.

## Changing the app

Edit `app/api.py`, then:

```bash
bash scripts/push-image.sh
terraform -chdir=terraform apply -replace=aws_instance.app -auto-approve
bash scripts/alb-local.sh             # the instance id changed
```

The instance is immutable: a new image means a new instance that pulls it
at boot. Nothing is edited in place. (An Auto Scaling group with a launch
template would do this rollout for you; here there is one instance and
`-replace` does it by hand.)

## Observability, honestly

| Pillar | What is here | What a production system adds |
|---|---|---|
| **Logs** | Structured JSON from the API via the `awslogs` driver; Lambda's own log group. Both filterable by `trace_id`. | Logs Insights queries saved as dashboards; retention policy per group. |
| **Metrics** | `OrdersCreated`, `NotificationsSent`, `NotificationsFailed` in the `order-lab` namespace. | The AWS-published metrics (ALB 5xx, RDS connections, Lambda duration, SQS age) -- free in a real account, mostly absent in the emulator. |
| **Traces** | A `trace_id` minted by the API, carried in the SQS message attributes, logged by the Lambda. Grep one id across both log groups and you have the trace. | X-Ray (`aws_xray_sampling_rule`, the SDK, Lambda `tracing_config`) or **Dynatrace**: OneAgent on the instance via user data, the Lambda layer, and the AWS integration pulling CloudWatch. Neither has an emulator. Dynatrace's *Service Flow* is exactly the API → SQS → Lambda picture this trace id draws by hand. |
| **Alerts** | `notification-failures` (custom metric, fires within a minute) and `dlq-not-empty` (AWS/SQS metric). | SNS topic as `alarm_actions`; a composite alarm so the two do not page twice for one incident. |

## Diagram

`docs/architecture.html` — an interactive version of the picture above with
three guided views (the request, the notification, observability). Open it in
a browser. Source: `docs/architecture.archify.json`.

## Next steps

1. **Take the password out of user data.** A `aws_secretsmanager_secret` for the DB credentials, `secretsmanager:GetSecretValue` in the instance role, and the app reading it at start — gap 5 in the list above. pipeline-lab shows the same pattern with External Secrets.
2. **Replace `-replace` with an Auto Scaling group.** A launch template with the same user data, an ASG of 1–2 behind the target group, and an instance refresh on image change: the rollout the README does by hand.
3. **Drop the NAT gateway.** VPC endpoints for ECR, SQS, CloudWatch Logs and Secrets Manager; the instance then needs no route to the internet at all.
4. **Real traces.** X-Ray (`aws_xray_sampling_rule`, the SDK in the app and Lambda, `tracing_config` on the function) or Dynatrace OneAgent via user data — the "Service Flow" the trace id draws by hand today.
5. **Move the consumer out of the request path further.** A second Lambda (or a Fargate task) for a slow step such as fulfilment, fanned out through SNS → two queues.
6. **Put it through a pipeline.** pipeline-lab's `scripts/ci/` stages work unchanged on this app; the deploy stage becomes `terraform apply -replace` (or, after step 2, an instance refresh).

## What is real and what is not

Floci does a lot more than return metadata:

- **EC2 is a real instance.** An Amazon Linux 2023 container with the user data executed: it installs Docker, pulls the image from ECR, and runs it with the `awslogs` log driver. The API log group in CloudWatch is filled by that driver, not by anything simulated.
- **RDS is a real Postgres 16** (a `postgres:16-alpine` container). The orders are in a real table.
- **SQS, Lambda, the event source mapping, the DLQ redrive** all genuinely work: the Lambda runs in its own container, per-message failures go back to the queue, and after three receives SQS moves the message to the DLQ.
- **CloudWatch Logs, custom metrics, and alarms on custom metrics** work; `notification-failures` really goes to `ALARM`.
- **ECR is a real registry**; the image is pushed and pulled.

The gaps, stated here rather than left to be found:

1. **The ALB forwards nothing.** It is metadata (created, validated -- it refuses one AZ -- and visible in the console). `scripts/alb-local.sh` runs a `socat` container on the emulator's network that does the ALB's job: host port 8000 → the instance's port 8080.
2. **The registry has three names.** From this machine it is `localhost:5100`; ECR reports it as `<account>.dkr.ecr.<region>.localhost:5100`, which Windows resolves unreliably; from inside the instance it is `floci-ecr-registry:5000` over plain HTTP. `local_mode` in `variables.tf` selects the last one for the bootstrap. In AWS there is one name and `docker login` in front of it.
3. **`dlq-not-empty` stays `OK`.** Floci does not publish the `AWS/SQS` metrics, so the alarm never sees a datapoint. In AWS it would fire about a minute after the demo's poison order. The custom-metric alarm is the one that fires locally.
4. **Security groups are not enforced locally.** Created, referenced, inspectable; not filtering.
5. **The database password travels through user data.** Visible to anyone who can read the instance's metadata. The fix is Secrets Manager plus a `secretsmanager:GetSecretValue` statement in the instance role, with the app reading it at start.
6. **`max_retries = 2` in the provider is for the emulator.** Deleting a load balancer makes the provider poll `DescribeNetworkInterfaces` in a way Floci answers with a 500; the SDK's default 25 retries turn that into a half-hour hang. Remove it against a real account.
7. **Instances do not survive a Docker restart.** The emulated EC2 container stays stopped and Terraform still thinks it is running. Recreate it: `terraform -chdir=terraform apply -replace=aws_instance.app -auto-approve`, then `scripts/alb-local.sh` again.

## Layout

```
terraform/     VPC, subnets, NAT, security groups, IAM, RDS, SQS, Lambda, ECR, EC2, ALB, CloudWatch
app/           the order API (Flask + psycopg + boto3) and its Dockerfile
lambda/        notify.py
scripts/       push-image.sh, alb-local.sh, demo.sh, down.sh, app-bootstrap.sh (EC2 user data)
```
