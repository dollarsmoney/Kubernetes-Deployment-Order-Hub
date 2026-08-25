###############################################################################
# rds.tf — private PostgreSQL
###############################################################################
#
#   Backend Pod (private subnet)
#        |
#        |  TCP 5432
#        v
#   +--------------------------------------------------+
#   |  Security Group: jollof-run-rds-sg                |
#   |  INGRESS: 5432 from the EKS NODE security group   |  <- source is an SG,
#   |           (NOT from a CIDR, NOT from 0.0.0.0/0)   |     not an IP range
#   |  EGRESS : none required                           |
#   +--------------------------------------------------+
#        |
#        v
#   +--------------------------------------------------+
#   |  RDS PostgreSQL  db.t3.micro                      |
#   |  publicly_accessible = false                      |
#   |  storage_encrypted   = true (our KMS CMK)         |
#   |  DB subnet group: the two PRIVATE subnets         |
#   +--------------------------------------------------+
#
# THREE independent things make this database unreachable from the internet.
# Any one of them failing still leaves two:
#   1. No public IP        (publicly_accessible = false)
#   2. No inbound route    (private subnets have no IGW route)
#   3. No permitted source (SG allows only the node SG)
###############################################################################

# -----------------------------------------------------------------------------
# DB SUBNET GROUP — which subnets RDS may place the instance in
# -----------------------------------------------------------------------------
# RDS requires subnets in at least TWO Availability Zones even for a
# single-AZ instance. AWS wants the option to fail the instance over during
# maintenance without asking you first.
#
# We list only PRIVATE subnets. This is the single most important line in the
# file: RDS physically cannot be placed anywhere with an internet route.
# -----------------------------------------------------------------------------

resource "aws_db_subnet_group" "main" {
  name        = "${local.name}-db-subnet-group"
  description = "Private subnets for ${local.name} PostgreSQL"
  subnet_ids  = aws_subnet.private[*].id

  tags = { Name = "${local.name}-db-subnet-group" }
}

# -----------------------------------------------------------------------------
# SECURITY GROUP — a stateful firewall on the database's network interface
# -----------------------------------------------------------------------------

