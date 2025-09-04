output "image_pipeline_arn" {
  description = "ARN of the AMI build pipeline"
  value       = aws_imagebuilder_image_pipeline.main.arn
}

output "image_recipe_arn" {
  description = "ARN of the AMI build recipe"
  value       = aws_imagebuilder_image_recipe.main.arn
}

output "component_arn" {
  description = "ARN of the nginx security component"
  value       = aws_imagebuilder_component.nginx_security.arn
}

output "latest_ami_command" {
  description = "AWS CLI command to get the latest AMI ID"
  value = "aws ec2 describe-images --owners self --filters 'Name=name,Values=${local.project_name}-${local.environment}-nginx-*' --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' --output text"
}

output "ami_build_status_command" {
  description = "AWS CLI command to check AMI build status"
  value = "aws imagebuilder list-images --filter name=${local.project_name}-${local.environment}-recipe --query 'imageList[0].state.status' --output text"
}

output "build_triggered" {
  description = "Indicates that AMI build has been automatically triggered"
  value = "AMI build automatically started via AMI build pipeline"
  depends_on = [null_resource.trigger_ami_build]
}

# AMI ID is now provided directly from the build process via built_ami_id output

data "external" "ami_id" {
  program = ["bash", "-c", "cat /tmp/terraform_built_ami_id | jq -Rs '{id: .}'"]
  depends_on = [null_resource.trigger_ami_build]
}

output "built_ami_id" {
  description = "AMI ID built by this terraform deployment"
  value = trimspace(data.external.ami_id.result.id)
}

output "frontend_assets_bucket" {
  description = "S3 bucket name for frontend assets"
  value       = aws_s3_bucket.frontend_assets.bucket
}

output "frontend_assets_bucket_arn" {
  description = "S3 bucket ARN for frontend assets"
  value       = aws_s3_bucket.frontend_assets.arn
}