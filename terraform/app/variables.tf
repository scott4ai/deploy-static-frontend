variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, stage, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "hitl-tf"
}

# VPC Configuration - now sourced from VPC remote state in main.tf locals

# EC2 Configuration
variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"
}

variable "min_size" {
  description = "Minimum number of EC2 instances"
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Maximum number of EC2 instances" 
  type        = number
  default     = 4
}

variable "desired_capacity" {
  description = "Desired number of EC2 instances"
  type        = number
  default     = 2
}

variable "custom_ami_id" {
  description = "Custom AMI ID (golden AMI)"
  type        = string
  default     = ""
}

# Application Configuration
variable "domain_name" {
  description = "Domain name for SSL certificate (leave empty to skip HTTPS)"
  type        = string
  default     = "hitl-tf.emg1.com"
}

variable "ssl_certificate_arn" {
  description = "SSL certificate ARN (optional, will create if not provided)"
  type        = string
  default     = ""
}

variable "create_route53_records" {
  description = "Whether to create Route53 records"
  type        = bool
  default     = true
}

variable "route53_zone_id" {
  description = "Route 53 hosted zone ID for the domain"
  type        = string
  default     = "Z06144693848E68QIDQLM"
}

# Lambda Configuration
variable "lambda_zip_path" {
  description = "Path to Lambda deployment zip file"
  type        = string
  default     = "../../lambda-backend/deployment.zip"
}

variable "lambda_handler" {
  description = "Lambda function handler"
  type        = string
  default     = "index.handler"
}

variable "lambda_runtime" {
  description = "Lambda runtime"
  type        = string
  default     = "nodejs22.x"
}

variable "lambda_timeout" {
  description = "Lambda timeout in seconds"
  type        = number
  default     = 30
}

variable "lambda_memory" {
  description = "Lambda memory in MB"
  type        = number
  default     = 128
}

# Cognito Configuration (for Lambda authentication)
variable "cognito_user_pool_id" {
  description = "Cognito User Pool ID for Lambda authentication"
  type        = string
  default     = ""
}

variable "cognito_user_pool_client_id" {
  description = "Cognito User Pool Client ID for Lambda authentication"
  type        = string
  default     = ""
}

# WAF Configuration
variable "enable_waf" {
  description = "Whether to enable WAF protection"
  type        = bool
  default     = true
}

variable "waf_rate_limit" {
  description = "WAF rate limit per 5-minute period"
  type        = number
  default     = 2000
}


# Monitoring Configuration
variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

# Common tags
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}