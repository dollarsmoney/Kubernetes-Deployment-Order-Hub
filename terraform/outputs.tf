###############################################################################
# outputs.tf — the values you will paste into later phases
###############################################################################
#
# Outputs serve three purposes here:
#   1. they hand you values you need on the command line
#      (`terraform output -raw ecr_backend_url`)
#   2. they document what this stack produces
#   3. they are how the Kubernetes manifests get their ARNs and image URLs
#
# NOTE ON SENSITIVE OUTPUTS: marking an output `sensitive = true` stops
# Terraform PRINTING it. It does NOT encrypt it, and it is still in plain text
# in terraform.tfstate. Sensitivity is a display setting, not a security
# control.
###############################################################################

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnets — the ALB lives here"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnets — EKS nodes and RDS live here"
  value       = aws_subnet.private[*].id
}

output "nat_gateway_ips" {
  description = "Public IPs your cluster appears to come FROM. Useful when allowlisting your egress with a third-party API."
  value       = aws_eip.nat[*].public_ip
}

# -----------------------------------------------------------------------------
# EKS
# -----------------------------------------------------------------------------

output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_version" {
  description = "Kubernetes version running on the control plane"
  value       = aws_eks_cluster.main.version
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN — the root of trust for IRSA"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "configure_kubectl" {
  description = "Run this to point kubectl at the cluster"
  value       = "aws eks update-kubeconfig --region ${local.region} --name ${aws_eks_cluster.main.name}"
}

# -----------------------------------------------------------------------------
# ECR — Phase 3/5 push targets
# -----------------------------------------------------------------------------

output "ecr_registry" {
  description = "Registry host. `docker login` targets this."
  value       = "${local.account_id}.dkr.ecr.${local.region}.amazonaws.com"
}

output "ecr_frontend_url" {
  description = "Frontend image repository URL"
  value       = aws_ecr_repository.app["frontend"].repository_url
}

output "ecr_backend_url" {
  description = "Backend image repository URL"
  value       = aws_ecr_repository.app["backend"].repository_url
}

output "ecr_login_command" {
  description = "Authenticate Docker against ECR (token is valid 12 hours)"
  value       = "aws ecr get-login-password --region ${local.region} | docker login --username AWS --password-stdin ${local.account_id}.dkr.ecr.${local.region}.amazonaws.com"
}

# -----------------------------------------------------------------------------
# IAM roles — Phase 6 and Phase 8 paste these into Kubernetes YAML
# -----------------------------------------------------------------------------

output "alb_controller_role_arn" {
  description = "IRSA role for the AWS Load Balancer Controller. Goes into the Helm --set serviceAccount.annotations flag."
  value       = aws_iam_role.alb_controller.arn
}

output "backend_irsa_role_arn" {
  description = "IRSA role for backend pods. Goes into kubernetes/serviceaccount.yaml as eks.amazonaws.com/role-arn."
  value       = aws_iam_role.backend.arn
}

# -----------------------------------------------------------------------------
# Database and secrets
# -----------------------------------------------------------------------------

output "rds_endpoint" {
  description = "RDS endpoint including port. Resolves ONLY inside the VPC."
  value       = aws_db_instance.main.endpoint
}

output "rds_address" {
  description = "RDS hostname without the port"
  value       = aws_db_instance.main.address
}

output "secret_name" {
  description = "Secrets Manager secret name. Goes into kubernetes/secretproviderclass.yaml."
  value       = aws_secretsmanager_secret.db.name
}

output "secret_arn" {
  description = "Secrets Manager secret ARN — the exact resource the backend IRSA policy allows"
  value       = aws_secretsmanager_secret.db.arn
}

output "kms_key_arn" {
  description = "The customer-managed key encrypting RDS, Secrets Manager, and logs"
  value       = aws_kms_key.main.arn
}

# The password is deliberately NOT output, not even as sensitive.
# There is no legitimate reason to print it: the application reads it from
# Secrets Manager. If you genuinely need it for a psql session, fetch it the
# same way the app does, which also leaves a CloudTrail record:
#
#   aws secretsmanager get-secret-value \
#     --secret-id jollof-run/db-credentials \
#     --query SecretString --output text | python -m json.tool

