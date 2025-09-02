# Use existing S3 VPC endpoint from VPC stack
data "aws_vpc_endpoint" "s3" {
  vpc_id       = local.vpc_id
  service_name = "com.amazonaws.${local.aws_region}.s3"
}

# Data source to get public route tables
data "aws_route_tables" "public" {
  vpc_id = local.vpc_id

  filter {
    name   = "tag:Name"
    values = ["*public*"]
  }
}

# Use existing SSM VPC endpoint from VPC stack
data "aws_vpc_endpoint" "ssm" {
  vpc_id       = local.vpc_id
  service_name = "com.amazonaws.${local.aws_region}.ssm"
}

# Use existing VPC endpoints security group from VPC stack
data "aws_security_group" "vpc_endpoints" {
  name   = "hitl-dev-vpc-endpoints"
  vpc_id = local.vpc_id
}
