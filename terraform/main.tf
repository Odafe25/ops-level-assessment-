data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_security_group" "hello_sg" {
  name        = "hello-svc-sg"
  description = "Allow SSH, HTTP, HTTPS"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = []
  }

  ingress {
    description      = "HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = []
  }

  ingress {
    description      = "HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = []
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = []
  }
}

# Render cloud-init for each env
locals {
  prod_user_data    = templatefile("${path.module}/user_data_app.sh", {
    ENV_NAME      = "production"
    DOMAIN        = var.prod_domain
    GIT_REPO_URL  = var.git_repo_url
  })

  staging_user_data = templatefile("${path.module}/user_data_app.sh", {
    ENV_NAME      = "staging"
    DOMAIN        = var.staging_domain
    GIT_REPO_URL  = var.git_repo_url
  })
}

resource "aws_instance" "prod" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.small"
  subnet_id                   = element(data.aws_subnets.default.ids, 0)
  vpc_security_group_ids      = [aws_security_group.hello_sg.id]
  key_name                    = var.key_name
  associate_public_ip_address = true

  user_data = local.prod_user_data

  tags = { Name = "hello-svc-prod" }
}

resource "aws_instance" "staging" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.small"
  subnet_id                   = element(data.aws_subnets.default.ids, 0)
  vpc_security_group_ids      = [aws_security_group.hello_sg.id]
  key_name                    = var.key_name
  associate_public_ip_address = true

  user_data = local.staging_user_data

  tags = { Name = "hello-svc-staging" }
}

output "prod_public_dns"     { value = aws_instance.prod.public_dns }
output "staging_public_dns"  { value = aws_instance.staging.public_dns }

output "verify_commands" {
  value = [
    "curl -I  http://${aws_instance.prod.public_dns}",
    "curl -I  http://${aws_instance.staging.public_dns}",
    "curl -k https://${aws_instance.prod.public_dns}",
    "curl -k https://${aws_instance.staging.public_dns}",
  ]
}
