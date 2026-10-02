# ---------------------------------------------------------------------------
# Notification Lambda.
#
# Triggered by the orders queue, not by the API. The API never knows whether
# a notification went out and does not wait for it -- which is the point of
# the queue. If this function is broken, orders still get accepted and the
# messages wait (then dead-letter, and the alarm fires).
# ---------------------------------------------------------------------------

data "archive_file" "notify" {
  type        = "zip"
  source_file = "${path.module}/../lambda/notify.py"
  output_path = "${path.module}/.build/notify.zip"
}

resource "aws_lambda_function" "notify" {
  function_name = "${var.name}-notify"
  role          = aws_iam_role.notify.arn

  runtime = "python3.12"
  handler = "notify.handler"
  timeout = 10

  filename         = data.archive_file.notify.output_path
  source_code_hash = data.archive_file.notify.output_base64sha256

  environment {
    variables = {
      METRIC_NAMESPACE = var.name
      SENT_TABLE       = aws_dynamodb_table.notifications_sent.name
      # The function runs in its own container and reaches the emulator by
      # service name. Not called AWS_ENDPOINT_URL because Lambda reserves
      # parts of the AWS_* namespace. Empty against a real account.
      ORDER_LAB_ENDPOINT = var.internal_endpoint_url == null ? "" : var.internal_endpoint_url
    }
  }

  depends_on = [aws_cloudwatch_log_group.notify]
}

# Poll the queue and invoke the function with batches. This is Lambda pulling
# from SQS on our behalf; there is no code that calls ReceiveMessage.
resource "aws_lambda_event_source_mapping" "orders" {
  event_source_arn = aws_sqs_queue.orders.arn
  function_name    = aws_lambda_function.notify.arn
  batch_size       = 5

  # Report per-message failures instead of failing the whole batch, so one
  # bad order does not send its four batch-mates back to the queue with it.
  function_response_types = ["ReportBatchItemFailures"]
}
