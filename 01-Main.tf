#1 generates random alphanumeric values thst can be added to expressions/names to maintain uniqueness/limit redundancy
resource "random_string" "random" {
  length  = 6
  special = false
  upper   = false
}

#2 S3 bucket
resource "aws_s3_bucket" "bucket" {
  bucket        = "psychoticbumpschool${random_string.random.result}"
  force_destroy = true
}

#3 Object ownership controls are owner enforced
resource "aws_s3_bucket_ownership_controls" "S3controls" {
  bucket = aws_s3_bucket.bucket.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

#4 public access is blocked on all fronts
resource "aws_s3_bucket_public_access_block" "pabs" {
  bucket = aws_s3_bucket.bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Bucket Versioning is disabled
resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.bucket.id
  versioning_configuration {
    status = "Disabled"
  }
}

variable "objects" {
  type = map(string)
}

# 6 bucket objects
resource "aws_s3_object" "ninjafile" {
  for_each     = var.objects
  bucket       = aws_s3_bucket.bucket.id
  key          = each.key
  source       = "./Content/${each.key}"
  content_type = each.value
  #etag         = filemd5(each.value)
  #acl = "private"
}

# 7 Encryption type
resource "aws_s3_bucket_server_side_encryption_configuration" "bucket_encryption" {
  bucket = aws_s3_bucket.bucket.id

  rule {
    bucket_key_enabled = true
  }
}

# 8 Policy from CloudFront Data block
data "aws_iam_policy_document" "s3_policy_data" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.bucket.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["${aws_cloudfront_distribution.s3_distribution.arn}"]
    }
  }
}

# 9 Policy from CloudFront Resource block
resource "aws_s3_bucket_policy" "s3_policy" {
  bucket = aws_s3_bucket.bucket.id
  policy = data.aws_iam_policy_document.s3_policy_data.json
}

# Holds values that are repeated throughout the code
locals {
  s3_origin_id   = "${random_string.random.result}-origin"
  hosted_zone_id = "Z091687013GGJBC7OUC98"
  my_domain      = "ninjasdelacloud.com"
  acm_arn        = "arn:aws:acm:us-east-1:107881574243:certificate/a8336b75-dee8-45d1-950a-919f66821abd"
}

#Origin access
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = aws_s3_bucket.bucket.bucket_regional_domain_name
  description                       = "${random_string.random.result}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name              = aws_s3_bucket.bucket.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
    origin_id                = local.s3_origin_id
  }

  enabled             = true
  is_ipv6_enabled     = false
  comment             = "S3 bucket distribution"
  default_root_object = "index.html"

  aliases = ["ninjasdelacloud.com"]

  default_cache_behavior {
    compress               = true
    viewer_protocol_policy = "allow-all"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    target_origin_id = local.s3_origin_id
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  price_class = "PriceClass_100"

  tags = {
    Environment = "development"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    acm_certificate_arn            = local.acm_arn
    ssl_support_method             = "sni-only"
    minimum_protocol_version       = "TLSv1.2_2021"
  }
}
resource "aws_route53_record" "www" {
  zone_id = local.hosted_zone_id
  name    = local.my_domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
    evaluate_target_health = true
  }
}

output "cloudfront_endpoint" {
  value = "https://${aws_route53_record.www.name}"
}
