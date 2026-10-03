locals {
  authorizer_src      = "${path.root}/../../src/authorizer"
  authorizer_build    = "/tmp/anycompany-authorizer-build-${var.env}"
  authorizer_zip_path = "/tmp/anycompany-authorizer-${var.env}.zip"
}

# Install dependencies into a staging dir, then zip
resource "null_resource" "authorizer_build" {
  triggers = {
    src_hash = sha256(join("", [
      filesha256("${local.authorizer_src}/lambda_authorizer.py"),
      filesha256("${local.authorizer_src}/requirements.txt"),
    ]))
  }

  provisioner "local-exec" {
    command = <<-EOT
      rm -rf "${local.authorizer_build}"
      mkdir -p "${local.authorizer_build}"
      pip install -q -r "${local.authorizer_src}/requirements.txt" \
        -t "${local.authorizer_build}"
      cp "${local.authorizer_src}/lambda_authorizer.py" "${local.authorizer_build}/"
      cd "${local.authorizer_build}" && zip -q -r "${local.authorizer_zip_path}" .
    EOT
  }
}

data "local_file" "authorizer_zip" {
  filename   = local.authorizer_zip_path
  depends_on = [null_resource.authorizer_build]
}

resource "aws_iam_role" "lambda_authorizer" {
  name = "${local.prefix}-authorizer-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = {
    Name    = "${local.prefix}-authorizer-role"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_iam_role_policy_attachment" "lambda_authorizer_basic" {
  role       = aws_iam_role.lambda_authorizer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "token_authorizer" {
  function_name = "${local.prefix}-token-authorizer"
  role          = aws_iam_role.lambda_authorizer.arn
  runtime       = "python3.10"
  handler       = "lambda_authorizer.handler"

  filename         = local.authorizer_zip_path
  source_code_hash = data.local_file.authorizer_zip.content_base64sha256

  environment {
    variables = {
      COGNITO_JWKS_URL = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.main.id}/.well-known/jwks.json"
    }
  }

  depends_on = [null_resource.authorizer_build]

  tags = {
    Name    = "${local.prefix}-token-authorizer"
    Project = "anycompany-users"
    Env     = var.env
  }
}

output "authorizer_invoke_arn" {
  description = "Lambda authorizer invoke ARN — referenced by api-gateway.tf"
  value       = aws_lambda_function.token_authorizer.invoke_arn
}

output "authorizer_function_name" {
  description = "Lambda authorizer function name"
  value       = aws_lambda_function.token_authorizer.function_name
}
