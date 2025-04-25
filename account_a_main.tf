variable "subnet_id" {}
variable "account_b_id" {}

resource "aws_sns_topic" "sns_topic" {
  name = "cross-account-topic"
}

resource "aws_sns_topic_policy" "sns_topic_policy" {
  arn = aws_sns_topic.sns_topic.arn
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid       = "AllowSubscriptionFromAccountB",
      Effect    = "Allow",
      Principal = { AWS = "arn:aws:iam::${var.account_b_id}:root" },
      Action    = ["sns:Subscribe", "sns:GetTopicAttributes"],
      Resource  = aws_sns_topic.sns_topic.arn
    }]
  })
}

resource "aws_iam_role" "publisher_role" {
  name = "sns-publisher-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "sns_publish_policy" {
  name = "sns-publish-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = "sns:Publish",
      Resource = aws_sns_topic.sns_topic.arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "attach_publish_policy" {
  role       = aws_iam_role.publisher_role.name
  policy_arn = aws_iam_policy.sns_publish_policy.arn
}

resource "aws_iam_instance_profile" "publisher_profile" {
  name = "publisher-instance-profile"
  role = aws_iam_role.publisher_role.name
}

resource "aws_instance" "publisher_ec2" {
  ami                    = "ami-00a929b66ed6e0de6"
  instance_type          = "t2.micro"
  subnet_id              = var.subnet_id
  iam_instance_profile   = aws_iam_instance_profile.publisher_profile.name
  associate_public_ip_address = true
  user_data = <<-EOF
              #!/bin/bash
              yum install -y aws-cli
              aws sns publish --region us-east-1 --topic-arn "${aws_sns_topic.sns_topic.arn}" --message "Hello from Account A EC2"
              EOF
}
