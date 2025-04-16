# ----------------------------
# ACCOUNT A - SNS + EC2 PUBLISHER
# ----------------------------

# Create SNS Topic in Account A
resource "aws_sns_topic" "sns_topic" {
  name = "cross-account-topic"
}

# IAM Role for EC2 to publish to SNS
resource "aws_iam_role" "ec2_publish_role" {
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
  name = "sns-publish-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = ["sns:Publish"],
      Resource = aws_sns_topic.sns_topic.arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "sns_policy_attachment" {
  role       = aws_iam_role.ec2_publish_role.name
  policy_arn = aws_iam_policy.sns_publish_policy.arn
}

# EC2 Instance in Account A
resource "aws_instance" "ec2_publisher" {
  ami                         = "ami-xxxxxxxx" # Replace with a valid AMI
  instance_type               = "t2.micro"
  subnet_id                   = "subnet-xxxxxxxx" # Replace accordingly
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = true
  user_data = <<-EOF
              #!/bin/bash
              yum install -y aws-cli jq
              aws sns publish --topic-arn ${aws_sns_topic.sns_topic.arn} \
                --message "Hello from Account A EC2" \
                --region ${var.region}
              EOF
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-profile"
  role = aws_iam_role.ec2_publish_role.name
}

# ----------------------------
# ACCOUNT B - SQS + EC2 CONSUMER
# ----------------------------

# Create SQS Queue
resource "aws_sqs_queue" "sqs_queue" {
  name = "cross-account-queue"
}

# Policy to allow SNS from Account A to publish
resource "aws_sqs_queue_policy" "sqs_policy" {
  queue_url = aws_sqs_queue.sqs_queue.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { AWS = "arn:aws:iam::<ACCOUNT_A_ID>:root" },
      Action = "sqs:SendMessage",
      Resource = aws_sqs_queue.sqs_queue.arn,
      Condition = {
        ArnEquals = {
          "aws:SourceArn" = "arn:aws:sns:${var.region}:<ACCOUNT_A_ID>:cross-account-topic"
        }
      }
    }]
  })
}

# EC2 Role to Read from SQS
resource "aws_iam_role" "ec2_consume_role" {
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
  role       = aws_iam_role.ec2_consume_role.name
  policy_arn = aws_iam_policy.sqs_receive_policy.arn
}

# EC2 Instance in Account B
resource "aws_instance" "ec2_consumer" {
  ami                         = "ami-yyyyyyyy" # Replace with valid AMI
  instance_type               = "t2.micro"
  subnet_id                   = "subnet-yyyyyyyy" # Replace accordingly
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
  name = "consumer-profile"
  role = aws_iam_role.ec2_consume_role.name
}
