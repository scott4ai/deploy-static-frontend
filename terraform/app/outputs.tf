output "alb_dns_name" {
  description = "DNS name of the load balancer"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the load balancer"
  value       = aws_lb.main.zone_id
}

output "alb_arn" {
  description = "ARN of the load balancer"
  value       = aws_lb.main.arn
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for frontend assets"
  value       = data.aws_s3_bucket.frontend_assets.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for frontend assets"
  value       = data.aws_s3_bucket.frontend_assets.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.api.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.api.arn
}

output "lambda_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.api.invoke_arn
}

output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.web.name
}

output "autoscaling_group_arn" {
  description = "ARN of the Auto Scaling Group"
  value       = aws_autoscaling_group.web.arn
}

output "ec2_security_group_id" {
  description = "ID of the EC2 security group"
  value       = aws_security_group.ec2.id
}

output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "lambda_security_group_id" {
  description = "ID of the Lambda security group"
  value       = aws_security_group.lambda.id
}

output "waf_web_acl_id" {
  description = "ID of the WAF Web ACL"
  value       = var.enable_waf ? aws_wafv2_web_acl.main[0].id : null
}

output "waf_web_acl_arn" {
  description = "ARN of the WAF Web ACL"
  value       = var.enable_waf ? aws_wafv2_web_acl.main[0].arn : null
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = "https://${local.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${local.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

# Application URLs
output "application_url" {
  description = "Application URL (HTTP)"
  value       = "http://${aws_lb.main.dns_name}"
}

output "application_https_url" {
  description = "Application URL (HTTPS) - only if domain configured"
  value       = local.has_domain_name ? "https://${var.domain_name}" : null
}

output "load_balancer_dns_name" {
  description = "DNS name of the load balancer"
  value       = aws_lb.main.dns_name
}

output "domain_url" {
  description = "The HTTPS URL of the application (if domain configured)"
  value       = local.has_domain_name ? "https://${var.domain_name}" : null
}

output "certificate_arn" {
  description = "ARN of the SSL certificate"
  value       = local.has_domain_name ? aws_acm_certificate.main[0].arn : null
}

output "web_acl_arn" {
  description = "ARN of the WAF Web ACL"
  value       = local.enable_waf ? aws_wafv2_web_acl.main[0].arn : null
}

# Outputs for deployment scripts
output "deployment_info" {
  description = "Information needed for deployment"
  value = {
    s3_bucket           = data.aws_s3_bucket.frontend_assets.bucket
    alb_dns_name       = aws_lb.main.dns_name
    lambda_function    = aws_lambda_function.api.function_name
    autoscaling_group  = aws_autoscaling_group.web.name
    environment        = local.environment
    project_name       = local.project_name
    aws_region         = local.aws_region
  }
}

# Outputs for monitoring
output "monitoring_info" {
  description = "Information for monitoring and alerts"
  value = {
    cloudwatch_dashboard = aws_cloudwatch_dashboard.main.dashboard_name
    log_groups = {
      nginx_access = aws_cloudwatch_log_group.nginx_access.name
      nginx_error  = aws_cloudwatch_log_group.nginx_error.name
      hitl_sync    = aws_cloudwatch_log_group.hitl_sync.name
      lambda_logs  = aws_cloudwatch_log_group.lambda_logs.name
    }
    alarms = {
      cpu_high           = aws_cloudwatch_metric_alarm.cpu_high.alarm_name
      cpu_low            = aws_cloudwatch_metric_alarm.cpu_low.alarm_name
      alb_target_health  = aws_cloudwatch_metric_alarm.alb_target_health.alarm_name
    }
  }
}