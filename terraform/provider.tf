###############################################################################
# provider.tf — who we are talking to, and with which plugin versions
###############################################################################
#
# Terraform needs three things before it can do anything:
#   1. which version of Terraform itself is acceptable
#   2. which provider plugins to download (a "provider" = an API client)
#   3. how to configure each provider (region, credentials, defaults)
#
# We pin version RANGES, not exact versions. "~> 6.0" means ">= 6.0, < 7.0" —
# accept bug fixes and features, refuse breaking major-version changes.
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # Generates the RDS password. It never appears in source — see secrets.tf.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    # Reads the EKS OIDC endpoint's TLS certificate so we can compute the
    # thumbprint IAM needs to trust it. Used once, in eks.tf.
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # ---------------------------------------------------------------------------
  # STATE BACKEND
  # ---------------------------------------------------------------------------
  # We use the default LOCAL backend: state lands in ./terraform.tfstate.
  #
  # This is a deliberate learning-project choice, and it has a real cost:
  # terraform.tfstate contains EVERY value Terraform manages, including the
  # generated database password. That is why .gitignore excludes *.tfstate.
  #
  # A real team would use the block below instead — S3 for durability and
  # sharing, KMS for encryption at rest, DynamoDB for state locking so two
  # engineers cannot apply at the same time:
  #
  #   backend "s3" {
  #     bucket         = "my-tfstate-bucket"
  #     key            = "jollof-run/terraform.tfstate"
  #     region         = "us-east-1"
  #     encrypt        = true
  #     kms_key_id     = "alias/terraform-state"
  #     dynamodb_table = "terraform-locks"
  #   }
  #
  # Be able to explain this trade-off. "I used local state because it is a
  # solo learning project, and here is exactly what that costs me" is a much
  # better interview answer than not having thought about it.
  # ---------------------------------------------------------------------------
}

###############################################################################
# The AWS provider
###############################################################################
# Credentials are NOT configured here. The provider resolves them in order:
#   1. environment variables (AWS_ACCESS_KEY_ID, ...)
#   2. the shared credentials file (~/.aws/credentials)
#   3. IAM roles (EC2 instance profile, ECS task role, etc.)
#
# Never put access keys in a .tf file. There is no reason to, ever.
###############################################################################

provider "aws" {
  region = var.aws_region

  # default_tags are applied to every taggable resource this provider creates.
  # This is enormously useful: it means cost allocation, ownership, and
  # "what is this thing?" are answered without tagging each resource by hand.
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repo        = "DevopsWaf"
    }
  }
}

###############################################################################
# Data sources — read-only lookups of things that already exist
###############################################################################

# Our own account ID and ARN. Used to scope IAM policies and build ARNs
# without hardcoding "609898225411" anywhere.
data "aws_caller_identity" "current" {}

# The region we are actually running in, as AWS reports it.
data "aws_region" "current" {}

# Which Availability Zones are usable in this region right now. We take the
# first N (var.az_count) rather than hardcoding us-east-1a/1b, so this code
# works in any region.
data "aws_availability_zones" "available" {
  state = "available"

  # Local Zones and Wavelength Zones are not normal AZs and will break subnet
  # placement. Filter to real AZs only.
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

###############################################################################
# Locals — computed values used across the other files
###############################################################################

locals {
  # "jollof-run" — the prefix for nearly every resource name.
  name = var.project_name

  # The AZs we will actually use, e.g. ["us-east-1a", "us-east-1b"]
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
}
