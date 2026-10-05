resource "aws_dynamodb_table" "users" {
  name         = "${local.prefix}-users"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "user_id"

  attribute {
    name = "user_id"
    type = "S"
  }

  attribute {
    name = "email"
    type = "S"
  }

  global_secondary_index {
    name            = "email-index"
    hash_key        = "email"
    projection_type = "ALL"
  }

  tags = {
    Name    = "${local.prefix}-users"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_dynamodb_table" "products" {
  name         = "${local.prefix}-products"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "category"
    type = "S"
  }

  global_secondary_index {
    name            = "category-index"
    hash_key        = "category"
    projection_type = "ALL"
  }

  tags = {
    Name    = "${local.prefix}-products"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_dynamodb_table" "orders" {
  name         = "${local.prefix}-orders"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "user_id"
    type = "S"
  }

  global_secondary_index {
    name            = "user-index"
    hash_key        = "user_id"
    projection_type = "ALL"
  }

  tags = {
    Name    = "${local.prefix}-orders"
    Project = "anycompany-users"
    Env     = var.env
  }
}

resource "aws_dynamodb_table" "shipments" {
  name         = "${local.prefix}-shipments"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "order_id"

  attribute {
    name = "order_id"
    type = "S"
  }

  tags = {
    Name    = "${local.prefix}-shipments"
    Project = "anycompany-users"
    Env     = var.env
  }
}

output "dynamodb_users_table_name"     { value = aws_dynamodb_table.users.name }
output "dynamodb_products_table_name"  { value = aws_dynamodb_table.products.name }
output "dynamodb_orders_table_name"    { value = aws_dynamodb_table.orders.name }
output "dynamodb_shipments_table_name" { value = aws_dynamodb_table.shipments.name }
