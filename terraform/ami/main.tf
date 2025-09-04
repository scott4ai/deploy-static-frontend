# EC2 AMI Builder for Golden AMI Creation
# AWS native service - much better than Packer for FedRAMP environments

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Fetch VPC configuration from the VPC stack state
data "terraform_remote_state" "vpc" {
  backend = "local"

  config = {
    path = "../vpc/terraform.tfstate"
  }
}

locals {
  # Use VPC stack outputs with variable overrides as fallback
  aws_region   = var.aws_region != "" ? var.aws_region : data.terraform_remote_state.vpc.outputs.aws_region
  environment  = var.environment != "" ? var.environment : data.terraform_remote_state.vpc.outputs.environment
  project_name = var.project_name != "" ? var.project_name : data.terraform_remote_state.vpc.outputs.project_name
  
  vpc_id           = data.terraform_remote_state.vpc.outputs.vpc_id
  public_subnet_id = data.terraform_remote_state.vpc.outputs.public_subnet_ids[0]  # Use first public subnet
  
  common_tags = {
    Environment = local.environment
    Project     = local.project_name
    ManagedBy   = "terraform"
    Stack       = "ami"
  }
}

# IAM role for AMI Builder
resource "aws_iam_role" "ami_instance_role" {
  name = "${local.project_name}-${local.environment}-ami-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# Attach AWS managed policies for AMI Builder
resource "aws_iam_role_policy_attachment" "ami_instance_profile" {
  policy_arn = "arn:aws:iam::aws:policy/EC2InstanceProfileForImageBuilder"
  role       = aws_iam_role.ami_instance_role.name
}

resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.ami_instance_role.name
}

# Custom policy for additional permissions
resource "aws_iam_role_policy" "ami_custom" {
  name = "${local.project_name}-${local.environment}-ami-custom"
  role = aws_iam_role.ami_instance_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = [
          "arn:aws:s3:::${local.project_name}-${local.environment}-*",
          "arn:aws:s3:::${local.project_name}-${local.environment}-*/*",
          "${aws_s3_bucket.ami_logs.arn}",
          "${aws_s3_bucket.ami_logs.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${local.aws_region}:*:*"
      }
    ]
  })
}

# Instance profile
resource "aws_iam_instance_profile" "ami" {
  name = "${local.project_name}-${local.environment}-ami-instance-profile"
  role = aws_iam_role.ami_instance_role.name

  tags = local.common_tags
}

# Component for nginx and security hardening
resource "aws_imagebuilder_component" "nginx_security" {
  depends_on = [
    aws_s3_object.install_nginx_script,
    aws_s3_object.sync_from_s3_script,
    aws_s3_object.generate_health_script
  ]
  
  name        = "${local.project_name}-${local.environment}-nginx-security"
  description = "Install nginx and apply security hardening"
  platform    = "Linux"
  version     = "1.0.9"  # Updated sync scripts and health monitoring

  data = yamlencode({
    name        = "nginx-security-hardening"
    description = "Install nginx with security hardening for HITL Platform"
    schemaVersion = "1.0"

    phases = [
      {
        name = "build"
        steps = [
          {
            name   = "InstallNginx"
            action = "ExecuteBash"
            inputs = {
              commands = [
                "yum update -y",
                "aws s3 cp s3://${aws_s3_bucket.frontend_assets.bucket}/scripts/install-nginx.sh /tmp/ --region ${local.aws_region}",
                "chmod +x /tmp/install-nginx.sh",
                "/tmp/install-nginx.sh",
                "echo 'Downloading and installing scripts from S3...'",
                "aws s3 cp s3://${aws_s3_bucket.frontend_assets.bucket}/scripts/sync-from-s3.sh /usr/local/bin/ --region ${local.aws_region}",
                "chmod +x /usr/local/bin/sync-from-s3.sh",
                "aws s3 cp s3://${aws_s3_bucket.frontend_assets.bucket}/scripts/generate-health.sh /usr/local/bin/ --region ${local.aws_region}",
                "chmod +x /usr/local/bin/generate-health.sh",
                "echo 'Running initial health generation...'",
                "/usr/local/bin/generate-health.sh"
              ]
            }
          }
        ]
      }
    ]
  })

  lifecycle {
    create_before_destroy = true
  }

  tags = local.common_tags
}

