#!/bin/bash

OUTPUT_FILE="lb_http_only.csv"
echo "Region,LB Name,app,bu,env,Security group id,number_of_targets" > "$OUTPUT_FILE"

regions=$(aws ec2 describe-regions --query "Regions[].RegionName" --output text)

for region in $regions; do
  echo "Checking region: $region"

  lbs=$(aws elbv2 describe-load-balancers --region "$region" --query 'LoadBalancers[?Type==`application`].LoadBalancerArn' --output text)

  for lb_arn in $lbs; do
    # Get listeners
    listeners=$(aws elbv2 describe-listeners --load-balancer-arn "$lb_arn" --region "$region")
    total_listeners=$(echo "$listeners" | jq '.Listeners | length')
    http_listeners=$(echo "$listeners" | jq '[.Listeners[] | select(.Port == 80)]')
    http_count=$(echo "$http_listeners" | jq 'length')

    # Only include LBs with *only* HTTP listeners
    if [[ "$total_listeners" -gt 0 && "$http_count" -eq "$total_listeners" ]]; then
      lb_info=$(aws elbv2 describe-load-balancers --load-balancer-arns "$lb_arn" --region "$region")
      lb_name=$(echo "$lb_info" | jq -r '.LoadBalancers[0].LoadBalancerName')
      sg_id=$(echo "$lb_info" | jq -r '.LoadBalancers[0].SecurityGroups[0]')

      # Tags
      tags=$(aws elbv2 describe-tags --resource-arns "$lb_arn" --region "$region")
      app=$(echo "$tags" | jq -r '.TagDescriptions[0].Tags[] | select(.Key=="app") | .Value')
      bu=$(echo "$tags" | jq -r '.TagDescriptions[0].Tags[] | select(.Key=="bu") | .Value')
      env=$(echo "$tags" | jq -r '.TagDescriptions[0].Tags[] | select(.Key=="env") | .Value')

      # Count targets
      target_count=0
      for tg_arn in $(echo "$http_listeners" | jq -r '.[].DefaultActions[].TargetGroupArn'); do
        count=$(aws elbv2 describe-target-health --target-group-arn "$tg_arn" --region "$region" \
                | jq '.TargetHealthDescriptions | length')
        target_count=$((target_count + count))
      done

      echo "$region,$lb_name,$app,$bu,$env,$sg_id,$target_count" >> "$OUTPUT_FILE"
    fi
  done
done

echo "Report generated: $OUTPUT_FILE"