resource "aws_security_group" "rds" {
  name        = "${local.name}-rds-sg"
  description = "Allow PostgreSQL from EKS worker nodes only"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name}-rds-sg" }

  lifecycle {
    # Create the replacement SG before destroying the old one, so a change
    # here does not briefly cut the database off from the cluster.
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# THE INGRESS RULE — note what the source is
# -----------------------------------------------------------------------------
# source_security_group_id, not cidr_blocks.
#
# This means: "allow 5432 from anything whose network interface carries the
# EKS cluster security group." Node IPs change constantly as instances are
# replaced; referencing the SG means the rule never needs updating.
#
# What we deliberately did NOT write:
#
#   cidr_blocks = ["0.0.0.0/0"]      <- the internet. Never.
#   cidr_blocks = [var.vpc_cidr]     <- would also allow the ALB and any
#                                       future workload in the VPC.
#
# EKS attaches the "cluster security group" to every managed node group
# instance automatically, which is why referencing it covers all our nodes.
# -----------------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "rds_from_nodes" {
  security_group_id = aws_security_group.rds.id
  description       = "PostgreSQL from EKS nodes"

  from_port   = 5432
  to_port     = 5432
  ip_protocol = "tcp"

  referenced_security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

# NOTE: there is deliberately NO egress rule.
#
# A brand-new AWS security group has no egress rules at all, and a database
# does not need to initiate outbound connections. Security groups are
# STATEFUL — response traffic to an allowed inbound connection is permitted
# automatically, without any egress rule. This trips people up: they add
# egress "just in case" and widen the surface for no benefit.

# -----------------------------------------------------------------------------
# PARAMETER GROUP — PostgreSQL configuration
# -----------------------------------------------------------------------------
# Not strictly required, but enabling query logging gives Phase 12 something
# real to look at, and forcing SSL is a genuine security control.
# -----------------------------------------------------------------------------

resource "aws_db_parameter_group" "main" {
  name        = "${local.name}-pg16"
  family      = "postgres16"
  description = "${local.name} PostgreSQL parameters"

  # Require TLS for every client connection. psycopg2 negotiates this
  # automatically, so the application needs no change — but a plaintext
  # connection attempt is now refused outright.
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  # Log any statement taking longer than 1 second. Value is milliseconds;
  # -1 disables. Useful for spotting a missing index in Phase 10.
  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  # Log every connection and disconnection. Chatty, but it is how you prove in
  # Phase 12 that connections arrive only from pod IPs.
  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${local.name}-pg16" }
}

# -----------------------------------------------------------------------------
# THE DATABASE INSTANCE
# -----------------------------------------------------------------------------

resource "aws_db_instance" "main" {
  identifier = "${local.name}-db"

  # --- Engine ---------------------------------------------------------------
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  # --- Storage --------------------------------------------------------------
  allocated_storage = var.db_allocated_storage

  # gp3 is cheaper than gp2 at the same performance and is the current default
  # recommendation for small instances.
  storage_type = "gp3"

  # Grow storage automatically up to this ceiling rather than running out of
  # disk at 3am. RDS can only ever grow, never shrink.
  max_allocated_storage = 50

  # -------------------------------------------------------------------------
  # ENCRYPTION AT REST
  # -------------------------------------------------------------------------
  # Encrypts the underlying EBS volumes, automated backups, read replicas, and
  # snapshots. Transparent to the application — no code change, no measurable
  # performance cost.
  #
  # CANNOT BE ENABLED LATER. You cannot turn on encryption for an existing
  # unencrypted instance; you must snapshot, copy the snapshot with encryption,
  # and restore. Get it right the first time.
  # -------------------------------------------------------------------------
  storage_encrypted = true
  kms_key_id        = aws_kms_key.main.arn

  # --- Database and credentials ---------------------------------------------
  db_name  = var.db_name
  username = var.db_username

  # The password comes from random_password, generated at apply time.
  # It is never typed by a human, never committed, and never appears in any
  # variable file. Terraform passes it straight to the RDS API and simultaneously
  # writes it to Secrets Manager (secrets.tf) for the application to read.
  password = random_password.db.result

  # --- Networking -----------------------------------------------------------
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  # THE LINE THAT KEEPS IT OFF THE INTERNET.
  # true would give the instance a public IP and a publicly resolvable
  # endpoint. Even with a restrictive SG, that is a needless exposure.
  publicly_accessible = false

  port = 5432

  parameter_group_name = aws_db_parameter_group.main.name

  # --- Availability ---------------------------------------------------------
  multi_az = var.db_multi_az # false: no standby replica, ~half the cost

  # --- Backups and maintenance ----------------------------------------------
  backup_retention_period = var.db_backup_retention_days
  backup_window           = "03:00-04:00" # UTC
  maintenance_window      = "sun:04:00-sun:05:00"

  # Apply parameter/engine changes immediately instead of waiting for the
  # maintenance window. Convenient while learning; in production this can
  # cause an unplanned restart in the middle of the day.
  apply_immediately = true

  auto_minor_version_upgrade = true

  # --- Observability --------------------------------------------------------
  # Ship PostgreSQL's own logs to CloudWatch Logs so Phase 10 and Phase 12 have
  # something to read. Creates /aws/rds/instance/jollof-run-db/postgresql.
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  # Enhanced Monitoring (OS-level metrics at 1-60s granularity) is deliberately
  # OFF — it needs another IAM role and adds cost. Standard CloudWatch metrics
  # at 60s are plenty for this project.
  monitoring_interval = 0

  # Performance Insights is free for 7 days of retention on t3 instances and is
  # genuinely the best RDS debugging tool AWS ships.
  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  performance_insights_kms_key_id       = aws_kms_key.main.arn

  # --- Teardown behaviour ---------------------------------------------------
  # Both of these are set for a DISPOSABLE learning database.
  # In production: skip_final_snapshot = false, deletion_protection = true.
  skip_final_snapshot = true
  deletion_protection = false

  tags = { Name = "${local.name}-db" }
}
