# Application Load Balancer
resource "aws_lb" "main" {
  name               = "${local.project_name}-${local.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.public_subnet_ids

  enable_deletion_protection = false

  # Enable access logs (optional - requires S3 bucket)
  # access_logs {
  #   bucket  = aws_s3_bucket.alb_logs.bucket
  #   prefix  = "access-logs"
  #   enabled = true
  # }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.project_name}-${local.environment}-alb"
    }
  )
}

# Target Group for EC2 instances
resource "aws_lb_target_group" "ec2" {
  name     = "${local.project_name}-${local.environment}-ec2-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = local.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/health"
    matcher             = "200"
    port                = "traffic-port"
    protocol            = "HTTP"
  }

  # Stickiness for better load balancing demonstration
  stickiness {
    type            = "lb_cookie"
    cookie_duration = 300  # 5 minutes
    enabled         = false  # Disabled to show load balancing better
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.project_name}-${local.environment}-ec2-tg"
    }
  )
}

# Target Group for Lambda function
resource "aws_lb_target_group" "lambda" {
  name        = "${local.project_name}-${local.environment}-lambda-tg"
  target_type = "lambda"

  tags = merge(
    local.common_tags,
    {
      Name = "${local.project_name}-${local.environment}-lambda-tg"
    }
  )
}

# Lambda permission for ALB to invoke
resource "aws_lambda_permission" "alb_invoke" {
  statement_id  = "AllowExecutionFromALB"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.lambda.arn
}

# Attach Lambda to target group
resource "aws_lb_target_group_attachment" "lambda" {
  target_group_arn = aws_lb_target_group.lambda.arn
  target_id        = aws_lambda_function.api.arn
  depends_on       = [aws_lambda_permission.alb_invoke]
}

# HTTP Listener (redirect to HTTPS if certificate available)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  # If SSL certificate is available, redirect to HTTPS
  # Otherwise, forward to EC2 instances
  dynamic "default_action" {
    for_each = var.ssl_certificate_arn != "" || var.domain_name != "" ? [1] : []
    content {
      type = "redirect"
      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  dynamic "default_action" {
    for_each = var.ssl_certificate_arn == "" && var.domain_name == "" ? [1] : []
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.ec2.arn
    }
  }

  # Rules for API endpoints go to Lambda
  depends_on = [aws_lb_target_group.ec2, aws_lb_target_group.lambda]
}

# HTTP Listener Rules for API routing (when using HTTP only)
resource "aws_lb_listener_rule" "api_http" {
  count        = var.ssl_certificate_arn == "" && var.domain_name == "" ? 1 : 0
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lambda.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
}

# Health endpoint handled by default EC2 action, no special rule needed

# Note: HTTPS listener and ACM certificate configuration moved to acm-certificate.tf

# HTTPS Listener Rules for API routing
resource "aws_lb_listener_rule" "api_https" {
  count        = var.ssl_certificate_arn != "" || var.domain_name != "" ? 1 : 0
  listener_arn = aws_lb_listener.https[0].arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lambda.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
}

# Health endpoint should go to EC2 instances (default action), not Lambda