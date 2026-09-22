# ---------------------------------------------------------------------------
# The application: an image in ECR, one instance that runs it with Docker,
# and an ALB in front.
# ---------------------------------------------------------------------------

# --- ECR -------------------------------------------------------------------

resource "aws_ecr_repository" "api" {
  name                 = "${var.name}/api"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = "${var.name}-api" }
}

# --- EC2 -------------------------------------------------------------------

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

locals {
  # From inside the instance the ECR registry has two names. In AWS it is the
  # repository URL. Locally that hostname resolves to loopback inside the
  # container, so the same registry is addressed by its container name on
  # the emulator's network, over plain HTTP.
  image = var.local_mode ? "floci-ecr-registry:5000/${aws_ecr_repository.api.name}:${var.app_image_tag}" : "${aws_ecr_repository.api.repository_url}:${var.app_image_tag}"
}

resource "aws_instance" "app" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.app_instance_type
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.app.name

  user_data = templatefile("${path.module}/../scripts/app-bootstrap.sh", {
    local_mode   = var.local_mode
    region       = var.region
    endpoint_url = var.internal_endpoint_url == null ? "" : var.internal_endpoint_url
    image        = local.image
    registry     = var.local_mode ? "floci-ecr-registry:5000" : aws_ecr_repository.api.repository_url
    app_port     = var.app_port
    log_group    = aws_cloudwatch_log_group.app.name
    metric_ns    = var.name
    db_host      = aws_db_instance.orders.address
    db_port      = aws_db_instance.orders.port
    db_name      = var.db_name
    db_user      = var.db_username
    db_password  = var.db_password
    queue_url    = aws_sqs_queue.orders.url
  })

  # A change to user data means a new bootstrap, which means a new instance.
  user_data_replace_on_change = true

  tags = {
    Name = "${var.name}-app"
    Role = "api"
  }
}

# --- ALB -------------------------------------------------------------------
# Layer 7: the ALB terminates HTTP, health-checks the API on /health, and
# is the only thing with a public address. Locally it is metadata;
# scripts/alb-local.sh runs a stand-in proxy on the emulator's network.

resource "aws_lb" "api" {
  name               = "${var.name}-api"
  internal           = false
  load_balancer_type = "application"
  subnets            = aws_subnet.public[*].id
  security_groups    = [aws_security_group.alb.id]

  tags = { Name = "${var.name}-api" }
}

resource "aws_lb_target_group" "api" {
  name        = "${var.name}-api"
  vpc_id      = aws_vpc.this.id
  port        = var.app_port
  protocol    = "HTTP"
  target_type = "instance"

  health_check {
    path                = "/health"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = { Name = "${var.name}-api" }
}

resource "aws_lb_target_group_attachment" "api" {
  target_group_arn = aws_lb_target_group.api.arn
  target_id        = aws_instance.app.id
  port             = var.app_port
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.api.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}
