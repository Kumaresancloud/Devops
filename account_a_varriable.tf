variable "subnet_id" {
  description = "The subnet ID for the EC2 instance"
  type        = string
}

variable "account_a_id" {
  description = "The AWS Account ID of Account A (SNS publisher)"
  type        = string
}
