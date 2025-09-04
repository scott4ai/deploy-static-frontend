# Launch Template for EC2 instances
resource "aws_launch_template" "web" {
  name          = "${local.project_name}-${local.environment}-web-template"
  image_id      = local.use_custom_ami ? local.ami_id : data.aws_ami.amazon_linux[0].id
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.ec2.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  monitoring {
    enabled = var.enable_detailed_monitoring
  }

  # User data script to configure the instance
  user_data = base64encode(templatefile(
    local.use_custom_ami ? "${path.module}/user-data-ami.sh" : "${path.module}/user-data.sh", 
    {
      s3_bucket_name       = data.aws_s3_bucket.frontend_assets.bucket
      aws_region          = local.aws_region
      environment         = local.environment
      project_name        = local.project_name
      lambda_function_url = "http://${aws_lb.main.dns_name}"  # ALB will proxy to Lambda
    }
  ))

  # Instance metadata options for security
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      local.common_tags,
      {
        Name = "${local.project_name}-${local.environment}-web"
        S3Bucket = data.aws_s3_bucket.frontend_assets.bucket
      }
    )
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    data.terraform_remote_state.ami
  ]
}

# Auto Scaling Group
resource "aws_autoscaling_group" "web" {
  name                = "${local.project_name}-${local.environment}-web-asg"
  vpc_zone_identifier = local.private_subnet_ids
  target_group_arns   = [aws_lb_target_group.ec2.arn]
  health_check_type   = "ELB"
  health_check_grace_period = 300

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  # Instance refresh - terminate all instances immediately on every deploy
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 0  # Terminate all instances immediately
      instance_warmup = 60        # Quick warmup time
    }
    triggers = ["tag"]
  }

  # Instances spread across AZs via vpc_zone_identifier (subnets)
  # availability_zones not needed when using vpc_zone_identifier

  tag {
    key                 = "Name"
    value               = "${local.project_name}-${local.environment}-web"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = local.environment
    propagate_at_launch = true
  }

  # Force instance refresh on every deploy for safety
  tag {
    key                 = "LastDeployed"
    value               = timestamp()
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = local.project_name
    propagate_at_launch = true
  }

  tag {
    key                 = "ManagedBy"
    value               = "terraform"
    propagate_at_launch = true
  }

  tag {
    key                 = "S3Bucket"
    value               = data.aws_s3_bucket.frontend_assets.bucket
    propagate_at_launch = true
  }

  # Lifecycle hook for graceful shutdown (optional)
  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_lb_target_group.ec2]
}

# Auto Scaling Policies
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "${local.project_name}-${local.environment}-scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.web.name
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "${local.project_name}-${local.environment}-scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.web.name
}

# CloudWatch Alarms for Auto Scaling
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${local.project_name}-${local.environment}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "70"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web.name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "${local.project_name}-${local.environment}-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "20"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.scale_down.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web.name
  }

  tags = local.common_tags
}

# CloudWatch Alarm for ALB target health
resource "aws_cloudwatch_metric_alarm" "alb_target_health" {
  alarm_name          = "${local.project_name}-${local.environment}-alb-unhealthy-targets"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "This metric monitors ALB healthy target count"
  treat_missing_data  = "breaching"

  dimensions = {
    TargetGroup  = aws_lb_target_group.ec2.arn_suffix
    LoadBalancer = aws_lb.main.arn_suffix
  }

  tags = local.common_tags
}