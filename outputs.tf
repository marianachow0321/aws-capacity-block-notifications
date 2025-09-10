output "sns_topic_arn" {
  description = "ARN of the SNS topic for capacity block alerts"
  value       = aws_sns_topic.capacity_block_alerts.arn
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.capacity_block_checker.arn
}

output "eventbridge_rule_native_arn" {
  description = "ARN of the native EventBridge rule"
  value       = aws_cloudwatch_event_rule.native_expiry.arn
}

output "eventbridge_rule_daily_arn" {
  description = "ARN of the daily schedule EventBridge rule"
  value       = aws_cloudwatch_event_rule.daily_schedule.arn
}
