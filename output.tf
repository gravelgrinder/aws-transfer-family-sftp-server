output "sftp_connection_string_lwdvin" {
  value = "sftp -i ./${local_file.private_key["lwdvin"].filename} ${aws_transfer_user.example["lwdvin"].user_name}@${aws_vpc_endpoint.transfer.dns_entry[1].dns_name}"
}