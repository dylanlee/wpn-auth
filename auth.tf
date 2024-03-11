terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

# uncomment backend for CIROH deployment
#  backend "s3" {
#    bucket = "ciroh-tf-backend"
#    key    = "ciroh-fim/wpn-auth"
#    region = "us-east-1"
#  }
}

provider "aws" {
  region = var.aws_region
}

# Lambda Functions
resource "aws_lambda_function" "token_generator_function" {
  function_name = "TokenGeneratorFunction"
  s3_bucket     = "wpnauthconfig"
  s3_key        = "authlambda.zip"
  handler       = "index.handler"
  role          = aws_iam_role.lambda_execution_role.arn
  runtime       = "nodejs20.x"
  tags = {
      Name = "${var.name_tag} Lambda"
      Project = var.project_tag
    }
}

resource "aws_lambda_function" "token_validator_function" {
  function_name = "TokenValidatorFunction"
  s3_bucket     = "wpnauthconfig"
  s3_key        = "accesslambda.zip"
  handler       = "index.handler"
  role          = aws_iam_role.lambda_execution_role.arn
  runtime       = "nodejs20.x"
  publish       = true
  tags = {
      Name = "${var.name_tag} Lambda"
      Project = var.project_tag
    }
}

# need to be able to reference the published version ARN of token_validator so can run on lambda@edge
data "aws_lambda_function" "token_validator_function_published" {
  function_name = aws_lambda_function.token_validator_function.function_name
  qualifier     = aws_lambda_function.token_validator_function.version # Use the latest published version
}

# IAM Role and Policy for Lambda
resource "aws_iam_role" "lambda_execution_role" {
  name = "wpn_lambda_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = ["lambda.amazonaws.com", "edgelambda.amazonaws.com"]
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_execution_policy" {
  name   = "Wpn_LambdaExecutionPolicy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:*",
          "dynamodb:*",
          "s3:GetObject",
          "ses:SendEmail",
          "ses:SendRawEmail"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_execution_policy.arn
}

# Lambda Permissions
resource "aws_lambda_permission" "token_generator_function_invoke_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.token_generator_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.aws_region}:${var.aws_account_id}:${aws_api_gateway_rest_api.api_gateway.id}/*/POST/"
}
# API Gateway
resource "aws_api_gateway_rest_api" "api_gateway" {
  name = "TokenBasedAuthAPI"
  tags = {
      Name = "${var.name_tag} API"
      Project = var.project_tag
    }
}

# POST method at root
resource "aws_api_gateway_method" "root_post_method" {
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  resource_id   = aws_api_gateway_rest_api.api_gateway.root_resource_id
  http_method   = "POST"
  authorization = "NONE"
}

# Integration for POST method at root
resource "aws_api_gateway_integration" "root_post_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api_gateway.id
  resource_id             = aws_api_gateway_rest_api.api_gateway.root_resource_id
  http_method             = aws_api_gateway_method.root_post_method.http_method
  type                    = "AWS_PROXY"
  integration_http_method = "POST"  # This is for the backend integration, typically "POST" for AWS_PROXY type
  uri                     = aws_lambda_function.token_generator_function.invoke_arn
}

# Method response for POST 200 status response
resource "aws_api_gateway_method_response" "post_method_response_200" {
  depends_on = [aws_api_gateway_method.root_post_method]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_rest_api.api_gateway.root_resource_id
  http_method = "POST"
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
  }

  response_models = {
    "application/json" = "Empty"
  }
}

# Integration response for POST 200 status response
resource "aws_api_gateway_integration_response" "post_integration_response_200" {
  depends_on  = [aws_api_gateway_integration.root_post_integration]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_rest_api.api_gateway.root_resource_id
  http_method = aws_api_gateway_method.root_post_method.http_method
  status_code = "200" # The status code returned from your Lambda function

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
    "method.response.header.Access-Control-Allow-Methods" = "'OPTIONS,POST'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
  }

  response_templates = {
    "application/json" = "$input.path('$')"
  }
}

# Method response for POST 400 status response
resource "aws_api_gateway_method_response" "post_method_response_400" {
  depends_on = [aws_api_gateway_method.root_post_method]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_rest_api.api_gateway.root_resource_id
  http_method = "POST"
  status_code = "400"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
  }

  response_models = {
    "application/json" = "Empty"
  }
}

# Integration response for POST 400 status response
resource "aws_api_gateway_integration_response" "post_integration_response_400" {
  depends_on  = [aws_api_gateway_integration.root_post_integration]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_rest_api.api_gateway.root_resource_id
  http_method = aws_api_gateway_method.root_post_method.http_method
  status_code = "400" # The status code returned from your Lambda function

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
    "method.response.header.Access-Control-Allow-Methods" = "'OPTIONS,POST'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
  }

  response_templates = {
    "application/json" = "$input.path('$')"
  }
}

