locals {
  # NLB routes traffic by listener port — port 80 → login-service, port 8080 → users-service.
  # API Gateway VPC Link connections use the NLB DNS name with explicit port for users routes.
  openapi_body = jsonencode({
    openapi = "3.0.1"
    info = {
      title   = "${local.prefix}-api"
      version = "v1"
    }
    components = {
      securitySchemes = {
        CognitoTokenAuthorizer = {
          type = "apiKey"
          name = "Authorization"
          in   = "header"
          "x-amazon-apigateway-authtype" = "custom"
          "x-amazon-apigateway-authorizer" = {
            type                         = "token"
            authorizerUri                = aws_lambda_function.token_authorizer.invoke_arn
            authorizerResultTtlInSeconds = 300
            identitySource               = "method.request.header.Authorization"
          }
        }
      }
    }
    paths = {
      "/auth/login" = {
        post = {
          operationId = "loginUser"
          security    = []
          responses   = { "200" = { description = "Successful login" } }
          "x-amazon-apigateway-integration" = {
            type           = "HTTP_PROXY"
            httpMethod     = "POST"
            uri            = "http://${aws_lb.nlb.dns_name}/auth/login"
            connectionType = "VPC_LINK"
            connectionId   = aws_api_gateway_vpc_link.vpc_link.id
          }
        }
      }
      "/auth/refresh" = {
        post = {
          operationId = "refreshToken"
          security    = []
          responses   = { "200" = { description = "Tokens refreshed" } }
          "x-amazon-apigateway-integration" = {
            type           = "HTTP_PROXY"
            httpMethod     = "POST"
            uri            = "http://${aws_lb.nlb.dns_name}/auth/refresh"
            connectionType = "VPC_LINK"
            connectionId   = aws_api_gateway_vpc_link.vpc_link.id
          }
        }
      }
      "/auth/logout" = {
        post = {
          operationId = "logoutUser"
          security    = []
          responses   = { "204" = { description = "Logged out" } }
          "x-amazon-apigateway-integration" = {
            type           = "HTTP_PROXY"
            httpMethod     = "POST"
            uri            = "http://${aws_lb.nlb.dns_name}/auth/logout"
            connectionType = "VPC_LINK"
            connectionId   = aws_api_gateway_vpc_link.vpc_link.id
          }
        }
      }
      "/users" = {
        get = {
          operationId = "listUsers"
          security    = [{ CognitoTokenAuthorizer = [] }]
          parameters = [
            { name = "limit", in = "query", required = false, schema = { type = "integer" } },
            { name = "next_token", in = "query", required = false, schema = { type = "string" } }
          ]
          responses = { "200" = { description = "List of users" } }
          "x-amazon-apigateway-integration" = {
            type           = "HTTP_PROXY"
            httpMethod     = "GET"
            uri            = "http://${aws_lb.nlb.dns_name}:8080/users"
            connectionType = "VPC_LINK"
            connectionId   = aws_api_gateway_vpc_link.vpc_link.id
          }
        }
        post = {
          operationId = "createUser"
          security    = [{ CognitoTokenAuthorizer = [] }]
          responses   = { "201" = { description = "User created" } }
          "x-amazon-apigateway-integration" = {
            type           = "HTTP_PROXY"
            httpMethod     = "POST"
            uri            = "http://${aws_lb.nlb.dns_name}:8080/users"
            connectionType = "VPC_LINK"
            connectionId   = aws_api_gateway_vpc_link.vpc_link.id
          }
        }
      }
      "/users/{user_id}" = {
        get = {
          operationId = "getUser"
          security    = [{ CognitoTokenAuthorizer = [] }]
          parameters  = [{ name = "user_id", in = "path", required = true, schema = { type = "string" } }]
          responses   = { "200" = { description = "User found" } }
          "x-amazon-apigateway-integration" = {
            type           = "HTTP_PROXY"
            httpMethod     = "GET"
            uri            = "http://${aws_lb.nlb.dns_name}:8080/users/{user_id}"
            connectionType = "VPC_LINK"
            connectionId   = aws_api_gateway_vpc_link.vpc_link.id
          }
        }
        put = {
          operationId = "updateUser"
          security    = [{ CognitoTokenAuthorizer = [] }]
          parameters  = [{ name = "user_id", in = "path", required = true, schema = { type = "string" } }]
          responses   = { "200" = { description = "User updated" } }
          "x-amazon-apigateway-integration" = {
            type           = "HTTP_PROXY"
            httpMethod     = "PUT"
            uri            = "http://${aws_lb.nlb.dns_name}:8080/users/{user_id}"
            connectionType = "VPC_LINK"
            connectionId   = aws_api_gateway_vpc_link.vpc_link.id
          }
        }
        delete = {
          operationId = "deleteUser"
          security    = [{ CognitoTokenAuthorizer = [] }]
          parameters  = [{ name = "user_id", in = "path", required = true, schema = { type = "string" } }]
          responses   = { "204" = { description = "User deleted" } }
          "x-amazon-apigateway-integration" = {
            type           = "HTTP_PROXY"
            httpMethod     = "DELETE"
            uri            = "http://${aws_lb.nlb.dns_name}:8080/users/{user_id}"
            connectionType = "VPC_LINK"
            connectionId   = aws_api_gateway_vpc_link.vpc_link.id
          }
        }
      }
    }
  })
}

resource "aws_api_gateway_rest_api" "api" {
  name = "${local.prefix}-api"
  body = local.openapi_body

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name    = "${local.prefix}-api"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_api_gateway_deployment" "v1" {
  rest_api_id = aws_api_gateway_rest_api.api.id

  triggers = {
    redeployment = sha256(local.openapi_body)
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "v1" {
  deployment_id = aws_api_gateway_deployment.v1.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "v1"

  tags = {
    Name    = "${local.prefix}-api-v1"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_lambda_permission" "apigw_authorizer" {
  statement_id  = "AllowAPIGatewayInvokeAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.token_authorizer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

output "api_gateway_invoke_url" {
  description = "API Gateway invoke URL (base URL for all endpoints)"
  value       = aws_api_gateway_stage.v1.invoke_url
}

output "api_gateway_rest_api_id" {
  description = "API Gateway REST API ID"
  value       = aws_api_gateway_rest_api.api.id
}
