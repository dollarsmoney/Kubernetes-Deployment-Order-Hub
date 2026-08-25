###############################################################################
# variables.tf — every knob in the project, in one place
###############################################################################
#
# Rule of thumb: if you might reasonably want to change a value, or if it
# appears in more than one file, it belongs here. Hunting for a hardcoded
# instance type across eleven .tf files is how infrastructure rots.
#
# Override any of these with:
#   terraform apply -var="node_instance_type=t3.medium"
# or by creating a terraform.tfvars file (which .gitignore excludes).
###############################################################################

# -----------------------------------------------------------------------------
# Project identity
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Name prefix for every resource. Keep it short and DNS-safe."
  type        = string
  default     = "jollof-run"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.project_name))
    error_message = "project_name must be lowercase alphanumeric with hyphens, 2-21 chars, starting with a letter."
  }
}

variable "environment" {
  description = "Environment tag. This project only ever builds one."
  type        = string
  default     = "learning"
}

variable "aws_region" {
  description = "AWS region. Everything is regional; nothing here is global except IAM and CloudTrail's multi-region flag."
  type        = string
  default     = "us-east-1"
}

# -----------------------------------------------------------------------------
# Networking  (used by vpc.tf)
# -----------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC. /16 gives us 65,536 addresses — far more than we need, but leaves room and costs nothing."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = <<-EOT
    How many Availability Zones to spread across.
    Minimum 2 — an ALB REQUIRES subnets in at least two AZs and will refuse
    to be created otherwise. Going to 3 increases resilience and, if you also
    raise nat_gateway_count, cost.
  EOT
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3. An ALB needs at least 2 AZs."
  }
}

variable "single_nat_gateway" {
  description = <<-EOT
    true  = one NAT Gateway shared by all private subnets  (~$33/month)
    false = one NAT Gateway per AZ, the production pattern (~$33/month EACH)

    The lean-build default is true. The trade-off: if the AZ holding the NAT
    Gateway fails, private subnets in the OTHER AZs lose internet egress —
    nodes cannot pull images or reach AWS APIs. For a learning project that is
    an acceptable risk; for production it is not.
  EOT
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# EKS  (used by eks.tf)
# -----------------------------------------------------------------------------

variable "cluster_version" {
  description = "Kubernetes minor version for the EKS control plane. Check supported versions with: aws eks describe-addon-versions --addon-name vpc-cni --query 'addons[0].addonVersions[0].compatibilities[].clusterVersion'"
  type        = string
  default     = "1.34"
}

variable "node_instance_type" {
  description = <<-EOT
    EC2 instance type for worker nodes.

    IMPORTANT — the VPC CNI gives each pod a real VPC IP address from an ENI,
    so the instance type caps how many pods fit on a node:

      t3.small  -> 11 pods/node   (2 nodes = 22 slots)   ~$0.0208/hr
      t3.medium -> 17 pods/node   (2 nodes = 34 slots)   ~$0.0416/hr

    Our workload needs roughly 18 pods including kube-system, the ALB
    controller, and the Secrets Store CSI DaemonSets. t3.small fits, but only
    just. If you ever see a pod stuck in Pending with
    "Too many pods" or "0/2 nodes are available", raise this to t3.medium.
  EOT
  type        = string
  default     = "t3.small"
}

variable "node_desired_size" {
  description = "Number of worker nodes to run."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum nodes. Set to 0 to scale the cluster down to nothing overnight without destroying it — see docs/cost.md."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum nodes. Also the headroom a rolling node update can use."
  type        = number
  default     = 3
}

variable "node_disk_size" {
  description = "EBS root volume per node, in GiB. 20 is the AWS default and plenty for our images."
  type        = number
  default     = 20
}

# -----------------------------------------------------------------------------
# RDS  (used by rds.tf)
# -----------------------------------------------------------------------------

variable "db_instance_class" {
  description = "RDS instance size. db.t3.micro is the smallest and is free-tier eligible in the account's first 12 months."
  type        = string
  default     = "db.t3.micro"
}

variable "db_engine_version" {
  description = "PostgreSQL major.minor version. Check availability with: aws rds describe-db-engine-versions --engine postgres --query 'DBEngineVersions[].EngineVersion'"
  type        = string
  default     = "16.4"
}

variable "db_allocated_storage" {
  description = "Storage in GiB. 20 is the RDS minimum for gp3."
  type        = number
  default     = 20
}

variable "db_name" {
  description = "Initial database name created inside the instance."
  type        = string
  default     = "jollofrun"
}

variable "db_username" {
  description = <<-EOT
    Master username. This is NOT a secret — usernames are not credentials, and
    this value is visible in the RDS console anyway.

    The PASSWORD is never declared as a variable. It is generated by
    random_password in secrets.tf and written straight to Secrets Manager.
    A `variable "db_password"` would be an invitation to put a password in a
    tfvars file, so the variable simply does not exist.
  EOT
  type        = string
  default     = "jollofadmin"
}

variable "db_multi_az" {
  description = "Multi-AZ doubles RDS cost for a standby replica. Off for learning."
  type        = bool
  default     = false
}

variable "db_backup_retention_days" {
  description = "Automated backup retention. 1 = the minimum that still leaves backups enabled. 0 disables them entirely."
  type        = number
  default     = 1
}

# -----------------------------------------------------------------------------
# WAF  (used by waf.tf)
# -----------------------------------------------------------------------------

variable "waf_rate_limit" {
  description = "Requests per 5-minute window from a single IP before the rate-based rule blocks it. AWS enforces a minimum of 100."
  type        = number
  default     = 2000
}

# -----------------------------------------------------------------------------
# Observability  (used by cloudwatch.tf / cloudtrail.tf)
# -----------------------------------------------------------------------------

variable "log_retention_days" {
  description = <<-EOT
    CloudWatch Logs retention. The AWS DEFAULT IS "never expire", which
    quietly accumulates storage cost forever. Always set this explicitly.
    Valid values: 1,3,5,7,14,30,60,90,120,150,180,365,400,545,731,1096,1827,...
  EOT
  type        = number
  default     = 7
}

variable "alert_email" {
  description = <<-EOT
    Email address for CloudWatch alarm notifications via SNS.
    Leave empty to skip creating the subscription.

    NOTE: AWS sends a confirmation email you MUST click. Until you do, the
    subscription sits in "PendingConfirmation" and you will receive nothing.
  EOT
  type        = string
  default     = ""
}

variable "enable_container_insights" {
  description = "Install the amazon-cloudwatch-observability EKS addon, which ships node/pod metrics and container logs to CloudWatch. This is what makes Phase 10 interesting. It does add log-ingestion cost."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Filled in AFTER Phase 6  (used by cloudwatch.tf)
# -----------------------------------------------------------------------------

variable "alb_arn_suffix" {
  description = <<-EOT
    The ALB's ARN suffix, e.g. "app/k8s-jollofru-jollofru-abc123/0123456789abcdef".

    CHICKEN AND EGG: the ALB is created by the AWS Load Balancer Controller in
    Phase 6, not by Terraform, so this value cannot exist on the first apply.
    Leave it empty and the ALB alarms/widgets are skipped.

    After Phase 6, get it with:
      aws elbv2 describe-load-balancers --region us-east-1 \
        --query "LoadBalancers[?contains(LoadBalancerName,'jollof')].LoadBalancerArn" \
        --output text | cut -d'/' -f2-

    then re-apply with:
      terraform apply -var="alb_arn_suffix=app/k8s-.../abc123"
  EOT
  type        = string
  default     = ""
}
