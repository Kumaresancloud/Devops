echo "Scanning RDS instances missing 'RPO' tag across all regions..."

# Loop through each region
for REGION in $REGIONS; do
  echo "Checking region: $REGION"

  # Get all RDS instance identifiers in the region
  DB_INSTANCES=$(aws rds describe-db-instances --region "$REGION" \
                  --query "DBInstances[].DBInstanceIdentifier" --output text)

  for DB_ID in $DB_INSTANCES; do
    # Get instance class
    INSTANCE_CLASS=$(aws rds describe-db-instances --db-instance-identifier "$DB_ID" \
                      --region "$REGION" --query "DBInstances[0].DBInstanceClass" --output text)

    # Get tags for the instance
    TAGS=$(aws rds list-tags-for-resource \
              --region "$REGION" \
              --resource-name arn:aws:rds:$REGION:$ACCOUNT_ID:db:$DB_ID \
              --query "TagList[].Key" --output text)

    # Check if "RPO" tag exists
    if [[ ! " ${TAGS[@]} " =~ " RPO " ]]; then
      echo "$ACCOUNT_ID,$REGION,$DB_ID,$INSTANCE_CLASS" >> "$REPORT_FILE"
    fi
  done
done

echo "✅ Report generated: $REPORT_FILE"
