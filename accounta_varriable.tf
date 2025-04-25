variable "subnet_id" {
  description = "The subnet ID for the EC2 instance"
  type        = string
}

variable "account_b_id" {
  description = "The AWS Account ID of Account B (for cross-account access)"
  type        = string
}
