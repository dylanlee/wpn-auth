variable "aws_region" {
  description = "The AWS region to deploy resources into"
  type        = string
  default     = "us-east-1"
}

variable "aws_account_id" {
  description = "The AWS account ID"
  type        = string
  default     = ""
}

provider "aws" {
  region = "us-east-1" # replace with your preferred AWS region
}

# Lambda Functions
resource "aws_lambda_function" "token_generator_function" {
  function_name = "TokenGeneratorFunction"
  s3_bucket     = "wpnauthconfig"
  s3_key        = "authlambda.zip"
  handler       = "index.handler"
  role          = aws_iam_role.lambda_execution_role.arn
  runtime       = "nodejs20.x"
}

resource "aws_lambda_function" "token_validator_function" {
  function_name = "TokenValidatorFunction"
  s3_bucket     = "wpnauthconfig"
  s3_key        = "accesslambda.zip"
  handler       = "index.handler"
  role          = aws_iam_role.lambda_execution_role.arn
  runtime       = "nodejs20.x"
  publish       = true 
}

# need to be able to reference the published version ARN of token_validator so can run on lambda@edge
data "aws_lambda_function" "token_validator_function_published" {
  function_name = aws_lambda_function.token_validator_function.function_name
  qualifier     = aws_lambda_function.token_validator_function.version # Use the latest published version
}

# IAM Role and Policy for Lambda
resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda_execution_role"

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
  name   = "LambdaExecutionPolicy"
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

# Method response for POST
resource "aws_api_gateway_method_response" "post_method_response" {
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
      restriction_type = "none"
    }
  }
}

resource "aws_s3_bucket" "private_s3_bucket" {
  bucket = "wpn-exp-cat"
  acl    = "private"

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
      }
    ]
  })
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
    read_capacity      = 10 # Not necessary for PAY_PER_REQUEST billing mode, but included for completeness
    write_capacity     = 10 # Not necessary for PAY_PER_REQUEST billing mode, but included for completeness
  }

  global_secondary_index {
    name            = "GenerationDateIndex"
    hash_key        = "generationDate"
    projection_type = "ALL"
    read_capacity   = 10 # Not necessary for PAY_PER_REQUEST billing mode, but included for completeness
    write_capacity  = 10 # Not necessary for PAY_PER_REQUEST billing mode, but included for completeness
  }
}

# Outputs
output "api_url" {
  value = "${aws_api_gateway_deployment.api_deployment.invoke_url}"
}
