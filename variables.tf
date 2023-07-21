variable "vpc_id" {
  type    = string
  default = "vpc-00b09e53c6e62a994"
}

variable "subnet_ids" {
  type    = set(string)
  default = ["subnet-0bf68322307a35cd6"]
}

variable "allowable-public-ip-ranges" {
  description = "Public IPs allowed to connect to the SFTP Server."
  type        = list(string)
  default     = ["208.95.71.55/32", "10.0.0.0/16"]
}

variable "aws_region" {
  type        = string
  default     = "us-east-1"
}


locals {
  sftpUsers = {
    "lwdvin" = "private_key_lwdvin.pem"
  }
}
