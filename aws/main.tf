terraform {
    required_providers {
        aws = {
            source = "hashicorp/aws"
            version = ">= 6.8.0"
        }
    }
}

variable "region" {
    type = string
    default = "us-east-2"
}

variable "aws_access_key_id" {
    type = string
    sensitive = true
}

variable "aws_secret_access_key_id" {
    type = string
    sensitive = true
}

variable "coder_access_url" {
    type = string
    deafult = ""
}

variable "coder_wildcard_access_url" {
    type = string
    deafult = ""
}

provider "aws" {
    region = var.region
    access_key  = var.aws_access_key_id
    secret_key  = var.aws_secret_access_key_id
}

locals {
    envs = {
        CODER_VERSION = "2.25.1"
        CODER_ACCESS_URL = var.coder_access_url != "" : var.coder_access_url ? "http://${aws_instance.this.public_dns}"
        CODER_WILDCARD_ACCESS_URL = var.coder_wildcard_access_url != "" : var.coder_wildcard_access_url ? "*.${aws_instance.this.public_dns}"
        CODER_HTTP_ADDRESS = "127.0.0.1:3000"
        CODER_TLS_ADDRESS = "127.0.0.1:3443"
        CODER_TLS_ENABLE = false
    }
    tags = {
        Name = "Coder"
    }
}

resource "aws_ssm_parameter" "env" {
    for_each = local.envs
    type  = "String"
    name  = each.key
    value = each.value
    tags = local.tags
}

data "aws_iam_policy_document" "this" {
    statement {
        actions = ["sts:AssumeRole"]
        principals {
            type        = "Service"
            identifiers = ["ec2.amazonaws.com"]
        }
    }
}

resource "aws_iam_role" "this" {
    name               = "coder"
    assume_role_policy = data.aws_iam_policy_document.this.json
    managed_policy_arns = [
        "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess",
        "arn:aws:iam::aws:policy/AmazonSSMManagedEC2InstanceDefaultPolicy"
    ]
    inline_policy {
        name = "PassRole"
        policy = jsonencode({
            Version = "2012-10-17"
            Statement = [{
                Action   = ["iam:PassRole"]
                Effect   = "Allow"
                Resource = "*"
            }]
        })
    }

    tags = local.tags
}

resource "aws_iam_instance_profile" "this" {
    name = "coder"
    role = aws_iam_role.this.name
}

data "aws_vpc" "this" {
    default = true
}

locals {
    ingress_rules = {
        mc = {
            from_port         = 25565
            to_port           = 25565
            ip_protocol       = "tcp"
        }
        https =  {
            from_port         = 443
            to_port           = 443
            ip_protocol       = "tcp"
        }
        http =  {
            from_port         = 80
            to_port           = 80
            ip_protocol       = "tcp"
        }
        ssh =  {
            from_port         = 22
            to_port           = 22
            ip_protocol       = "tcp"
        }
        icmp =  {
            from_port = -1
            to_port = -1
            ip_protocol = "icmp"
        }
    }
}

resource "aws_vpc_security_group_ingress_rule" "in" {
    for_each = local.ingress_rules
    security_group_id = aws_security_group.this.id
    cidr_ipv4         = "0.0.0.0/0"
    from_port         = each.value.from_port
    to_port           = each.value.to_port
    ip_protocol       = each.value.ip_protocol
}


resource "aws_vpc_security_group_egress_rule" "all" {
    security_group_id = aws_security_group.this.id
    cidr_ipv4         = "0.0.0.0/0"
    ip_protocol       = "-1"
}

resource "aws_security_group" "this" {
    name        = "coder"
    description = "Coder Security Group."
    vpc_id      = data.aws_vpc.this.id
    tags = local.tags
}

data "aws_ami" "this" {
    most_recent = true
    owners      = ["amazon"]
    filter {
        name   = "architecture"
        values = ["arm64"]
    }
    filter {
        name   = "name"
        values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-20250610"]
    }
}

data "cloudinit_config" "this" {
    gzip = false
    base64_encode = false
    part {
        filename = "cloud-config"
        content_type = "text/cloud-config"
        content = yamlencode({
            cloud_final_modules = [
                ["scripts-user", "always"]
            ]
        })
    }
    part {
        filename = "setup.sh"
        content_type = "text/x-shellscript"
        # Don't pass in local.envs. Causes cyclic-dependency
        content = templatefile("${path.module}/scripts/install.sh", {})
    }
}

resource "aws_instance" "this" {
    instance_type = "t4g.small"
    ami = data.aws_ami.this.id
    availability_zone = "${var.region}a"
    vpc_security_group_ids = [ aws_security_group.this.id ]
    iam_instance_profile = aws_iam_instance_profile.this.name
    
    instance_market_options {
        market_type = "spot"
    }
    
    user_data_base64 = base64encode(data.cloudinit_config.this.rendered)
    user_data_replace_on_change = true

    tags = local.tags
}