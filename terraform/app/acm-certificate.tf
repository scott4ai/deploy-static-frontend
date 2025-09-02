# ACM Certificate for HTTPS
resource "aws_acm_certificate" "main" {
  count             = var.domain_name != "" ? 1 : 0
  domain_name       = var.domain_name
  validation_method = "DNS"

  # No alternative names needed for API subdomain
  subject_alternative_names = []

  tags = merge(
    local.common_tags,
    {
      Name = "${local.project_name}-${local.environment}-cert"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Automatic DNS validation if using Route 53
data "aws_route53_zone" "main" {
  count        = var.create_route53_records && var.route53_zone_id == "" ? 1 : 0
  name         = var.domain_name
  private_zone = false
}

resource "aws_route53_record" "cert_validation" {
  for_each = var.create_route53_records && var.domain_name != "" ? {
    for dvo in aws_acm_certificate.main[0].domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.route53_zone_id != "" ? var.route53_zone_id : data.aws_route53_zone.main[0].zone_id
}

# Certificate validation
resource "aws_acm_certificate_validation" "main" {
  count                   = var.domain_name != "" ? 1 : 0
  certificate_arn         = aws_acm_certificate.main[0].arn
  validation_record_fqdns = var.create_route53_records ? [for record in aws_route53_record.cert_validation : record.fqdn] : []
}

# Update ALB listener to use HTTPS
resource "aws_lb_listener" "https" {
  count             = var.domain_name != "" ? 1 : 0
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"  # Latest TLS 1.3 policy
  certificate_arn   = aws_acm_certificate_validation.main[0].certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ec2.arn
  }

  depends_on = [
    aws_acm_certificate_validation.main
  ]
}

# Update HTTP listener to redirect to HTTPS
resource "aws_lb_listener_rule" "http_redirect" {
  count        = var.domain_name != "" ? 1 : 0
  listener_arn = aws_lb_listener.http.arn
  priority     = 1

  action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  condition {
    host_header {
      values = [var.domain_name]
    }
  }
}

# CloudWatch alarm for certificate expiration monitoring
resource "aws_cloudwatch_metric_alarm" "certificate_expiry" {
  count = var.domain_name != "" ? 1 : 0
  
  alarm_name          = "${local.project_name}-${local.environment}-cert-expiry"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "DaysToExpiry"
  namespace           = "AWS/CertificateManager"
  period              = "86400"  # Daily
  statistic           = "Minimum"
  threshold           = "30"     # Alert when less than 30 days to expiry
  alarm_description   = "This metric monitors SSL certificate expiration"
  treat_missing_data  = "breaching"

  dimensions = {
    CertificateArn = aws_acm_certificate.main[0].arn
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.project_name}-${local.environment}-cert-expiry-alarm"
    }
  )
}
