#!/bin/bash

set -e

# Output CSV file
REPORT_FILE="rds_missing_rpo_report.csv"

# Write headers
echo "AWS Account ID,Region,RDS Instance ID,Instance Class" > "$REPORT_FILE"

# Get current account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Get all AWS regions
REGIONS=$(aws ec2 describe-regions --query "Regions[].RegionName" --output text)

for REGION in $REGIONS; do
  echo "Checking region: $REGION"
  DB_INSTANCES=$(aws rds describe-db-instances --region "$REGION" --query "DBInstances[].DBInstanceIdentifier" --output text)

  for DB_ID in $DB_INSTANCES; do
    INSTANCE_CLASS=$(aws rds describe-db-instances --region "$REGION" \
                    --db-instance-identifier "$DB_ID" \
                    --query "DBInstances[0].DBInstanceClass" --output text)

    TAGS=$(aws rds list-tags-for-resource \
           --region "$REGION" \
           --resource-name arn:aws:rds:$REGION:$ACCOUNT_ID:db:$DB_ID \
           --query "TagList[].Key" --output text)

    if [[ ! " ${TAGS[@]} " =~ " RPO " ]]; then
      echo "$ACCOUNT_ID,$REGION,$DB_ID,$INSTANCE_CLASS" >> "$REPORT_FILE"
    fi
  done
done

echo "✅ Report saved to $REPORT_FILE"
