terraform {
  required_version = ">= 1.0.0, < 2.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0, < 6.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0.0, < 4.0.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.7.0, < 1.0.0"
    }
    template = {
      source  = "hashicorp/template"
      version = ">=2.1.2"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazonlinux2" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*x86_64-gp2"]
  }

  owners = ["amazon"]
}

#data "aws_ami" "rhel" {
#  most_recent = true
#  owners = ["679593333241"] # Foundation Security
#  filter {
#    name = "name"
#    values = ["foundation-h-*-rhel8-cislevel2-*"] # CIS Level 2 Hardened Red Hat Enterprise Linux 8
#  }
#  filter {
#    name = "virtualization-type"
#    values = ["hvm"]
#  }
#  filter {
#    name = "architecture"
#    values = ["x86_64"]
#  }
#}

resource "random_id" "default" {
  count       = var.use_unique_names ? 1 : 0
  byte_length = 2
}

locals {
  name                          = var.use_unique_names ? "${var.name_prefix}-${lower(random_id.default[0].hex)}" : var.name_prefix
  access_log_bucket_name_prefix = "${local.name}-accesslogs"
  certificate_file              = "tls.cert"
  web_file                      = "tls.key"
  config                        = "zarf-config.yaml"
  tags = merge(
    var.tags,
    {
      DeployedBy = data.aws_caller_identity.current.arn
    }
  )
}

module "vpc" {
  source                       = "git::https://github.com/defenseunicorns/terraform-aws-uds-vpc.git?ref=v0.1.5"
  name                         = local.name
  tags                         = local.tags
  vpc_cidr                     = var.vpc_cidr
  azs                          = [data.aws_availability_zones.available.names[0], data.aws_availability_zones.available.names[1], data.aws_availability_zones.available.names[2]]
  public_subnets               = [for k, v in module.vpc.azs : cidrsubnet(module.vpc.vpc_cidr_block, 5, k)]
  private_subnets              = [for k, v in module.vpc.azs : cidrsubnet(module.vpc.vpc_cidr_block, 5, k + 4)]
  create_database_subnet_group = false
  instance_tenancy             = "default"
  enable_nat_gateway           = true
  single_nat_gateway           = true
}

# Create a bucket for certs / config
resource "aws_s3_bucket" "tf-copy-file-s3" {
  # -- TODO production bucket acl
  # checkov:skip=CKV_AWS_144: Cross region replication is overkill
  # checkov:skip=CKV2_AWS_62: "Ensure S3 buckets should have event notifications enabled"
  # checkov:skip=CKV_AWS_145: "Ensure that S3 buckets are encrypted with KMS by default"
  # checkov:skip=CKV2_AWS_6: "Ensure that S3 bucket has a Public Access block"
  # checkov:skip=CKV_AWS_21: "Ensure all data stored in the S3 bucket have versioning enabled"
  # checkov:skip=CKV2_AWS_61: "Ensure that an S3 bucket has a lifecycle configuration"
  # checkov:skip=CKV_AWS_18: "Ensure the S3 bucket has access logging enabled" -- This is the access logging bucket. Logging to the logging bucket would cause an infinite loop.
  bucket        = "narwhal-test-automation"
  force_destroy = true
}

resource "aws_s3_bucket_acl" "tf-copy-file-s3" {
  bucket = aws_s3_bucket.tf-copy-file-s3.id
  acl    = "private"
}

# Upload Files to S3
resource "aws_s3_object" "file1" {
  bucket        = aws_s3_bucket.tf-copy-file-s3.id
  key           = "tls.cert"
  source        = local.certificate_file
  source_hash   = filemd5(local.certificate_file)
  etag          = filemd5(local.certificate_file)
  force_destroy = true
}
resource "aws_s3_object" "file2" {
  bucket        = aws_s3_bucket.tf-copy-file-s3.id
  key           = "tls.key"
  source        = local.web_file
  source_hash   = filemd5(local.web_file)
  etag          = filemd5(local.web_file)
  force_destroy = true
}

resource "aws_s3_object" "file3" {
  bucket        = aws_s3_bucket.tf-copy-file-s3.id
  key           = "tls.key"
  source        = local.web_file
  source_hash   = filemd5(local.config)
  etag          = filemd5(local.config)
  force_destroy = true
}


data "aws_iam_policy_document" "kms_access" {
  # checkov:skip=CKV_AWS_111: todo reduce perms on key
  # checkov:skip=CKV_AWS_109: todo be more specific with resources
  # checkov:skip=CKV_AWS_356: todo be more specific with kms resources
  statement {
    sid = "KMS Key Default"
    principals {
      type = "AWS"
      identifiers = [
        "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
      ]
    }

    actions = [
      "kms:*",
    ]

    resources = ["*"]
  }
  statement {
    sid = "CloudWatchLogsEncryption"
    principals {
      type        = "Service"
      identifiers = ["logs.${var.region}.amazonaws.com"]
    }
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]

    resources = ["*"]
  }
  statement {
    sid = "Cloudtrail KMS permissions"
    principals {
      type = "Service"
      identifiers = [
        "cloudtrail.amazonaws.com"
      ]
    }
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]
    resources = ["*"]
  }
}

