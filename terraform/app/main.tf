# Fetch AMI ID from ami stack
data "terraform_remote_state" "ami" {
  backend = "local"

  config = {
    path = "../ami/terraform.tfstate"
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
  
  # Use AMI from ami stack if available, fallback to custom AMI, then default
  # Also check the temp file directly to avoid state caching issues
  ami_from_file = try(trimspace(file("/tmp/terraform_built_ami_id")), "")
  ami_id = local.ami_from_file != "" ? local.ami_from_file : try(data.terraform_remote_state.ami.outputs.built_ami_id, var.custom_ami_id != "" ? var.custom_ami_id : "")
  use_custom_ami = local.ami_id != ""
  
  # Use S3 bucket created by ami stack
  s3_bucket_name = data.terraform_remote_state.ami.outputs.frontend_assets_bucket
  
  # Use VPC info from VPC stack
  vpc_id = data.terraform_remote_state.vpc.outputs.vpc_id
  public_subnet_ids = data.terraform_remote_state.vpc.outputs.public_subnet_ids
  private_subnet_ids = data.terraform_remote_state.vpc.outputs.private_subnet_ids
  vpc_cidr_block = data.terraform_remote_state.vpc.outputs.vpc_cidr_block
  
  # Domain configuration conditions (like CloudFormation)
  has_domain_name = var.domain_name != ""
  create_route53_records = local.has_domain_name && var.create_route53_records
  enable_waf = var.enable_waf
}

# Random suffix no longer needed - AMI stack creates bucket with unique naming

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

# Reference S3 bucket created by AMI stack
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
          "s3:ListBucket",
          "s3:DeleteObject"
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
  name              = "/aws/ec2/${local.project_name}/nginx/access"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "nginx_error" {
  name              = "/aws/ec2/${local.project_name}/nginx/error"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "hitl_sync" {
  name              = "/aws/ec2/${local.project_name}/sync"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.project_name}-${local.environment}-api"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

# Build and upload frontend to S3
resource "null_resource" "build_and_upload_frontend" {
  provisioner "local-exec" {
    command = <<-EOF
      cd "${path.root}/../../demo-app"
      
      # Build the React frontend
      echo "Building React frontend..."
      npm install
      npm run build
      
      # Upload to S3
      echo "Uploading frontend to s3://${local.s3_bucket_name}/build/"
      
      # Upload all files except index.html with long cache (1 year)
      aws s3 sync build/ "s3://${local.s3_bucket_name}/build/" \
        --region ${local.aws_region} \
        --delete \
        --cache-control "public, max-age=31536000" \
        --exclude "index.html"
      
      # Upload index.html with no-cache headers
      if [ -f "build/index.html" ]; then
        aws s3 cp build/index.html "s3://${local.s3_bucket_name}/build/" \
          --region ${local.aws_region} \
          --cache-control "no-cache, no-store, must-revalidate" \
          --content-type "text/html"
      fi
      
      echo "Frontend build and upload completed successfully"
    EOF
  }
  
  # Re-run if frontend source changes
  triggers = {
    frontend_src_hash = md5(join("", [
      for f in fileset("${path.root}/../../demo-app/src", "**/*") : 
      filemd5("${path.root}/../../demo-app/src/${f}")
    ]))
    package_json_hash = filemd5("${path.root}/../../demo-app/package.json")
  }
  
  # Depends on the infrastructure being ready
  depends_on = [
    aws_lb.main,
    aws_autoscaling_group.web
  ]
}