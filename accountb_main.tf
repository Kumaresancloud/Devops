variable "subnet_id" {}
variable "account_a_id" {}

resource "aws_sqs_queue" "sqs_queue" {
  name = "cross-account-queue"
}

resource "aws_sqs_queue_policy" "allow_sns_publish" {
  queue_url = aws_sqs_queue.sqs_queue.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = "*",
      Action   = "sqs:SendMessage",
      Resource = aws_sqs_queue.sqs_queue.arn,
      Condition = {
        ArnEquals = {
          "aws:SourceArn" = "arn:aws:sns:us-east-1:${var.account_a_id}:cross-account-topic"
        }
      }
    }]
  })
}

resource "aws_sns_topic_subscription" "sqs_sub" {
  topic_arn = "arn:aws:sns:us-east-1:${var.account_a_id}:cross-account-topic"
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.sqs_queue.arn
}

resource "aws_iam_role" "consumer_role" {
  name = "sqs-consumer-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "sqs_consume_policy" {
  name = "sqs-consume-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes"
      ],
      Resource = aws_sqs_queue.sqs_queue.arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "consumer_policy_attach" {
  role       = aws_iam_role.consumer_role.name
  policy_arn = aws_iam_policy.sqs_consume_policy.arn
}

resource "aws_iam_instance_profile" "consumer_profile" {
  name = "consumer-instance-profile"
  role = aws_iam_role.consumer_role.name
}

resource "aws_instance" "consumer_ec2" {
  ami                    = "ami-00a929b66ed6e0de6"
  instance_type          = "t2.micro"
  subnet_id              = var.subnet_id
  iam_instance_profile   = aws_iam_instance_profile.consumer_profile.name
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
