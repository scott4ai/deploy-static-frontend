# Route 53 A record for the domain pointing to the ALB
resource "aws_route53_record" "main" {
  count   = var.create_route53_records && var.domain_name != "" ? 1 : 0
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

# Output the domain URL for easy access
output "domain_url" {
  value       = var.domain_name != "" ? "https://${var.domain_name}" : null
  description = "The HTTPS URL of the application (if domain configured)"
}