locals {
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
            type             = "HTTP_PROXY"
            httpMethod       = "POST"
            uri              = "http://${aws_lb.alb.dns_name}/auth/login"
            connectionType   = "VPC_LINK"
            connectionId     = aws_apigatewayv2_vpc_link.vpc_link.id
            integrationTarget = aws_lb.alb.arn
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
            uri            = "http://${aws_lb.alb.dns_name}/auth/refresh"
            connectionType    = "VPC_LINK"
            connectionId      = aws_apigatewayv2_vpc_link.vpc_link.id
            integrationTarget = aws_lb.alb.arn
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
            uri            = "http://${aws_lb.alb.dns_name}/auth/logout"
            connectionType    = "VPC_LINK"
            connectionId      = aws_apigatewayv2_vpc_link.vpc_link.id
            integrationTarget = aws_lb.alb.arn
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
            uri            = "http://${aws_lb.alb.dns_name}/users"
            connectionType    = "VPC_LINK"
            connectionId      = aws_apigatewayv2_vpc_link.vpc_link.id
            integrationTarget = aws_lb.alb.arn
          }
        }
        post = {
          operationId = "createUser"
          security    = [{ CognitoTokenAuthorizer = [] }]
          responses   = { "201" = { description = "User created" } }
          "x-amazon-apigateway-integration" = {
            type           = "HTTP_PROXY"
            httpMethod     = "POST"
            uri            = "http://${aws_lb.alb.dns_name}/users"
            connectionType    = "VPC_LINK"
            connectionId      = aws_apigatewayv2_vpc_link.vpc_link.id
            integrationTarget = aws_lb.alb.arn
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
            uri            = "http://${aws_lb.alb.dns_name}/users/{user_id}"
            connectionType    = "VPC_LINK"
            connectionId      = aws_apigatewayv2_vpc_link.vpc_link.id
            integrationTarget = aws_lb.alb.arn
            requestParameters = {
              "integration.request.path.user_id" = "method.request.path.user_id"
            }
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
            uri            = "http://${aws_lb.alb.dns_name}/users/{user_id}"
            connectionType    = "VPC_LINK"
            connectionId      = aws_apigatewayv2_vpc_link.vpc_link.id
            integrationTarget = aws_lb.alb.arn
            requestParameters = {
              "integration.request.path.user_id" = "method.request.path.user_id"
            }
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
            uri            = "http://${aws_lb.alb.dns_name}/users/{user_id}"
            connectionType    = "VPC_LINK"
            connectionId      = aws_apigatewayv2_vpc_link.vpc_link.id
            integrationTarget = aws_lb.alb.arn
            requestParameters = {
              "integration.request.path.user_id" = "method.request.path.user_id"
            }
          }
        }
      }

      # ── Browse / Products ────────────────────────────────────────────────────
      "/products" = {
        get = {
          operationId = "listProducts"
          security    = [{ CognitoTokenAuthorizer = [] }]
          parameters = [
            { name = "category", in = "query", required = false, schema = { type = "string" } },
            { name = "limit",    in = "query", required = false, schema = { type = "integer" } }
          ]
          responses = { "200" = { description = "List of products" } }
          "x-amazon-apigateway-integration" = {
            type              = "HTTP_PROXY"
            httpMethod        = "GET"
            uri               = "http://${aws_lb.alb.dns_name}/products"
            connectionType    = "VPC_LINK"
            connectionId      = aws_apigatewayv2_vpc_link.vpc_link.id
            integrationTarget = aws_lb.alb.arn
          }
        }
        post = {
          operationId = "createProduct"
          security    = [{ CognitoTokenAuthorizer = [] }]
          responses   = { "201" = { description = "Product created" } }
          "x-amazon-apigateway-integration" = {
            type              = "HTTP_PROXY"
            httpMethod        = "POST"
            uri               = "http://${aws_lb.alb.dns_name}/products"
            connectionType    = "VPC_LINK"
            connectionId      = aws_apigatewayv2_vpc_link.vpc_link.id
            integrationTarget = aws_lb.alb.arn
          }
        }
      }
      "/products/{product_id}" = {
        get = {
          operationId = "getProduct"
          security    = [{ CognitoTokenAuthorizer = [] }]
          parameters  = [{ name = "product_id", in = "path", required = true, schema = { type = "string" } }]
          responses   = { "200" = { description = "Product found" } }
          "x-amazon-apigateway-integration" = {
            type              = "HTTP_PROXY"
            httpMethod        = "GET"
            uri               = "http://${aws_lb.alb.dns_name}/products/{product_id}"
            connectionType    = "VPC_LINK"
            connectionId      = aws_apigatewayv2_vpc_link.vpc_link.id
            integrationTarget = aws_lb.alb.arn
            requestParameters = {
              "integration.request.path.product_id" = "method.request.path.product_id"
            }
          }
        }
        put = {
          operationId = "updateProduct"
          security    = [{ CognitoTokenAuthorizer = [] }]
          parameters  = [{ name = "product_id", in = "path", required = true, schema = { type = "string" } }]
          responses   = { "200" = { description = "Product updated" } }
          "x-amazon-apigateway-integration" = {
            type              = "HTTP_PROXY"
            httpMethod        = "PUT"
            uri               = "http://${aws_lb.alb.dns_name}/products/{product_id}"
            connectionType    = "VPC_LINK"
            connectionId      = aws_apigatewayv2_vpc_link.vpc_link.id
            integrationTarget = aws_lb.alb.arn
            requestParameters = {
              "integration.request.path.product_id" = "method.request.path.product_id"
            }
          }
        }
        delete = {
          operationId = "deleteProduct"
          security    = [{ CognitoTokenAuthorizer = [] }]
          parameters  = [{ name = "product_id", in = "path", required = true, schema = { type = "string" } }]
          responses   = { "204" = { description = "Product deleted" } }
          "x-amazon-apigateway-integration" = {
            type              = "HTTP_PROXY"
            httpMethod        = "DELETE"
            uri               = "http://${aws_lb.alb.dns_name}/products/{product_id}"
            connectionType    = "VPC_LINK"
            connectionId      = aws_apigatewayv2_vpc_link.vpc_link.id
            integrationTarget = aws_lb.alb.arn
            requestParameters = {
              "integration.request.path.product_id" = "method.request.path.product_id"
            }
          }
        }
      }

      # ── Search ───────────────────────────────────────────────────────────────
      "/search" = {
        get = {
          operationId = "searchProducts"
          security    = [{ CognitoTokenAuthorizer = [] }]
          parameters = [
            { name = "q",          in = "query", required = true,  schema = { type = "string" } },
            { name = "category",   in = "query", required = false, schema = { type = "string" } },
            { name = "min_price",  in = "query", required = false, schema = { type = "number" } },
            { name = "max_price",  in = "query", required = false, schema = { type = "number" } },
            { name = "page",       in = "query", required = false, schema = { type = "integer" } },
            { name = "page_size",  in = "query", required = false, schema = { type = "integer" } }
          ]
          responses = { "200" = { description = "Search results" } }
          "x-amazon-apigateway-integration" = {
            type              = "HTTP_PROXY"
            httpMethod        = "GET"
            uri               = "http://${aws_lb.alb.dns_name}/search"
            connectionType    = "VPC_LINK"
            connectionId      = aws_apigatewayv2_vpc_link.vpc_link.id
            integrationTarget = aws_lb.alb.arn
          }
        }
      }

      # ── Orders / Payment ─────────────────────────────────────────────────────
      "/orders" = {
        get = {
          operationId = "listOrders"
          security    = [{ CognitoTokenAuthorizer = [] }]
          parameters  = [{ name = "user_id", in = "query", required = true, schema = { type = "string" } }]
          responses   = { "200" = { description = "List of orders" } }
          "x-amazon-apigateway-integration" = {
            type              = "HTTP_PROXY"
            httpMethod        = "GET"
            uri               = "http://${aws_lb.alb.dns_name}/orders"
            connectionType    = "VPC_LINK"
            connectionId      = aws_apigatewayv2_vpc_link.vpc_link.id
            integrationTarget = aws_lb.alb.arn
          }
        }
        post = {
          operationId = "createOrder"
          security    = [{ CognitoTokenAuthorizer = [] }]
          responses   = { "201" = { description = "Order created" } }
          "x-amazon-apigateway-integration" = {
            type              = "HTTP_PROXY"
            httpMethod        = "POST"
            uri               = "http://${aws_lb.alb.dns_name}/orders"
            connectionType    = "VPC_LINK"
            connectionId      = aws_apigatewayv2_vpc_link.vpc_link.id
            integrationTarget = aws_lb.alb.arn
          }
        }
      }
      "/orders/{order_id}" = {
        get = {
          operationId = "getOrder"
          security    = [{ CognitoTokenAuthorizer = [] }]
          parameters  = [{ name = "order_id", in = "path", required = true, schema = { type = "string" } }]
          responses   = { "200" = { description = "Order found" } }
          "x-amazon-apigateway-integration" = {
            type              = "HTTP_PROXY"
            httpMethod        = "GET"
            uri               = "http://${aws_lb.alb.dns_name}/orders/{order_id}"
            connectionType    = "VPC_LINK"
            connectionId      = aws_apigatewayv2_vpc_link.vpc_link.id
            integrationTarget = aws_lb.alb.arn
            requestParameters = {
              "integration.request.path.order_id" = "method.request.path.order_id"
            }
          }
        }
      }

      # ── Shipping ─────────────────────────────────────────────────────────────
      "/shipping/{order_id}" = {
        get = {
          operationId = "getShipment"
          security    = [{ CognitoTokenAuthorizer = [] }]
          parameters  = [{ name = "order_id", in = "path", required = true, schema = { type = "string" } }]
          responses   = { "200" = { description = "Shipment found" } }
          "x-amazon-apigateway-integration" = {
            type              = "HTTP_PROXY"
            httpMethod        = "GET"
            uri               = "http://${aws_lb.alb.dns_name}/shipping/{order_id}"
            connectionType    = "VPC_LINK"
            connectionId      = aws_apigatewayv2_vpc_link.vpc_link.id
            integrationTarget = aws_lb.alb.arn
            requestParameters = {
              "integration.request.path.order_id" = "method.request.path.order_id"
            }
          }
        }
        patch = {
          operationId = "updateShipmentStatus"
          security    = [{ CognitoTokenAuthorizer = [] }]
          parameters  = [{ name = "order_id", in = "path", required = true, schema = { type = "string" } }]
          responses   = { "200" = { description = "Shipment status updated" } }
          "x-amazon-apigateway-integration" = {
            type              = "HTTP_PROXY"
            httpMethod        = "PATCH"
            uri               = "http://${aws_lb.alb.dns_name}/shipping/{order_id}/status"
            connectionType    = "VPC_LINK"
            connectionId      = aws_apigatewayv2_vpc_link.vpc_link.id
            integrationTarget = aws_lb.alb.arn
            requestParameters = {
              "integration.request.path.order_id" = "method.request.path.order_id"
            }
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
