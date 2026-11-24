# ------------------------------------------------------------------
# BACKEND: DynamoDB (database) + Lambda (Python code) + API Gateway
# ------------------------------------------------------------------

# DynamoDB table that stores the visitor count.
# PAY_PER_REQUEST = you pay only per read/write, nothing when idle.
resource "aws_dynamodb_table" "visits" {
  name         = "${var.project_name}-visits"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

# --- IAM role: the permissions the Lambda function runs with ---

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.project_name}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# Allow Lambda to write logs to CloudWatch (for debugging).
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Least privilege: Lambda may ONLY update items in THIS one table.
data "aws_iam_policy_document" "lambda_dynamodb" {
  statement {
    actions   = ["dynamodb:UpdateItem"]
    resources = [aws_dynamodb_table.visits.arn]
  }
}

resource "aws_iam_role_policy" "lambda_dynamodb" {
  name   = "dynamodb-update-visits"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_dynamodb.json
}

# --- Lambda function ---

# Zip the Python file, because Lambda receives code as a .zip.
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/../backend/lambda/visitor_counter.py"
  output_path = "${path.module}/build/visitor_counter.zip"
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.project_name}-visitor-counter"
  retention_in_days = 14 # delete old logs automatically to save money
}

resource "aws_lambda_function" "visitor_counter" {
  function_name    = "${var.project_name}-visitor-counter"
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  handler          = "visitor_counter.lambda_handler"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 10  # first ("cold") start loads the AWS SDK, which can take a few seconds
  memory_size      = 256 # more memory also gives Lambda more CPU, so cold starts are faster

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.visits.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda]
}

# --- API Gateway (HTTP API): gives the Lambda a public web address ---

resource "aws_apigatewayv2_api" "visits" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"

  # CORS: only YOUR website is allowed to call this API from a browser.
  cors_configuration {
    allow_origins = ["https://${aws_cloudfront_distribution.website.domain_name}"]
    allow_methods = ["GET"]
    max_age       = 300
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.visits.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.visitor_counter.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_visits" {
  api_id    = aws_apigatewayv2_api.visits.id
  route_key = "GET /visits"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.visits.id
  name        = "$default"
  auto_deploy = true

  # Rate limiting protects you from surprise bills if someone spams the API.
  default_route_settings {
    throttling_burst_limit = 20
    throttling_rate_limit  = 10
  }
}

# Give API Gateway permission to run the Lambda function.
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.visitor_counter.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.visits.execution_arn}/*/*"
}