# Infrastructure configuration (VPC, subnets, etc.)
resource "aws_imagebuilder_infrastructure_configuration" "main" {
  name          = "${local.project_name}-${local.environment}-infrastructure"
  description   = "Infrastructure configuration for HITL golden AMI"
  instance_profile_name = aws_iam_instance_profile.ami.name
  instance_types = ["t3.small"]

  # Use public subnet for build (simpler networking)
  subnet_id = local.public_subnet_id

  # Security group for build instance
  security_group_ids = [aws_security_group.ami.id]

  # Enable logging
  logging {
    s3_logs {
      s3_bucket_name = aws_s3_bucket.ami_logs.bucket
      s3_key_prefix  = "ami-logs"
    }
  }

  # Terminate instance after build
  terminate_instance_on_failure = true

  tags = local.common_tags
}

# Security group for AMI build instances
resource "aws_security_group" "ami" {
  name_prefix = "${local.project_name}-${local.environment}-ami-"
  vpc_id      = local.vpc_id
  description = "Security group for AMI build instances"

  # Outbound for package downloads and AWS API calls
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-${local.environment}-ami-sg"
  })
}

# S3 bucket for frontend assets and scripts
resource "aws_s3_bucket" "frontend_assets" {
  bucket = "${local.project_name}-${local.environment}-frontend"
  
  tags = local.common_tags
  
  # Empty bucket before destruction
  provisioner "local-exec" {
    when    = destroy
    command = "aws s3 rm s3://${self.id} --recursive || true"
  }
}

