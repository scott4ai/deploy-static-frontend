# Variables are now dynamically fetched from VPC stack via data.terraform_remote_state.vpc
# This removes hardcoding and makes the infrastructure fully dynamic

# Optional overrides - these use data sources by default
variable "aws_region" {
  description = "AWS region for resources (auto-detected from VPC stack)"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment name (auto-detected from VPC stack)"
  type        = string
  default     = ""
}

variable "project_name" {
  description = "Project name for resource naming (auto-detected from VPC stack)"
  type        = string
  default     = ""
}