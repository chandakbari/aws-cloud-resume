# Values Terraform prints at the end of "terraform apply".

output "website_url" {
  description = "Open this in your browser"
  value       = "https://${aws_cloudfront_distribution.website.domain_name}"
}

output "api_url" {
  description = "Visitor counter API"
  value       = "${aws_apigatewayv2_api.visits.api_endpoint}/visits"
}

output "s3_bucket" {
  description = "Copy into GitHub variable S3_BUCKET"
  value       = aws_s3_bucket.website.bucket
}

output "cloudfront_distribution_id" {
  description = "Copy into GitHub variable CLOUDFRONT_DISTRIBUTION_ID"
  value       = aws_cloudfront_distribution.website.id
}

output "github_role_arn" {
  description = "Copy into GitHub variable AWS_ROLE_ARN"
  value       = aws_iam_role.github_deploy.arn
}