# IAM Policy with Assume Role to EC2
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}
# Configure IAM Role
resource "aws_iam_role" "ec2_iam_role" {
  name               = "ec2-iam-role"
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}
# Configure IAM Instance Profile
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-profile"
  role = aws_iam_role.ec2_iam_role.name
}
# Attach EC2 Policies to Instance Role
resource "aws_iam_policy_attachment" "ec2_attach1" {
  name       = "ec2-iam-attachment"
  roles      = [aws_iam_role.ec2_iam_role.id]
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_policy_attachment" "ec2_attach2" {
  name       = "ec2-iam-attachment"
  roles      = [aws_iam_role.ec2_iam_role.id]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforSSM"
}
# Create S3 IAM Policy
resource "aws_iam_policy" "s3-ec2-policy" {
  # -- TODO, get a production s3 policy running
  # checkov:skip=CKV_AWS_18: "Ensure the S3 bucket has access logging enabled"
  # checkov:skip=CKV_AWS_290: "Ensure IAM policies does not allow write access without constraints"
  # checkov:skip=CKV_AWS_288: "Ensure IAM policies does not allow data exfiltration"
  # checkov:skip=CKV_AWS_289: "Ensure IAM policies does not allow permissions management /resource exposure without contraints"
  # checkov:skip=CKV_AWS_355: "Ensure no IAM policies documents allow '*' as a statement's resource for restrictable actions"
  name        = "s3-ec2-policy"
  description = "S3 ec2 policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:*"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:s3:::narwhal-test-automation"
      },
    ]
  })
}

# Attach S3 Policies to Instance Role
resource "aws_iam_policy_attachment" "s3_attach" {
  name       = "s3-iam-attachment"
  roles      = [aws_iam_role.ec2_iam_role.id]
  policy_arn = aws_iam_policy.s3-ec2-policy.arn
}

resource "aws_kms_key" "default" {
  description             = "SSM Key"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_access.json
  tags                    = local.tags
  multi_region            = true
}

resource "aws_kms_alias" "default" {
  name_prefix   = "alias/${local.name}"
  target_key_id = aws_kms_key.default.key_id
}

resource "aws_s3_bucket" "access_log_bucket" {
  # checkov:skip=CKV_AWS_144: Cross region replication is overkill
  # checkov:skip=CKV_AWS_18: "Ensure the S3 bucket has access logging enabled" -- This is the access logging bucket. Logging to the logging bucket would cause an infinite loop.
  # checkov:skip=CKV2_AWS_62: "Ensure S3 buckets should have event notifications enabled" -- TODO: enable event notifications
  # checkov:skip=CKV_AWS_145: "Ensure that S3 buckets are encrypted with KMS by default" -- S3 buckets are always encrypted by default now
  # checkov:skip=CKV2_AWS_6: "Ensure that S3 bucket has a Public Access block" -- TODO: add a public access block
  # checkov:skip=CKV_AWS_21: "Ensure all data stored in the S3 bucket have versioning enabled" -- TODO: enable versioning
  # checkov:skip=CKV2_AWS_61: "Ensure that an S3 bucket has a lifecycle configuration" -- TODO: Add a lifecycle configuration
  bucket_prefix = local.access_log_bucket_name_prefix
  force_destroy = true
  tags          = local.tags

  lifecycle {
    //noinspection HCLUnknownBlockType
    precondition {
      condition     = length(local.access_log_bucket_name_prefix) <= 37
      error_message = "Bucket name prefixes may not be longer than 37 characters."
    }
  }
}

data "template_file" "server" {
  template = file("${path.module}/s3copy.sh")
  vars = {
    bucket_name = aws_s3_bucket.tf-copy-file-s3.name
  }
}

module "server" {
  source               = "git::https://github.com/defenseunicorns/terraform-aws-uds-bastion.git?ref=v0.0.11"
  name                 = local.name
  ami_id               = data.aws_ami.amazonlinux2.id
  instance_type        = var.instance_type
  user_data            = data.template_file.server.rendered
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.id
  root_volume_config = {
    volume_type = "gp3"
    volume_size = 100
  }
  vpc_id                         = module.vpc.vpc_id
  subnet_id                      = module.vpc.private_subnets[0]
  region                         = var.region
  access_logs_bucket_name        = aws_s3_bucket.access_log_bucket.id
  kms_key_arn                    = aws_kms_key.default.arn
  session_log_bucket_name_prefix = "${local.name}-sessionlogs"
  ssh_user                       = "ec2-user"
  ssh_password                   = "password"
  assign_public_ip               = false
  tenancy                        = "default"
  zarf_version                   = var.zarf_version
  tags                           = local.tags
}
