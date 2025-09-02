# Fetch AMI ID from image-builder stack
data "terraform_remote_state" "image_builder" {
  backend = "local"

  config = {
    path = "../image-builder/terraform.tfstate"
  }
}

# Fetch VPC info from VPC stack
data "terraform_remote_state" "vpc" {
  backend = "local"

  config = {
    path = "../vpc/terraform.tfstate"
  }
}

locals {
  # Get core configuration from VPC remote state
  aws_region = data.terraform_remote_state.vpc.outputs.aws_region
  environment = data.terraform_remote_state.vpc.outputs.environment
  project_name = data.terraform_remote_state.vpc.outputs.project_name
  
  common_tags = merge(
    var.common_tags,
    {
      Environment = local.environment
      Project     = local.project_name
      ManagedBy   = "terraform"
      Stack       = "app"
    }
  )
  
  # Use AMI from image-builder stack if available, fallback to custom AMI, then default
  ami_id = try(data.terraform_remote_state.image_builder.outputs.built_ami_id, var.custom_ami_id != "" ? var.custom_ami_id : "")
  use_custom_ami = local.ami_id != ""
  
  # Use S3 bucket created by image-builder stack
  s3_bucket_name = data.terraform_remote_state.image_builder.outputs.frontend_assets_bucket
  
  # Use VPC info from VPC stack
  vpc_id = data.terraform_remote_state.vpc.outputs.vpc_id
  public_subnet_ids = data.terraform_remote_state.vpc.outputs.public_subnet_ids
  private_subnet_ids = data.terraform_remote_state.vpc.outputs.private_subnet_ids
  vpc_cidr_block = data.terraform_remote_state.vpc.outputs.vpc_cidr_block
}

# Random suffix no longer needed - Image Builder creates bucket with unique naming

# Data source to get latest Amazon Linux 2 AMI if custom AMI not provided
data "aws_ami" "amazon_linux" {
  count       = local.use_custom_ami ? 0 : 1
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Get availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Reference S3 bucket created by Image Builder stack
data "aws_s3_bucket" "frontend_assets" {
  bucket = local.s3_bucket_name
}

# S3 bucket policy for EC2 instances
resource "aws_s3_bucket_policy" "frontend_assets" {
  bucket = data.aws_s3_bucket.frontend_assets.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowEC2InstancesRead"
        Effect    = "Allow"
        Principal = {
          AWS = aws_iam_role.ec2_role.arn
        }
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          data.aws_s3_bucket.frontend_assets.arn,
          "${data.aws_s3_bucket.frontend_assets.arn}/*"
        ]
      }
    ]
  })
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "nginx_access" {
  name              = "/aws/ec2/nginx/access"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "nginx_error" {
  name              = "/aws/ec2/nginx/error"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "hitl_sync" {
  name              = "/aws/ec2/hitl/sync"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.project_name}-${local.environment}-api"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}