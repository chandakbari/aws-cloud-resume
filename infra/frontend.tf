# ------------------------------------------------------------------
# FRONTEND: S3 bucket (stores the website files) + CloudFront (CDN)
# ------------------------------------------------------------------

# Private S3 bucket that holds index.html, style.css and script.js.
# bucket_prefix makes AWS add a random ending, because bucket names
# must be unique across the whole world.
resource "aws_s3_bucket" "website" {
  bucket_prefix = "${var.project_name}-site-"
  force_destroy = true # lets "terraform destroy" delete it even when it has files
}

# Security: block ALL public access. Visitors never touch S3 directly;
# they only reach the files through CloudFront.
resource "aws_s3_bucket_public_access_block" "website" {
  bucket                  = aws_s3_bucket.website.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Origin Access Control: the "ID card" CloudFront shows to S3.
resource "aws_cloudfront_origin_access_control" "website" {
  name                              = "${var.project_name}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "website" {
  enabled             = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100" # cheapest: Europe + North America edge locations
  comment             = "${var.project_name} website"

  origin {
    domain_name              = aws_s3_bucket.website.bucket_regional_domain_name
    origin_id                = "s3-website"
    origin_access_control_id = aws_cloudfront_origin_access_control.website.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-website"
    viewer_protocol_policy = "redirect-to-https" # always use HTTPS
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    # AWS managed policy "CachingOptimized"
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Free HTTPS certificate for the *.cloudfront.net address.
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# Bucket policy: allow ONLY this CloudFront distribution to read files.
data "aws_iam_policy_document" "website_bucket" {
  statement {
    sid       = "AllowCloudFrontRead"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.website.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.website.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "website" {
  bucket     = aws_s3_bucket.website.id
  policy     = data.aws_iam_policy_document.website_bucket.json
  depends_on = [aws_s3_bucket_public_access_block.website]
}

# config.js tells the website where the visitor-counter API lives.
# Terraform writes it because only Terraform knows the API address.
resource "aws_s3_object" "config" {
  bucket        = aws_s3_bucket.website.id
  key           = "config.js"
  content       = "window.API_URL = \"${aws_apigatewayv2_api.visits.api_endpoint}/visits\";\n"
  content_type  = "application/javascript"
  cache_control = "no-cache"
}
