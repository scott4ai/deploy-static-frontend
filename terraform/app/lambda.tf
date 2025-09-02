# Lambda function for API backend
resource "aws_lambda_function" "api" {
  filename         = var.lambda_zip_path
  function_name    = "${local.project_name}-${local.environment}-api"
  role            = aws_iam_role.lambda_role.arn
  handler         = var.lambda_handler
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory

  source_code_hash = filebase64sha256(var.lambda_zip_path)

  # VPC configuration for private subnets
  vpc_config {
    subnet_ids         = local.private_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      ENVIRONMENT              = local.environment
      PROJECT_NAME             = local.project_name
      LOG_LEVEL                = "INFO"
      USER_POOL_ID             = var.cognito_user_pool_id
      USER_POOL_CLIENT_ID      = var.cognito_user_pool_client_id
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_logs,
    aws_cloudwatch_log_group.lambda_logs,
  ]

  tags = merge(
    local.common_tags,
    {
      Name = "${local.project_name}-${local.environment}-api"
    }
  )
}

# Lambda alias for blue/green deployments (optional)
resource "aws_lambda_alias" "api_live" {
  name             = "live"
  description      = "Live version of the API"
  function_name    = aws_lambda_function.api.function_name
  function_version = "$LATEST"

  lifecycle {
    ignore_changes = [function_version]
  }
}

# Lambda function URL (alternative to ALB, but we'll use ALB)
# resource "aws_lambda_function_url" "api" {
#   function_name      = aws_lambda_function.api.function_name
#   authorization_type = "NONE"
#   
#   cors {
#     allow_credentials = false
#     allow_origins     = ["*"]
#     allow_methods     = ["*"]
#     allow_headers     = ["date", "keep-alive"]
#     expose_headers    = ["date", "keep-alive"]
#     max_age          = 86400
#   }
# }

# WAF Web ACL (if enabled)

# CloudWatch dashboard for monitoring
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.project_name}-${local.environment}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.main.arn_suffix],
            [".", "TargetResponseTime", ".", "."],
            [".", "HTTPCode_Target_2XX_Count", ".", "."],
            [".", "HTTPCode_Target_4XX_Count", ".", "."],
            [".", "HTTPCode_Target_5XX_Count", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = local.aws_region
          title   = "ALB Metrics"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.api.function_name],
            [".", "Errors", ".", "."],
            [".", "Invocations", ".", "."],
            [".", "Throttles", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = local.aws_region
          title   = "Lambda Metrics"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", aws_autoscaling_group.web.name],
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", aws_lb_target_group.ec2.arn_suffix, "LoadBalancer", aws_lb.main.arn_suffix],
            [".", "UnHealthyHostCount", ".", ".", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = local.aws_region
          title   = "EC2 and Health Metrics"
          period  = 300
        }
      }
    ]
  })

  depends_on = [
    aws_lb.main,
    aws_lambda_function.api,
    aws_autoscaling_group.web
  ]
}