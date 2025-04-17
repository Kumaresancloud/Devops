#!/bin/bash

QUEUE_URL="<YOUR_SQS_QUEUE_URL>"  # Example: https://sqs.us-east-1.amazonaws.com/<ACCOUNT_B_ID>/cross-account-queue
REGION="us-east-1"

mkdir -p /tmp/sqs-messages

while true; do
  MESSAGES=$(aws sqs receive-message \
    --queue-url "$QUEUE_URL" \
    --region "$REGION" \
    --max-number-of-messages 1 \
    --wait-time-seconds 10)

  echo "$MESSAGES" | jq -c '.Messages[]?' | while read -r msg; do
    BODY=$(echo "$msg" | jq -r '.Body')
    RECEIPT=$(echo "$msg" | jq -r '.ReceiptHandle')
    TIMESTAMP=$(date +%s)

    echo "$BODY" > "/tmp/sqs-messages/message-$TIMESTAMP.json"
    echo "Stored message at /tmp/sqs-messages/message-$TIMESTAMP.json"

    aws sqs delete-message \
      --queue-url "$QUEUE_URL" \
      --region "$REGION" \
      --receipt-handle "$RECEIPT"
  done
done