# -----------------------------------------------------------------------------
# WAF — Phase 9 pastes this into the Ingress annotation
# -----------------------------------------------------------------------------

output "waf_web_acl_arn" {
  description = "Web ACL ARN. Goes into ingress.yaml as alb.ingress.kubernetes.io/wafv2-acl-arn — this is how WAF gets attached to the ALB."
  value       = aws_wafv2_web_acl.main.arn
}

output "waf_web_acl_name" {
  description = "Web ACL name, for CloudWatch metric dimensions"
  value       = aws_wafv2_web_acl.main.name
}

# -----------------------------------------------------------------------------
# Observability
# -----------------------------------------------------------------------------

output "sns_topic_arn" {
  description = "SNS topic all alarms publish to"
  value       = aws_sns_topic.alerts.arn
}

output "dashboard_url" {
  description = "Direct link to the CloudWatch dashboard"
  value       = "https://${local.region}.console.aws.amazon.com/cloudwatch/home?region=${local.region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "cloudtrail_bucket" {
  description = "S3 bucket holding CloudTrail logs"
  value       = aws_s3_bucket.cloudtrail.id
}

output "cloudtrail_log_group" {
  description = "CloudWatch log group for CloudTrail — query this with Logs Insights in Phase 11"
  value       = aws_cloudwatch_log_group.cloudtrail.name
}

output "log_groups" {
  description = "Every log group this stack creates"
  value = compact([
    aws_cloudwatch_log_group.eks_cluster.name,
    aws_cloudwatch_log_group.vpc_flow_logs.name,
    aws_cloudwatch_log_group.waf.name,
    aws_cloudwatch_log_group.cloudtrail.name,
    var.enable_container_insights ? aws_cloudwatch_log_group.container_application[0].name : "",
  ])
}

# -----------------------------------------------------------------------------
# A summary you can read at a glance after apply
# -----------------------------------------------------------------------------

output "next_steps" {
  description = "What to do after this apply"
  value       = <<-EOT

    ============================================================
     ${local.name} — infrastructure ready
    ============================================================

     1. Point kubectl at the cluster
        aws eks update-kubeconfig --region ${local.region} --name ${aws_eks_cluster.main.name}
        kubectl get nodes

     2. Log Docker in to ECR
        aws ecr get-login-password --region ${local.region} \
          | docker login --username AWS --password-stdin ${local.account_id}.dkr.ecr.${local.region}.amazonaws.com

     3. Install the AWS Load Balancer Controller (Phase 6)
        role ARN: ${aws_iam_role.alb_controller.arn}

     4. Fill in the Kubernetes manifests
        backend IRSA role : ${aws_iam_role.backend.arn}
        secret name       : ${aws_secretsmanager_secret.db.name}
        WAF Web ACL ARN   : ${aws_wafv2_web_acl.main.arn}

     5. After the Ingress creates the ALB, re-apply with the ALB
        alarms enabled:
        terraform apply -var="alb_arn_suffix=$(aws elbv2 describe-load-balancers \
          --region ${local.region} --query "LoadBalancers[?contains(LoadBalancerName,'k8s-')].LoadBalancerArn" \
          --output text | cut -d'/' -f2-)"

     REMEMBER: this stack costs roughly $6/day. See docs/cost.md.
     Destroy the Ingress BEFORE running terraform destroy.

  EOT
}

# -----------------------------------------------------------------------------
# CI/CD — GitHub Actions OIDC
# -----------------------------------------------------------------------------

output "github_actions_role_arn" {
  description = "Role GitHub Actions assumes via OIDC. Goes into .github/workflows/ci-cd.yml as role-to-assume. Safe to commit: an ARN is an identifier, and the trust policy is what grants access."
  value       = aws_iam_role.github_actions.arn
}

output "github_oidc_provider_arn" {
  description = "The registered GitHub OIDC identity provider"
  value       = aws_iam_openid_connect_provider.github.arn
}
