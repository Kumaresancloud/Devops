# ------------------------------
# PROVIDERS FOR BOTH ACCOUNTS
# ------------------------------
provider "aws" {
  alias  = "account_a"
  region = "us-east-1"
  profile = "account-a"
}

provider "aws" {
  alias  = "account_b"
  region = "us-east-1"
  profile = "account-b"
}

# ------------------------------
# ACCOUNT A - SNS + EC2 PUBLISHER
# ------------------------------
resource "aws_sns_topic" "sns_topic" {
  provider = aws.account_a
  name     = "cross-account-topic"
}

resource "aws_sns_topic_policy" "sns_topic_policy" {
  provider = aws.account_a
  arn      = aws_sns_topic.sns_topic.arn
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "AllowSubscriptionFromAccountB",
        Effect    = "Allow",
        Principal = { AWS = "arn:aws:iam::ACCOUNT_B_ID:root" },
        Action    = [
          "sns:Subscribe",
          "sns:GetTopicAttributes"
        ],
        Resource  = aws_sns_topic.sns_topic.arn
      }
    ]
  })
}

resource "aws_iam_role" "publisher_role" {
  provider = aws.account_a
  name     = "sns-publisher-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "sns_publish_policy" {
  provider = aws.account_a
  name     = "sns-publish-policy"
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
  provider = aws.account_a
  role       = aws_iam_role.publisher_role.name
  policy_arn = aws_iam_policy.sns_publish_policy.arn
}

resource "aws_iam_instance_profile" "publisher_profile" {
  provider = aws.account_a
  name     = "publisher-instance-profile"
  role     = aws_iam_role.publisher_role.name
}

resource "aws_instance" "publisher_ec2" {
  provider = aws.account_a
  ami           = "ami-00a929b66ed6e0de6"  # Amazon Linux 2
  instance_type = "t2.micro"
  subnet_id     = "subnet-xxxxxxxx"       # Replace with actual subnet
  iam_instance_profile = aws_iam_instance_profile.publisher_profile.name
  associate_public_ip_address = true
  user_data = <<-EOF
              #!/bin/bash
              yum install -y aws-cli
              aws sns publish --region us-east-1 --topic-arn "${aws_sns_topic.sns_topic.arn}" --message "Hello from Account A EC2"
              EOF
}

# ------------------------------
# ACCOUNT B - SQS + EC2 CONSUMER
# ------------------------------
resource "aws_sqs_queue" "sqs_queue" {
  provider = aws.account_b
  name     = "cross-account-queue"
}

resource "aws_sqs_queue_policy" "allow_sns_publish" {
  provider  = aws.account_b
  queue_url = aws_sqs_queue.sqs_queue.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = "*",
        Action = "sqs:SendMessage",
        Resource = aws_sqs_queue.sqs_queue.arn,
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = "arn:aws:sns:us-east-1:ACCOUNT_A_ID:cross-account-topic"
          }
        }
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "sqs_sub" {
  provider  = aws.account_b
  topic_arn = "arn:aws:sns:us-east-1:ACCOUNT_A_ID:cross-account-topic"
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.sqs_queue.arn
}

resource "aws_iam_role" "consumer_role" {
  provider = aws.account_b
  name     = "sqs-consumer-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "sqs_consume_policy" {
  provider = aws.account_b
  name     = "sqs-consume-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ],
        Resource = aws_sqs_queue.sqs_queue.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "consumer_policy_attach" {
  provider = aws.account_b
  role       = aws_iam_role.consumer_role.name
  policy_arn = aws_iam_policy.sqs_consume_policy.arn
}

resource "aws_iam_instance_profile" "consumer_profile" {
  provider = aws.account_b
  name     = "consumer-instance-profile"
  role     = aws_iam_role.consumer_role.name
}

resource "aws_instance" "consumer_ec2" {
  provider = aws.account_b
  ami           = "ami-00a929b66ed6e0de6"
  instance_type = "t2.micro"
  subnet_id     = "subnet-yyyyyyyy"  # Replace
  iam_instance_profile = aws_iam_instance_profile.consumer_profile.name
  associate_public_ip_address = true
  user_data = <<-EOF
              #!/bin/bash
              yum install -y aws-cli jq
              QUEUE_URL=${aws_sqs_queue.sqs_queue.id}
              while true; do
                MESSAGES=$(aws sqs receive-message --queue-url "$QUEUE_URL" --max-number-of-messages 1 --wait-time-seconds 10)
                echo "$MESSAGES" | jq -c '.Messages[]?' | while read -r msg; do
                  BODY=$(echo "$msg" | jq -r '.Body')
                  RECEIPT=$(echo "$msg" | jq -r '.ReceiptHandle')
                  echo "$BODY" > "/tmp/message-$(date +%s).json"
                  aws sqs delete-message --queue-url "$QUEUE_URL" --receipt-handle "$RECEIPT"
                done
              done
              EOF
}
