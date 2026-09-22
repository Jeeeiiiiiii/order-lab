# ---------------------------------------------------------------------------
# Security groups. One per tier, each admitting only the tier in front of it.
#
#   internet --80--> alb --8080--> app --5432--> db
#
# Rules reference the neighbouring group, not a CIDR, so they keep working
# when instances are replaced and IPs change.
# ---------------------------------------------------------------------------

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "Internet-facing ALB"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.name}-alb" }
}

resource "aws_security_group" "app" {
  name        = "${var.name}-app"
  description = "Order API instance"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.name}-app" }
}

resource "aws_security_group" "db" {
  name        = "${var.name}-db"
  description = "PostgreSQL"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.name}-db" }
}

# --- alb -------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from anywhere"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Forward to the API"
  from_port                    = var.app_port
  to_port                      = var.app_port
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.app.id

  # Floci reports this back as "<account>/<sg-id>"; ignore it or every plan
  # shows a no-op update.
  lifecycle {
    ignore_changes = [referenced_security_group_id]
  }
}

# --- app -------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  description                  = "API traffic from the ALB only"
  from_port                    = var.app_port
  to_port                      = var.app_port
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.alb.id

  # Floci reports this back as "<account>/<sg-id>"; ignore it or every plan
  # shows a no-op update.
  lifecycle {
    ignore_changes = [referenced_security_group_id]
  }
}

resource "aws_vpc_security_group_egress_rule" "app_all" {
  security_group_id = aws_security_group.app.id
  description       = "ECR, SQS, CloudWatch via NAT; the database"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# --- db --------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  description                  = "PostgreSQL from the API only"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.app.id

  # Floci reports this back as "<account>/<sg-id>"; ignore it or every plan
  # shows a no-op update.
  lifecycle {
    ignore_changes = [referenced_security_group_id]
  }
}

# No egress rule: the database initiates nothing.
