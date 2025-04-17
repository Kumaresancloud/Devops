#!/bin/bash

# Replace with the actual SNS topic ARN
SNS_TOPIC_ARN="arn:aws:sns:us-east-1:<ACCOUNT_A_ID>:cross-account-topic"
REGION="us-east-1"

# Message you want to send
MESSAGE="Hello from Account A EC2!"

# Publish message to SNS
aws sns publish \
  --region "$REGION" \
  --topic-arn "$SNS_TOPIC_ARN" \
  --message "$MESSAGE"
