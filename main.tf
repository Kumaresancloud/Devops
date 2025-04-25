module "account_a_sns_publisher" {
  source    = "./modules/account_a"
  providers = {
    aws = aws.account_a
  }
  subnet_id       = "subnet-xxxxxxxx"
  account_b_id    = "ACCOUNT_B_ID"
}

module "account_b_sqs_consumer" {
  source    = "./modules/account_b"
  providers = {
    aws = aws.account_b
  }
  subnet_id    = "subnet-yyyyyyyy"
  account_a_id = "ACCOUNT_A_ID"
}
