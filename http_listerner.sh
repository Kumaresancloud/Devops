#!/bin/bash

set -euo pipefail

REPORT="http_only_lbs_report.csv"
echo "Region,LB Name,App,BU,Env,Security Group ID,Number of Targets" > "$REPORT"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGIONS=$(aws ec2 describe-regions --query 'Regions[].RegionName' --output text)

for REGION in $REGIONS; do
  echo "🔍 Checking region: $REGION"
  LBS=$(aws elbv2 describe-load-balancers --region "$REGION" --query 'LoadBalancers[].LoadBalancerArn' --output text)

  for LB_ARN in $LBS; do
    # Get listener protocols
    LISTENER_PROTOCOLS=$(aws elbv2 describe-listeners --region "$REGION" --load-balancer-arn "$LB_ARN" --query 'Listeners[].Protocol' --output text)

    # Filter out LBs with only HTTP
    if [[ "$LISTENER_PROTOCOLS" =~ ^HTTP$ ]]; then
      LB_DESC=$(aws elbv2 describe-load-balancers --region "$REGION" --load-balancer-arns "$LB_ARN" --query 'LoadBalancers[0]' --output json)
      LB_NAME=$(echo "$LB_DESC" | jq -r '.LoadBalancerName')
      SG_ID=$(echo "$LB_DESC" | jq -r '.SecurityGroups[0]')

      TAGS=$(aws elbv2 describe-tags --region "$REGION" --resource-arns "$LB_ARN" --query 'TagDescriptions[0].Tags' --output json)
      APP=$(echo "$TAGS" | jq -r '.[] | select(.Key=="app") | .Value // "N/A"')
      BU=$(echo "$TAGS" | jq -r '.[] | select(.Key=="bu") | .Value // "N/A"')
      ENV=$(echo "$TAGS" | jq -r '.[] | select(.Key=="env") | .Value // "N/A"')

      TARGET_GROUPS=$(aws elbv2 describe-target-groups --region "$REGION" --load-balancer-arn "$LB_ARN" --query 'TargetGroups[].TargetGroupArn' --output text)
      NUM_TARGETS=0
      for TG_ARN in $TARGET_GROUPS; do
        COUNT=$(aws elbv2 describe-target-health --region "$REGION" --target-group-arn "$TG_ARN" --query 'TargetHealthDescriptions' --output json | jq length)
        NUM_TARGETS=$((NUM_TARGETS + COUNT))
      done

      echo "$REGION,$LB_NAME,$APP,$BU,$ENV,$SG_ID,$NUM_TARGETS" >> "$REPORT"
    fi
  done
done

echo "Report generated: $REPORT"
