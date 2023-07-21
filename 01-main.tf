### Consumer Account Resources
provider "aws" {
  profile = "default"
  region  = "us-east-1"
}

data "aws_caller_identity" "main-acct" {
}

###############################################################################
### Create SFTP S3 Bucket
###############################################################################
resource "aws_s3_bucket" "sftp-bucket" {
  bucket = "tf-sftp-bucket"
  force_destroy = true

  tags = {
      Name        = "tf-sftp-bucket"
      Environment = "DEV"
  }  
}

/*resource "aws_s3_bucket_acl" "sftp-bucket" {
  bucket = aws_s3_bucket.sftp-bucket.id
  acl    = "private"
}*/

resource "aws_s3_bucket_versioning" "sftp-bucket" {
  bucket = aws_s3_bucket.sftp-bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sftp-bucket" {
  bucket = aws_s3_bucket.sftp-bucket.id
  rule {
      apply_server_side_encryption_by_default {
      sse_algorithm     = "AES256"
      }
  }
}

resource "aws_s3_bucket_public_access_block" "sftp-bucket" {
  bucket = aws_s3_bucket.sftp-bucket.id

  block_public_acls   = true
  ignore_public_acls  = true
  block_public_policy = true
  restrict_public_buckets = true
}
###############################################################################


###############################################################################
### IAM Role for SFTP Server logging to CloudWatch
###############################################################################
resource "aws_iam_role" "example" {
  name                = "tf-transfer-logging-role"
  assume_role_policy  = "${file("IAM/transfer-logging-assume-role-policy.json")}"
  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AWSTransferLoggingAccess"]
}
###############################################################################


###############################################################################
### Security Group for AWS Transfer SFTP Server
###############################################################################
resource "aws_security_group" "sftpSG" {
  name        = "tf-transfer-family-sg"
  description = "Security Group for SFTP Server."
  vpc_id      = var.vpc_id
  tags = {
    Name = "tf-transfer-family-sg"
  }  
}

resource "aws_security_group_rule" "ingress01_sftp" {
  type              = "ingress"
  description       = "Allow SSH/SFTP Connections from specific IP address."
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = var.allowable-public-ip-ranges
  security_group_id = aws_security_group.sftpSG.id
}

###############################################################################

resource "aws_vpc_endpoint" "transfer" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.transfer.server"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids = [aws_security_group.sftpSG.id]
  private_dns_enabled = true

    tags = {
      Name        = "tf-transfer-family-vpce"
      Environment = "DEV"
  }  
}


resource "aws_transfer_server" "example" {
  endpoint_type = "VPC_ENDPOINT"
  security_policy_name = "TransferSecurityPolicy-2020-06"

  endpoint_details {
    vpc_endpoint_id = aws_vpc_endpoint.transfer.id
    /*subnet_ids = var.subnet_ids
    vpc_id     = var.vpc_id
    security_group_ids = [aws_security_group.sftpSG.id]*/
  }

  protocols   = ["SFTP"]
  identity_provider_type = "SERVICE_MANAGED"
/*
  identity_provider_type = "API_GATEWAY"
  url                    = "${aws_api_gateway_deployment.example.invoke_url}${aws_api_gateway_resource.example.path}"
  */
}

###############################################################################
### SFTP User Role 
###############################################################################
data "template_file" "sftp_trust_relationship" {
  template = "${file("IAM/01_sftp_bucket_trust_rel.json")}"

  vars = {}
}

data "template_file" "sftp_policy" {
  template = "${file("IAM/02_sftp_user_bucket_permissions.json")}"

  vars = {sftp_bucket_name = "${aws_s3_bucket.sftp-bucket.id}"}
}


resource "aws_iam_policy" "sftp_bucket_policy" {
  name        = "tf_sftp_bucket_policy"
  path        = "/"
  description = "Policy for the SFTP S3 bucket to allow AWS Transfer SFTP Server users to access it"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = "${data.template_file.sftp_policy.rendered}"
}

resource "aws_iam_role" "sftp_bucket_role" {
  name                = "tf-sftp-bucket_role"
  assume_role_policy  = "${data.template_file.sftp_trust_relationship.rendered}"
  managed_policy_arns = [aws_iam_policy.sftp_bucket_policy.arn]
  tags                = {}
}
###############################################################################

resource "tls_private_key" "lwdvin" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  key_name   = "tf-sftp-user-key-lwdvin"
  public_key = tls_private_key.lwdvin.public_key_openssh
}


data "template_file" "sftp_user_session_policy" {
  template = "${file("IAM/03_sftp_user_session_policy.json")}"

  vars = {}
}

resource "aws_transfer_user" "example" {
  for_each  = local.sftpUsers
  server_id = aws_transfer_server.example.id
  user_name = each.key
  role      = aws_iam_role.sftp_bucket_role.arn
  policy = "${data.template_file.sftp_user_session_policy.rendered}"
  

  home_directory_type = "PATH"
  home_directory = "/${aws_s3_bucket.sftp-bucket.id}/${each.key}"
  /*home_directory_mappings {
    entry  = "/"
    target = "/${aws_s3_bucket.sftp-bucket.id}/$${Transfer:UserName}"
  }*/
}

resource "aws_transfer_ssh_key" "example" {
  for_each  = local.sftpUsers
  server_id = aws_transfer_server.example.id
  user_name = each.key
  body      = tls_private_key.lwdvin.public_key_openssh
}

resource "local_file" "private_key" {
  for_each = local.sftpUsers
  content  = tls_private_key.lwdvin.private_key_openssh
  filename = each.value
  file_permission = 0500
}
