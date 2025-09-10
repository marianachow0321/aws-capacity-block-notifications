data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# SNS Topic
resource "aws_sns_topic" "capacity_block_alerts" {
  name = "capacity-block-expiry-alerts"
}

resource "aws_sns_topic_subscription" "email_notification" {
  topic_arn = aws_sns_topic.capacity_block_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "capacity-block-checker-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_role.name
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "CapacityBlockCheckerPolicy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeCapacityReservations",
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = "sns:Publish"
        Resource = aws_sns_topic.capacity_block_alerts.arn
      }
    ]
  })
}

# Lambda Function
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "capacity-block-checker.py"
  output_path = "capacity-block-checker.zip"
}

resource "aws_lambda_function" "capacity_block_checker" {
  filename         = "capacity-block-checker.zip"
  function_name    = "capacity-block-daily-checker"
  role            = aws_iam_role.lambda_role.arn
  handler         = "capacity-block-checker.lambda_handler"
  runtime         = "python3.13"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  description     = "Check capacity blocks daily and alert 1 day before expiry"
}

# EventBridge Rules
resource "aws_cloudwatch_event_rule" "native_expiry" {
  name        = "capacity-block-expiry-40min-notification"
  description = "Notify 40 minutes before capacity blocks expire"

  event_pattern = jsonencode({
    source       = ["aws.ec2"]
    detail_type  = ["Capacity Block Reservation Expiration Warning"]
  })
}

resource "aws_cloudwatch_event_rule" "daily_schedule" {
  name                = "capacity-block-expiry-1day-notification"
  description         = "Run capacity block checker daily"
  schedule_expression = "rate(1 day)"
}

# EventBridge Targets
resource "aws_cloudwatch_event_target" "sns_native" {
  rule      = aws_cloudwatch_event_rule.native_expiry.name
  target_id = "CapacityBlockSNSTarget"
  arn       = aws_sns_topic.capacity_block_alerts.arn
}

resource "aws_cloudwatch_event_target" "lambda_daily" {
  rule      = aws_cloudwatch_event_rule.daily_schedule.name
  target_id = "CapacityBlockLambdaTarget"
  arn       = aws_lambda_function.capacity_block_checker.arn
}

# Permissions
resource "aws_sns_topic_policy" "capacity_block_alerts_policy" {
  arn = aws_sns_topic.capacity_block_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.capacity_block_alerts.arn
      }
    ]
  })
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.capacity_block_checker.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_schedule.arn
}