# OPTIONS method at root
resource "aws_api_gateway_method" "root_options_method" {
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  resource_id   = aws_api_gateway_rest_api.api_gateway.root_resource_id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# Integration for OPTIONS method at root
resource "aws_api_gateway_integration" "root_options_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api_gateway.id
  resource_id             = aws_api_gateway_rest_api.api_gateway.root_resource_id
  http_method             = aws_api_gateway_method.root_options_method.http_method
  type                    = "MOCK"
  request_templates       = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

# Integration response for OPTIONS method with CORS headers
resource "aws_api_gateway_integration_response" "options_integration_response" {
  depends_on = [aws_api_gateway_integration.root_options_integration]
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_rest_api.api_gateway.root_resource_id
  http_method = aws_api_gateway_method.root_options_method.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
    "method.response.header.Access-Control-Allow-Methods" = "'OPTIONS,GET,PUT,POST,DELETE,PATCH'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
  }

  response_templates = {
    "application/json" = ""
  }
}

# Deployment of the API
resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on = [
    aws_api_gateway_integration.root_post_integration,
    aws_api_gateway_integration.root_options_integration,
  ]

  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  stage_name  = "prod"

  # Redeploy API when changes are applied
  triggers = {
    redeployment = sha1(join(",", tolist([
      jsonencode(aws_api_gateway_rest_api.api_gateway),
      jsonencode(aws_api_gateway_method.root_post_method),
      jsonencode(aws_api_gateway_integration.root_post_integration),
      jsonencode(aws_api_gateway_method.root_options_method),
      jsonencode(aws_api_gateway_integration.root_options_integration),
    ])))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "api_prod_stage" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api_gateway.id
  stage_name    = "prod"
}

# Method response for OPTIONS
resource "aws_api_gateway_method_response" "root_options_method_response" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway.id
  resource_id = aws_api_gateway_method.root_options_method.resource_id
  http_method = aws_api_gateway_method.root_options_method.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_wafv2_web_acl" "auth-api-gateway-acl" {
  name        = "auth-api-gateway-acl"
  scope       = "REGIONAL" 
  description = "ACL for API Gateway and CloudFront"
  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "auth-api-gateway-acl"
    sampled_requests_enabled   = true
  }

  # Geo match rule for allowed countries
  rule {
    name     = "GeoMatchRule"
    priority = 1

    action {
      allow {}
    }

    statement {
      geo_match_statement {
        country_codes = [
        "US", # United States
        "CA", # Canada
        "GB", # United Kingdom
	"AT", # Austria
	"BE", # Belgium
	"BG", # Bulgaria
	"HR", # Croatia
	"CY", # Cyprus
	"CZ", # Czech Republic
	"DK", # Denmark
	"EE", # Estonia
	"FI", # Finland
	"FR", # France
	"DE", # Germany
	"GR", # Greece
	"HU", # Hungary
	"IE", # Ireland
	"IT", # Italy
	"LV", # Latvia
	"LT", # Lithuania
	"LU", # Luxembourg
	"MT", # Malta
	"NL", # Netherlands
	"PL", # Poland
	"PT", # Portugal
	"RO", # Romania
	"SK", # Slovakia
	"SI", # Slovenia
	"ES", # Spain
	"SE", # Sweden
        ]
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "GeoMatchRule"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "RateLimit5Minute"
    priority = 2 # Ensure this does not conflict with other rule priorities
    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 10 
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimit5Minute"
      sampled_requests_enabled   = true
    }
  }
  tags = {
      Name = "${var.name_tag} WAF"
      Project = var.project_tag
    }
}

resource "aws_wafv2_web_acl_association" "api_gateway_association" {
  resource_arn = aws_api_gateway_stage.api_prod_stage.arn 
  web_acl_arn  = aws_wafv2_web_acl.auth-api-gateway-acl.arn
}

