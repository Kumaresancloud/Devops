#!/bin/bash

set -euo pipefail

REPORT_FILE="rds_missing_rpo_report.csv"
echo "AWS Account ID,Region,RDS Instance ID,Instance Class" > "$REPORT_FILE"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGIONS=$(aws ec2 describe-regions --query "Regions[].RegionName" --output text)

for REGION in $REGIONS; do
  echo "🔍 Checking region: $REGION"

  # Get DB instances in region
  DB_INSTANCES=$(aws rds describe-db-instances \
      --region "$REGION" \
      --query "DBInstances[].{ID:DBInstanceIdentifier, Class:DBInstanceClass}" \
      --output json)

  DB_COUNT=$(echo "$DB_INSTANCES" | jq length)
  if [[ "$DB_COUNT" -eq 0 ]]; then
    echo "No DB instances in region $REGION"
    continue
  fi

  for i in $(seq 0 $((DB_COUNT - 1))); do
    DB_ID=$(echo "$DB_INSTANCES" | jq -r ".[$i].ID")
    CLASS=$(echo "$DB_INSTANCES" | jq -r ".[$i].Class")
    DB_ARN="arn:aws:rds:$REGION:$ACCOUNT_ID:db:$DB_ID"

    echo "Checking tags for $DB_ID in $REGION"

    # Try to get tags; handle failures gracefully
    TAG_KEYS=$(aws rds list-tags-for-resource \
        --region "$REGION" \
        --resource-name "$DB_ARN" \
        --query "TagList[].Key" \
        --output text 2>/dev/null || true)

    if [[ -z "$TAG_KEYS" || ! "$TAG_KEYS" =~ RPO ]]; then
      echo "$ACCOUNT_ID,$REGION,$DB_ID,$CLASS" >> "$REPORT_FILE"
    fi
  done
done

echo "✅ Done. Report saved to $REPORT_FILE"
