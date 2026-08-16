provider "aws" {
  region = "ap-northeast-1"
}

resource "aws_db_instance" "example" {
  identifier              = var.db_identifier
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = var.instance_class
  allocated_storage       = var.allocated_storage
  username                = var.username
  password                = var.password
  db_name                 = var.db_name
  skip_final_snapshot     = true
  publicly_accessible     = false
  vpc_security_group_ids  = [aws_security_group.db.id]
}

resource "aws_security_group" "db" {
  name = "${var.db_identifier}-sg"

  ingress {
    from_port   = var.db_port
    to_port     = var.db_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # 必要なら後で制限
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}