# ---------------------------------------------------------------------------
# Data: the database and the queue.
#
# Two different kinds of state. Postgres is the system of record -- an order
# exists once it is in this table. The queue is a hand-off: the API has done
# its part when the message is sent, and whatever happens downstream (the
# notification) cannot lose the order or block the customer's request.
# ---------------------------------------------------------------------------

# --- RDS -------------------------------------------------------------------

resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = aws_subnet.private[*].id
  tags       = { Name = var.name }
}

resource "aws_db_instance" "orders" {
  identifier = var.name

  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t3.micro"

  allocated_storage = 20

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false

  # Lab settings. A production instance is multi_az, keeps backups, and
  # takes a final snapshot on destroy.
  multi_az                = false
  backup_retention_period = 0
  skip_final_snapshot     = true
  deletion_protection     = false

  tags = { Name = var.name }
}

# --- SQS -------------------------------------------------------------------

# Messages the notifier fails on three times land here instead of being
# retried forever. The alarm in observability.tf watches this queue: a
# non-empty DLQ is the signal that notifications are being lost.
resource "aws_sqs_queue" "orders_dlq" {
  name                      = "${var.name}-orders-dlq"
  message_retention_seconds = 1209600 # 14 days, the maximum
  tags                      = { Name = "${var.name}-orders-dlq" }
}

resource "aws_sqs_queue" "orders" {
  name = "${var.name}-orders"

  # Longer than the Lambda timeout, so a message is never handed to a second
  # invocation while the first is still working on it.
  visibility_timeout_seconds = 60

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.orders_dlq.arn
    maxReceiveCount     = 3
  })

  tags = { Name = "${var.name}-orders" }
}
