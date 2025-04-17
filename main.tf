# ----------------------------
# ACCOUNT A - SNS + EC2 PUBLISHER
# ----------------------------

# Create SNS Topic in Account A
resource "aws_sns_topic" "sns_topic" {
  provider = aws.account_a
  name = "cross-account-topic"
}

# IAM Role for EC2 to publish to SNS
resource "aws_iam_role" "ec2_publish_role" {
  provider = aws.account_a
  name = "ec2-publish-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Principal = { Service = "ec2.amazonaws.com" },
      Effect = "Allow",
      Sid = ""
    }]
  })
}

resource "aws_iam_policy" "sns_publish_policy" {
  provider = aws.account_a
  name = "sns-publish-policy"
  policy = jsonencode({
    "Version": "2008-10-17",
    "Id": "SNS",
    "Statement": [
      {
        "Sid": "__default_statement_ID",
        "Effect": "Allow",
        "Principal": {
          "AWS": "*"
        },
        "Action": [
          "SNS:Publish",
          "SNS:RemovePermission",
          "SNS:SetTopicAttributes",
          "SNS:DeleteTopic",
          "SNS:ListSubscriptionsByTopic",
          "SNS:GetTopicAttributes",
          "SNS:AddPermission",
          "SNS:Subscribe"
        ],
        "Resource": aws_sns_topic.sns_topic.arn,
        "Condition": {
          "StringEquals": {
            "AWS:SourceOwner": "541153896426"
          }
        }
      },
      {
        "Effect": "Allow",
        "Principal": {
          "AWS": "arn:aws:iam::568812757521:root"
        },
        "Action": "sns:Subscribe",
        "Resource": aws_sns_topic.sns_topic.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "sns_policy_attachment" {
  provider = aws.account_a
  role       = aws_iam_role.ec2_publish_role.name
  policy_arn = aws_iam_policy.sns_publish_policy.arn
}

# EC2 Instance in Account A
resource "aws_instance" "ec2_publisher" {
  provider = aws.account_a
  ami                         = "ami-00a929b66ed6e0de6" # Replace with a valid AMI
  instance_type               = "t2.micro"
  subnet_id                   = "subnet-0d3ba75070ff8198b" # Replace accordingly
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = true
  user_data = <<-EOF
              #!/bin/bash
              yum install -y aws-cli jq
              aws sns publish --topic-arn ${aws_sns_topic.sns_topic.arn} \
                --message "Hello from Account A EC2" \
                --region us-east-1
              EOF
}

resource "aws_iam_instance_profile" "ec2_profile" {
  provider = aws.account_a
  name = "ec2-profile"
  role = aws_iam_role.ec2_publish_role.name
}

# ----------------------------
# ACCOUNT B - SQS + EC2 CONSUMER
# ----------------------------

# Create SQS Queue
resource "aws_sqs_queue" "sqs_queue" {
  provider = aws.account_b
  name = "cross-account-queue"
}

# Policy to allow SNS from Account A to publish
resource "aws_sqs_queue_policy" "sqs_policy" {
  provider = aws.account_b
  queue_url = aws_sqs_queue.sqs_queue.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = "*",
      Action = "sqs:SendMessage",
      Resource = aws_sqs_queue.sqs_queue.arn,
      Condition = {
        ArnEquals = {
          "aws:SourceArn" = "arn:aws:sns:us-east-1:541153896426:cross-account-topic"
        }
      }
    }]
  })
}

data "aws_sns_topic" "sns_topic_from_a" {
  provider = aws.account_b
  arn      = "arn:aws:sns:us-east-1:541153896426:cross-account-topic"
}

resource "aws_sns_topic_subscription" "sqs_subscription" {
  provider  = aws.account_b
  topic_arn = data.aws_sns_topic.sns_topic_from_a.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.sqs_queue.arn
}

# EC2 Role to Read from SQS
resource "aws_iam_role" "ec2_consume_role" {
  provider = aws.account_b
  name = "ec2-consume-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Principal = { Service = "ec2.amazonaws.com" },
      Effect = "Allow",
      Sid = ""
    }]
  })
}

resource "aws_iam_policy" "sqs_receive_policy" {
  provider = aws.account_b
  name = "sqs-receive-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ],
        Resource = aws_sqs_queue.sqs_queue.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "sqs_policy_attachment" {
  provider = aws.account_b
  role       = aws_iam_role.ec2_consume_role.name
  policy_arn = aws_iam_policy.sqs_receive_policy.arn
}

# EC2 Instance in Account B
resource "aws_instance" "ec2_consumer" {
  provider = aws.account_b
  ami                         = "ami-00a929b66ed6e0de6" # AMI for ec2
  instance_type               = "t2.micro"
  subnet_id                   = "subnet-1e767854" # subnetID
  iam_instance_profile        = aws_iam_instance_profile.consumer_profile.name
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

resource "aws_iam_instance_profile" "consumer_profile" {
  provider = aws.account_b
  name = "consumer-profile"
  role = aws_iam_role.ec2_consume_role.name
}
