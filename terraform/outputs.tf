output "alb_dns" {
  description = "Public entry point. In AWS this resolves to the ALB; locally it is metadata and scripts/alb-local.sh runs a stand-in on port 8000."
  value       = aws_lb.api.dns_name
}

output "ecr_repository_url" {
  description = "Where scripts/push-image.sh pushes the API image."
  value       = aws_ecr_repository.api.repository_url
}

output "app_instance_id" {
  value = aws_instance.app.id
}

output "app_private_ip" {
  value = aws_instance.app.private_ip
}

output "db_endpoint" {
  value = "${aws_db_instance.orders.address}:${aws_db_instance.orders.port}"
}

output "orders_queue_url" {
  value = aws_sqs_queue.orders.url
}

output "orders_dlq_url" {
  value = aws_sqs_queue.orders_dlq.url
}

output "notify_function_name" {
  value = aws_lambda_function.notify.function_name
}

output "app_log_group" {
  value = aws_cloudwatch_log_group.app.name
}
