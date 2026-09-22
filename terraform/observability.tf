# ---------------------------------------------------------------------------
# Observability: CloudWatch.
#
#   Logs     two log groups, one per component. The API container ships its
#            stdout through Docker's awslogs driver; Lambda ships its own.
#   Metrics  custom namespace "order-lab": OrdersCreated from the API,
#            NotificationsSent / NotificationsFailed from the Lambda.
#   Alarms   one on the DLQ (notifications being lost) and one on the
#            failure metric (notifications failing right now).
#   Traces   every order carries a trace id from the API, through the queue
#            message attributes, into the Lambda log line -- greppable across
#            both log groups. Real tracing is X-Ray or Dynatrace; see README.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "app" {
  name              = "/${var.name}/api"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "notify" {
  name              = "/aws/lambda/${var.name}-notify"
  retention_in_days = 7
}

# Anything in the DLQ is an order whose customer was not notified. Fires on
# the first message and stays on until the queue is drained.
resource "aws_cloudwatch_metric_alarm" "dlq_not_empty" {
  alarm_name          = "${var.name}-dlq-not-empty"
  alarm_description   = "Orders whose notification failed three times"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.orders_dlq.name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
}

# Earlier signal than the DLQ: the first failure, before the retries.
resource "aws_cloudwatch_metric_alarm" "notification_failures" {
  alarm_name          = "${var.name}-notification-failures"
  alarm_description   = "The notifier raised on at least one order in the last minute"
  namespace           = var.name
  metric_name         = "NotificationsFailed"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
}
