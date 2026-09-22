variable "region" {
  type    = string
  default = "us-east-1"
}

variable "endpoint_url" {
  description = "Floci endpoint as seen from this machine. Everything in providers.tf points here."
  type        = string
  default     = "http://localhost:4566"
}

variable "internal_endpoint_url" {
  description = "Floci endpoint as seen from inside a container on its Docker network -- the EC2 instance and the Lambda resolve it by service name, not localhost. Set to null against a real account so the SDKs use the real AWS endpoints."
  type        = string
  default     = "http://floci:4566"
}

variable "name" {
  type    = string
  default = "order-lab"
}

variable "vpc_cidr" {
  type    = string
  default = "10.1.0.0/16"
}

# Two AZs: an ALB refuses subnets in fewer, and an RDS subnet group does too.
variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.1.0.0/24", "10.1.1.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.1.10.0/24", "10.1.11.0/24"]
}

variable "app_port" {
  type    = number
  default = 8080
}

variable "app_instance_type" {
  type    = string
  default = "t3.small"
}

variable "app_image_tag" {
  description = "Tag of the API image in ECR. scripts/push-image.sh builds and pushes it."
  type        = string
  default     = "latest"
}

variable "db_name" {
  type    = string
  default = "orders"
}

variable "db_username" {
  type    = string
  default = "app"
}

variable "db_password" {
  description = "Master password. A lab default; in a real account generate it and hand it to the instance through Secrets Manager, never through user data."
  type        = string
  sensitive   = true
  default     = "orders-lab-password"
}

variable "local_mode" {
  description = "True when running against Floci. Switches the EC2 bootstrap to the emulator's plain-HTTP registry and static credentials. False against a real account, where the instance profile and ECR do the same job."
  type        = bool
  default     = true
}