resource "aws_cloudfront_distribution" "cloudfront_distribution" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront distribution for S3 bucket with Lambda@Edge for authentication"
  default_root_object = "index.html"

  origin {
    domain_name = aws_s3_bucket.private_s3_bucket.bucket_regional_domain_name
    origin_id   = "S3Origin"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.my_cloudfront_oai.cloudfront_access_identity_path
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3Origin"

    forwarded_values {
      query_string = false
      headers      = ["Origin", "Authorization", "Access-Control-Request-Method", "Access-Control-Request-Headers"]

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400

    lambda_function_association {
      event_type = "viewer-request"
      lambda_arn = data.aws_lambda_function.token_validator_function_published.qualified_arn
    } 
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations = [
        "US", # United States
        "CA", # Canada
        "GB", # United Kingdom
	"AT", # Austria
	"BE", # Belgium
	"BG", # Bulgaria
	"HR", # Croatia
	"CY", # Cyprus
	"CZ", # Czech Republic
	"DK", # Denmark
	"EE", # Estonia
	"FI", # Finland
	"FR", # France
	"DE", # Germany
	"GR", # Greece
	"HU", # Hungary
	"IE", # Ireland
	"IT", # Italy
	"LV", # Latvia
	"LT", # Lithuania
	"LU", # Luxembourg
	"MT", # Malta
	"NL", # Netherlands
	"PL", # Poland
	"PT", # Portugal
	"RO", # Romania
	"SK", # Slovakia
	"SI", # Slovenia
	"ES", # Spain
	"SE", # Sweden
      ]
    }
  }

  tags = {
      Name = "${var.name_tag} CloudFront"
      Project = var.project_tag
    }
}

resource "aws_wafv2_web_acl" "cloudfront_acl" {
  name        = "cloudfront-acl"
  scope       = "CLOUDFRONT"
  description = "WAF ACL for CloudFront distribution"

  # Rate-Based Rule for Limiting Requests
  rule {
    name     = "RateLimit"
    priority = 200
    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 5000 
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimit"
      sampled_requests_enabled   = true
    }
  }

  tags = {
      Name = "${var.name_tag} WAF"
      Project = var.project_tag
    }
}

resource "aws_wafv2_web_acl_association" "cloudfront_acl_association" {
  resource_arn = aws_cloudfront_distribution.cloudfront_distribution.arn
  web_acl_arn  = aws_wafv2_web_acl.cloudfront_acl.arn
}

resource "aws_s3_bucket" "private_s3_bucket" {
  bucket = var.exp_bucket_name
  versioning {
    enabled = true
  }
  tags = {
      Name = "${var.name_tag} S3"
      Project = var.project_tag
    }
}

resource "aws_s3_bucket_ownership_controls" "s3_bucket_acl_ownership" {
  bucket = aws_s3_bucket.private_s3_bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "private_acl" {
  depends_on = [aws_s3_bucket_ownership_controls.s3_bucket_acl_ownership]
  bucket = aws_s3_bucket.private_s3_bucket.id
  acl    = "private"
}

resource "aws_s3_bucket_cors_configuration" "private_s3_bucket_cors" {
  bucket = aws_s3_bucket.private_s3_bucket.id

  cors_rule {
    allowed_origins = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_headers = ["*"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_policy" "my_s3_bucket_policy" {
  bucket = aws_s3_bucket.private_s3_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = {
          AWS = "arn:aws:iam::cloudfront:user/CloudFront Origin Access Identity ${aws_cloudfront_origin_access_identity.my_cloudfront_oai.id}"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.private_s3_bucket.arn}/*"
      },
      {
        Effect = "Allow"
        Principal = { AWS = "arn:aws:iam::474288090892:user/shawn.carter@noaa.gov" }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.private_s3_bucket.arn}/*"
      }
    ]
  })
}

# add some backups/accidental deletion protection 
resource "aws_s3_bucket_lifecycle_configuration" "example" {
  bucket = aws_s3_bucket.private_s3_bucket.id

  rule {
    id     = "transition-old-versions"
    status = "Enabled"

    noncurrent_version_transition {
      days          = 5 
      storage_class = "GLACIER"
    }

    noncurrent_version_expiration {
      days = 30
    }
  }
}

# CloudFront Origin Access Identity needed for the S3 bucket policy
resource "aws_cloudfront_origin_access_identity" "my_cloudfront_oai" {
  comment = "Origin Access Identity for S3 bucket"
}

resource "aws_dynamodb_table" "token_table" {
  name         = "TokenStorage"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "token"

  attribute {
    name = "email"
    type = "S"
  }

  attribute {
    name = "token"
    type = "S"
  }

  attribute {
    name = "generationDate"
    type = "S"
  }

  global_secondary_index {
    name               = "EmailIndex"
    hash_key           = "email"
    range_key          = "generationDate"
    projection_type    = "ALL"
  }

  global_secondary_index {
    name            = "GenerationDateIndex"
    hash_key        = "generationDate"
    projection_type = "ALL"
  }

  tags = {
      Name = "${var.name_tag} DynamoDB"
      Project = var.project_tag
    }
}

# Outputs
output "api_url" {
  value = "${aws_api_gateway_deployment.api_deployment.invoke_url}"
}
