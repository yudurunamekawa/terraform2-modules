############################################
# Provider & Locals
############################################
provider "aws" {
  region = "ap-northeast-1"
}

locals {
  http_port    = 80
  any_port     = 0
  any_protocol = "-1"
  tcp_protocol = "tcp"
  all_ips      = ["0.0.0.0/0"]
}

############################################
# Remote State (DB)
############################################
data "terraform_remote_state" "db" {
  backend = "s3"

  config = {
    bucket = var.db_remote_state_bucket
    key    = var.db_remote_state_key
    region = "ap-northeast-1"
  }
}

############################################
# VPC
############################################
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = merge(
    { Name = "${var.cluster_name}-vpc" },
    var.custom_tags
  )
}

############################################
# Subnets（Public IP 付与）
############################################
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-northeast-1a"
  map_public_ip_on_launch = true

  tags = merge(
    { Name = "${var.cluster_name}-public-1" },
    var.custom_tags
  )
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "ap-northeast-1c"
  map_public_ip_on_launch = true

  tags = merge(
    { Name = "${var.cluster_name}-public-2" },
    var.custom_tags
  )
}

############################################
# Internet Gateway & Route Table
############################################
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    { Name = "${var.cluster_name}-igw" },
    var.custom_tags
  )
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge(
    { Name = "${var.cluster_name}-public-rt" },
    var.custom_tags
  )
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

############################################
# Security Groups
############################################

# ALB SG
resource "aws_security_group" "alb" {
  name        = "${var.cluster_name}-alb-sg"
  description = "ALB security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = local.http_port
    to_port     = local.http_port
    protocol    = local.tcp_protocol
    cidr_blocks = local.all_ips
  }

  ingress {
    from_port   = var.server_port
    to_port     = var.server_port
    protocol    = local.tcp_protocol
    cidr_blocks = local.all_ips
  }

  egress {
    from_port   = local.any_port
    to_port     = local.any_port
    protocol    = local.any_protocol
    cidr_blocks = local.all_ips
  }

  tags = merge(
    { Name = "${var.cluster_name}-alb-sg" },
    var.custom_tags
  )
}

# EC2 SG
resource "aws_security_group" "instance" {
  name        = "${var.cluster_name}-instance-sg"
  description = "Instance security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = var.server_port
    to_port         = var.server_port
    protocol        = local.tcp_protocol
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = local.tcp_protocol
    cidr_blocks = local.all_ips
  }

  egress {
    from_port   = local.any_port
    to_port     = local.any_port
    protocol    = local.any_protocol
    cidr_blocks = local.all_ips
  }

  tags = merge(
    { Name = "${var.cluster_name}-instance-sg" },
    var.custom_tags
  )
}

############################################
# Target Group
############################################
resource "aws_lb_target_group" "tg" {
  name     = "${var.cluster_name}-tg"
  port     = var.server_port
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    port                = var.server_port
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 10
  }

  tags = merge(
    { Name = "${var.cluster_name}-tg" },
    var.custom_tags
  )
}

############################################
# ALB
############################################
resource "aws_lb" "alb" {
  name               = "${var.cluster_name}-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [
    aws_subnet.public_1.id,
    aws_subnet.public_2.id
  ]

  tags = merge(
    { Name = "${var.cluster_name}-alb" },
    var.custom_tags
  )
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = local.http_port
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

############################################
# AMI
############################################
data "aws_ami" "amazon_linux" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  owners = ["137112412989"]
}

############################################
# Launch Template
############################################
resource "aws_launch_template" "example" {
  name_prefix   = "${var.cluster_name}-lt-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  key_name      = var.key_name

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.instance.id]
  }

  user_data = base64encode(
    templatefile("${path.module}/user-data.sh", {
      server_port = var.server_port
      db_address  = data.terraform_remote_state.db.outputs.address
      db_port     = data.terraform_remote_state.db.outputs.port
    })
  )

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      { Name = "${var.cluster_name}-instance" },
      var.custom_tags
    )
  }
}

############################################
# Auto Scaling Group
############################################
resource "aws_autoscaling_group" "example" {
  name                = "${var.cluster_name}-asg"
  desired_capacity    = var.min_size
  min_size            = var.min_size
  max_size            = var.max_size
  vpc_zone_identifier = [
    aws_subnet.public_1.id,
    aws_subnet.public_2.id
  ]
  target_group_arns   = [aws_lb_target_group.tg.arn]

  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.example.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = var.cluster_name
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = var.custom_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  depends_on = [
    aws_launch_template.example,
    aws_lb_listener.http,
    aws_lb_target_group.tg
  ]
}
