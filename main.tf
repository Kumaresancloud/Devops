
variable "account_a_id" {}
variable "account_b_id" {}

variable "account_a_subnet_id" {}
variable "account_b_subnet_id" {}

module "account_a_sns_publisher" {
  source    = "./modules/account_a"
  providers = {
    aws = aws.account_a
  }
  subnet_id    = var.account_a_subnet_id
  account_b_id = var.account_b_id
  sg_name = "ssh_port"
}


module "account_b_sqs_consumer" {
  source    = "./modules/account_b"
  providers = {
    aws = aws.account_b
  }
  subnet_id    = var.account_b_subnet_id
  account_a_id = var.account_a_id
  sg_name = "ssh_port"
}
