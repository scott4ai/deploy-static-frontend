# Upload helper scripts to S3 for EC2 instances to download

# Upload React app build files to S3 bucket created by AMI stack
resource "aws_s3_object" "react_app" {
  for_each = fileset("${path.module}/../../demo-app/build", "**/*")
  
  bucket = data.aws_s3_bucket.frontend_assets.id
  key    = each.value
  source = "${path.module}/../../demo-app/build/${each.value}"
  etag   = filemd5("${path.module}/../../demo-app/build/${each.value}")
  
  content_type = lookup({
    "html" = "text/html",
    "css"  = "text/css",
    "js"   = "application/javascript",
    "json" = "application/json",
    "png"  = "image/png",
    "jpg"  = "image/jpeg",
    "jpeg" = "image/jpeg",
    "gif"  = "image/gif",
    "svg"  = "image/svg+xml",
    "ico"  = "image/x-icon"
  }, split(".", each.value)[length(split(".", each.value)) - 1], "application/octet-stream")
  
  tags = local.common_tags
}

# Note: sync-from-s3.sh and health-check.sh scripts are now uploaded by AMI stack