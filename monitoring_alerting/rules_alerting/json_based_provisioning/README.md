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


# Number or rules for each topic
under rules/gpu
GPU cluster health (5 rules)
GPU critical & warning conditions (10 rules)
GPU cost efficiency (5 rules)

under rules/nim-vllm
NIM vLLM models (8 rules)

under rules/nim-tensorrtllm
NIM embedding/TensorRT-LLM (5 rules)