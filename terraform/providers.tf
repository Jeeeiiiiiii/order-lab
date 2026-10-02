terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Every AWS call is redirected at the local emulator. The `endpoints` block is
# the only thing separating this from a real AWS deploy -- remove it and the
# same configuration targets a real account.
provider "aws" {
  region     = var.region
  access_key = "test"
  secret_key = "test"

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_requesting_account_id  = true

  # Deleting a load balancer makes the provider poll DescribeNetworkInterfaces
  # with a `description` filter, which Floci answers with a 500. The SDK's
  # default 25 retries with backoff turn that into a half-hour hang on one
  # resource; with 2 it fails in seconds, the provider logs a warning, and
  # the destroy continues. Remove this against a real account.
  max_retries = 2

  endpoints {
    ec2        = var.endpoint_url
    elbv2      = var.endpoint_url
    rds        = var.endpoint_url
    sqs        = var.endpoint_url
    lambda     = var.endpoint_url
    iam        = var.endpoint_url
    sts        = var.endpoint_url
    ecr        = var.endpoint_url
    logs       = var.endpoint_url
    cloudwatch = var.endpoint_url
    dynamodb   = var.endpoint_url
  }
}
