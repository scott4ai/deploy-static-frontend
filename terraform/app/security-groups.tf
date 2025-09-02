# Security Group for Application Load Balancer
resource "aws_security_group" "alb" {
  name        = "${local.project_name}-${local.environment}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = local.vpc_id

  # HTTP access from internet
  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS access from internet
  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound to EC2 instances
  egress {
    description = "HTTP to EC2 instances"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr_block]
  }

  # Outbound to Lambda (for API calls)
  egress {
    description = "HTTPS for Lambda integration"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.project_name}-${local.environment}-alb-sg"
    }
  )
}

# Security Group for EC2 instances
resource "aws_security_group" "ec2" {
  name        = "${local.project_name}-${local.environment}-ec2-sg"
  description = "Security group for EC2 web servers"
  vpc_id      = local.vpc_id

  # HTTP from ALB only
  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # All outbound traffic (for S3 access via VPC endpoint, package updates)
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.project_name}-${local.environment}-ec2-sg"
    }
  )
}

# Security Group for Lambda function (if in VPC)
resource "aws_security_group" "lambda" {
  name        = "${local.project_name}-${local.environment}-lambda-sg"
  description = "Security group for Lambda function"
  vpc_id      = local.vpc_id

  # No inbound rules needed for Lambda behind ALB
  # ALB handles the incoming traffic

  # Outbound HTTPS for any external API calls Lambda might need
  egress {
    description = "HTTPS outbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound HTTP for internal communication if needed
  egress {
    description = "HTTP outbound"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr_block]
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.project_name}-${local.environment}-lambda-sg"
    }
  )
}