resource "aws_s3_bucket_public_access_block" "frontend_assets" {
  bucket = aws_s3_bucket.frontend_assets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versioning disabled for simpler bucket deletion

# Lifecycle policy to automatically clean up old files
resource "aws_s3_bucket_lifecycle_configuration" "frontend_assets" {
  bucket = aws_s3_bucket.frontend_assets.id

  rule {
    id     = "delete_old_files"
    status = "Enabled"

    filter {
      prefix = ""  # Apply to all objects
    }

    expiration {
      days = 30  # Delete files after 30 days
    }
    
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend_assets" {
  bucket = aws_s3_bucket.frontend_assets.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Upload scripts to S3 for AMI build to use
resource "aws_s3_object" "install_nginx_script" {
  bucket = aws_s3_bucket.frontend_assets.bucket
  key    = "scripts/install-nginx.sh"
  source = "../../scripts/install-nginx.sh"
  etag   = filemd5("../../scripts/install-nginx.sh")

  tags = local.common_tags
}

resource "aws_s3_object" "sync_from_s3_script" {
  bucket = aws_s3_bucket.frontend_assets.bucket
  key    = "scripts/sync-from-s3.sh"
  source = "../../scripts/sync-from-s3.sh"
  etag   = filemd5("../../scripts/sync-from-s3.sh")

  tags = local.common_tags
}

resource "aws_s3_object" "generate_health_script" {
  bucket = aws_s3_bucket.frontend_assets.bucket
  key    = "scripts/generate-health.sh"
  source = "../../scripts/generate-health.sh"
  etag   = filemd5("../../scripts/generate-health.sh")

  tags = local.common_tags
}

# S3 bucket for AMI build logs
resource "aws_s3_bucket" "ami_logs" {
  bucket = "${local.project_name}-${local.environment}-ami-logs"
  
  tags = local.common_tags
  
  # Empty bucket before destruction
  provisioner "local-exec" {
    when    = destroy
    command = "aws s3 rm s3://${self.id} --recursive || true"
  }
}

resource "aws_s3_bucket_public_access_block" "ami_logs" {
  bucket = aws_s3_bucket.ami_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Image recipe
resource "aws_imagebuilder_image_recipe" "main" {
  name         = "${local.project_name}-${local.environment}-recipe"
  description  = "HITL Platform golden AMI recipe"
  parent_image = "arn:aws:imagebuilder:${local.aws_region}:aws:image/amazon-linux-2-x86/x.x.x"
  version      = "1.0.9"

  component {
    component_arn = aws_imagebuilder_component.nginx_security.arn
  }

  # Built-in security component
  component {
    component_arn = "arn:aws:imagebuilder:${local.aws_region}:aws:component/update-linux/x.x.x"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = local.common_tags
}

# Distribution configuration
resource "aws_imagebuilder_distribution_configuration" "main" {
  name        = "${local.project_name}-${local.environment}-distribution"
  description = "Distribution configuration for HITL golden AMI"

  distribution {
    ami_distribution_configuration {
      name        = "${local.project_name}-${local.environment}-nginx-{{ imagebuilder:buildDate }}"
      description = "HITL Platform nginx server with security hardening - {{ imagebuilder:buildDate }}"

      ami_tags = merge(local.common_tags, {
        Name        = "${local.project_name}-${local.environment}-nginx-{{ imagebuilder:buildDate }}"
        BuildDate   = "{{ imagebuilder:buildDate }}"
        Source      = "imagebuilder"
        Component   = "nginx"
      })
    }

    region = local.aws_region
  }

  tags = local.common_tags
}

# Image pipeline
resource "aws_imagebuilder_image_pipeline" "main" {
  name                             = "${local.project_name}-${local.environment}-pipeline"
  description                      = "HITL Platform golden AMI pipeline"
  image_recipe_arn                 = aws_imagebuilder_image_recipe.main.arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.main.arn
  distribution_configuration_arn   = aws_imagebuilder_distribution_configuration.main.arn

  # Build on schedule (weekly)
  schedule {
    schedule_expression                = "cron(0 6 ? * 1 *)"  # Every Monday at 6 AM UTC
    pipeline_execution_start_condition = "EXPRESSION_MATCH_AND_DEPENDENCY_UPDATES_AVAILABLE"
  }

  # Enable enhanced image metadata
  enhanced_image_metadata_enabled = true
  
  # Enable container recipe tests
  image_tests_configuration {
    image_tests_enabled = true
    timeout_minutes     = 60
  }

  tags = local.common_tags
}

# Automatically trigger the pipeline after infrastructure is ready and wait for completion
resource "null_resource" "trigger_ami_build" {
  depends_on = [
    aws_imagebuilder_image_pipeline.main,
    aws_imagebuilder_infrastructure_configuration.main,
    aws_imagebuilder_image_recipe.main,
    aws_imagebuilder_distribution_configuration.main
  ]
  
  provisioner "local-exec" {
    command = <<-EOF
      set -e
      echo "Starting AMI build pipeline..."
      BUILD_ARN=$(aws imagebuilder start-image-pipeline-execution --image-pipeline-arn ${aws_imagebuilder_image_pipeline.main.arn} --query 'imageBuildVersionArn' --output text)
      echo "Pipeline execution started with ARN: $BUILD_ARN"
      
      echo "Waiting for AMI build to complete..."
      while true; do
        STATUS=$(aws imagebuilder get-image --image-build-version-arn $BUILD_ARN --query 'image.state.status' --output text 2>/dev/null || echo "PENDING")
        echo "Current status: $STATUS"
        
        if [ "$STATUS" = "AVAILABLE" ]; then
          echo "AMI build completed successfully!"
          # Get the AMI ID and store it for cleanup
          AMI_ID=$(aws ec2 describe-images --owners self --filters "Name=name,Values=${local.project_name}-${local.environment}-nginx-*" --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' --output text)
          echo "Built AMI ID: $AMI_ID"
          echo "$AMI_ID" > /tmp/terraform_built_ami_id
          break
        elif [ "$STATUS" = "FAILED" ] || [ "$STATUS" = "CANCELLED" ]; then
          echo "AMI build failed with status: $STATUS"
          exit 1
        fi
        
        echo "Waiting 60 seconds before next check..."
        sleep 60
      done
    EOF
  }
  
  # Clean up AMI and snapshot on destroy
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOF
      if [ -f /tmp/terraform_built_ami_id ]; then
        AMI_ID=$(cat /tmp/terraform_built_ami_id)
        if [ -n "$AMI_ID" ] && [ "$AMI_ID" != "None" ]; then
          echo "Cleaning up AMI: $AMI_ID"
          # Get snapshot ID before deregistering
          SNAPSHOT_ID=$(aws ec2 describe-images --image-ids $AMI_ID --query 'Images[0].BlockDeviceMappings[0].Ebs.SnapshotId' --output text 2>/dev/null || echo "")
          # Deregister AMI
          aws ec2 deregister-image --image-id $AMI_ID || true
          # Delete snapshot if it exists
          if [ -n "$SNAPSHOT_ID" ] && [ "$SNAPSHOT_ID" != "None" ]; then
            echo "Cleaning up snapshot: $SNAPSHOT_ID"
            aws ec2 delete-snapshot --snapshot-id $SNAPSHOT_ID || true
          fi
          rm -f /tmp/terraform_built_ami_id
        fi
      fi
    EOF
    on_failure = continue
  }
  
  # Re-trigger if pipeline configuration changes
  triggers = {
    pipeline_arn     = aws_imagebuilder_image_pipeline.main.arn
    recipe_arn       = aws_imagebuilder_image_recipe.main.arn
    component_arn    = aws_imagebuilder_component.nginx_security.arn
    infra_config     = aws_imagebuilder_infrastructure_configuration.main.arn
    install_script   = aws_s3_object.install_nginx_script.etag
    sync_script      = aws_s3_object.sync_from_s3_script.etag
    health_script    = aws_s3_object.generate_health_script.etag
  }
}