# Create Rules - /api/v1/provisioning/alert-rules

# Deploy a single rule
./deploy-rule.sh rules/high-cpu.env

# Deploy all rules - All rules under dir "rules" will be created.
./deploy-rule.sh --all

# Deploy notification policies
./deploy_notification_policy.sh

# Cleanup the rules and policies - No Flag defaults to --rules
./cleanup.sh --rules     # Delete all alert rules only
./cleanup.sh --policy    # Reset notification policy only
./cleanup.sh --all       # Both