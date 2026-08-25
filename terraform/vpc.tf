###############################################################################
# vpc.tf — the network everything else sits inside
###############################################################################
#
#   Internet
#      |
#      +--> Internet Gateway --> PUBLIC subnets   10.0.0.0/20, 10.0.16.0/20
#      |                          - ALB (needs a public IP)
#      |                          - NAT Gateway
#      |                              | outbound only
#      |                              v
#      +------------------------  PRIVATE subnets  10.0.32.0/20, 10.0.48.0/20
#                                   - EKS worker nodes
#                                   - RDS
#
# THE ONLY THING that makes a subnet "public" is its route table containing
# 0.0.0.0/0 -> igw-xxxx. There is no is_public flag in AWS. A private subnet's
# default route points at a NAT Gateway instead, which is one-directional:
# instances can reach out, nothing can reach in.
###############################################################################

# -----------------------------------------------------------------------------
# The VPC itself
# -----------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  # Both of these MUST be true for EKS.
  # - enable_dns_support   : the VPC-provided DNS resolver at 169.254.169.253
  #                          works. Without it, CoreDNS cannot resolve anything
  #                          outside the cluster, and nothing can resolve your
  #                          RDS endpoint.
  # - enable_dns_hostnames : instances and VPC endpoints get DNS names. RDS
  #                          endpoints and EKS private endpoints require this.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name}-vpc"
  }
}

# -----------------------------------------------------------------------------
# Internet Gateway — the VPC's door to the internet
# -----------------------------------------------------------------------------
# An IGW is horizontally scaled, redundant, and free. It performs 1:1 NAT for
# instances that have public IPs. Attaching it does NOT by itself make anything
# reachable — a route table still has to point at it.
# -----------------------------------------------------------------------------

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name}-igw"
  }
}

# -----------------------------------------------------------------------------
# PUBLIC subnets — one per AZ
# -----------------------------------------------------------------------------
# cidrsubnet("10.0.0.0/16", 4, 0) = 10.0.0.0/20   (4096 addresses)
# cidrsubnet("10.0.0.0/16", 4, 1) = 10.0.16.0/20
#
# "4" is newbits: we add 4 bits to the /16 prefix, giving /20 subnets.
# Doing the maths in code rather than hardcoding CIDRs means changing
# az_count or vpc_cidr just works.
# -----------------------------------------------------------------------------

resource "aws_subnet" "public" {
  count = var.az_count

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone = local.azs[count.index]

  # Anything launched here gets a public IP automatically. The ALB relies on
  # this behaviour for its network interfaces.
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name}-public-${local.azs[count.index]}"
    Tier = "public"

    # -------------------------------------------------------------------------
    # THESE TWO TAGS ARE LOAD-BEARING. Do not remove them.
    # -------------------------------------------------------------------------
    # The AWS Load Balancer Controller does not read your Terraform. When you
    # create an Ingress, it has to DISCOVER which subnets to put the ALB in.
    # It does that by scanning the VPC for subnets tagged:
    #
    #   kubernetes.io/role/elb = 1           -> "put internet-facing LBs here"
    #   kubernetes.io/cluster/<name> = shared -> "these belong to this cluster"
    #
    # Miss these and Phase 6 fails with the single most-Googled error in this
    # whole project:
    #   "couldn't auto-discover subnets: unable to resolve at least one subnet"
    # -------------------------------------------------------------------------
    "kubernetes.io/role/elb"              = "1"
    "kubernetes.io/cluster/${local.name}" = "shared"
  }
}

# -----------------------------------------------------------------------------
# PRIVATE subnets — one per AZ
# -----------------------------------------------------------------------------
# cidrsubnet("10.0.0.0/16", 4, 2) = 10.0.32.0/20
# cidrsubnet("10.0.0.0/16", 4, 3) = 10.0.48.0/20
#
# Offset by az_count so public and private never overlap.
# -----------------------------------------------------------------------------

resource "aws_subnet" "private" {
  count = var.az_count

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index + var.az_count)
  availability_zone = local.azs[count.index]

  # No public IPs here. This is the whole point.
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name}-private-${local.azs[count.index]}"
    Tier = "private"

    # internal-elb marks these as the place for INTERNAL load balancers.
    # We do not create one, but the controller also uses this tag to
    # understand the cluster's subnet topology, and EKS uses the cluster tag
    # when placing worker-node ENIs.
    "kubernetes.io/role/internal-elb"     = "1"
    "kubernetes.io/cluster/${local.name}" = "shared"
  }
}

# -----------------------------------------------------------------------------
# Elastic IPs for the NAT Gateway(s)
# -----------------------------------------------------------------------------
# A NAT Gateway needs a static public IP. EIPs are free WHILE ATTACHED to a
# running resource and billed (~$3.60/month) while sitting unattached — which
# is why orphaned EIPs from deleted NAT Gateways are a classic surprise on a
# bill. `terraform destroy` releases these correctly.
#
# Default account limit is 5 EIPs per region. If Phase 2 fails with
# AddressLimitExceeded, release unused ones in the EC2 console.
# -----------------------------------------------------------------------------

resource "aws_eip" "nat" {
  count = var.single_nat_gateway ? 1 : var.az_count

  domain = "vpc"

  tags = {
    Name = "${local.name}-nat-eip-${count.index}"
  }

  # The EIP is useless until the IGW exists; being explicit avoids a race
  # where Terraform tries to create the NAT Gateway before the VPC has a
  # route to the internet.
  depends_on = [aws_internet_gateway.main]
}

# -----------------------------------------------------------------------------
# NAT Gateway(s) — outbound-only internet for private subnets
# -----------------------------------------------------------------------------
# The NAT Gateway lives in a PUBLIC subnet (it needs to reach the IGW) but
# serves PRIVATE subnets. That inversion trips everyone up once.
#
# Traffic flow:
#   private instance -> NAT Gateway (public subnet) -> IGW -> internet
#   internet -> ??? -> nothing. There is no inbound path. That is the point.
#
# COST: ~$0.045/hour ($33/month) PLUS $0.045 per GB processed. This is the
# second most expensive thing in the project after the EKS control plane, and
# the most common thing people forget to destroy.
# -----------------------------------------------------------------------------

resource "aws_nat_gateway" "main" {
  count = var.single_nat_gateway ? 1 : var.az_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${local.name}-nat-${count.index}"
  }

  depends_on = [aws_internet_gateway.main]
}

# -----------------------------------------------------------------------------
# PUBLIC route table — this is what makes a public subnet public
# -----------------------------------------------------------------------------

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  # "Anything not destined for inside this VPC, send to the Internet Gateway."
  #
  # Note there is no route for 10.0.0.0/16 here. AWS adds an implicit "local"
  # route for the VPC CIDR to every route table, and you cannot remove it.
  # That implicit route is why the ALB in a public subnet can reach pods in a
  # private subnet without any internet involvement at all.
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.name}-public-rt"
  }
}

# One route table shared by all public subnets — they all want identical
# routing, so there is no reason to duplicate it.
resource "aws_route_table_association" "public" {
  count = var.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# -----------------------------------------------------------------------------
# PRIVATE route tables — one PER AZ
# -----------------------------------------------------------------------------
# Why one per AZ instead of one shared table? Because with
# single_nat_gateway = false each AZ must route to its OWN NAT Gateway.
# Building it this way from the start means flipping that variable is a
# one-line change rather than a refactor.
#
# With single_nat_gateway = true, all of them point at the same NAT — which is
# exactly the cross-AZ dependency described in variables.tf.
# -----------------------------------------------------------------------------

resource "aws_route_table" "private" {
  count = var.az_count

  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    # index 0 when sharing one NAT, otherwise this AZ's own NAT.
    nat_gateway_id = var.single_nat_gateway ? aws_nat_gateway.main[0].id : aws_nat_gateway.main[count.index].id
  }

  tags = {
    Name = "${local.name}-private-rt-${local.azs[count.index]}"
  }
}

resource "aws_route_table_association" "private" {
  count = var.az_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# -----------------------------------------------------------------------------
# VPC Flow Logs — a record of every connection accepted or rejected
# -----------------------------------------------------------------------------
# Not in your original requirement list, but it is three resources and it is
# what turns "I think RDS is unreachable from the internet" into "here is the
# log proving nothing ever connected". Genuinely useful in Phase 12.
#
# Cost: log ingestion only, a few cents at our traffic levels.
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/${local.name}/flow-logs"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.main.arn

  tags = {
    Name = "${local.name}-flow-logs"
  }

  # The KMS key policy must allow CloudWatch Logs before the log group can be
  # created with encryption enabled.
  depends_on = [aws_kms_key.main]
}

resource "aws_flow_log" "main" {
  vpc_id          = aws_vpc.main.id
  traffic_type    = "ALL" # ACCEPT, REJECT, or ALL
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs.arn

  tags = {
    Name = "${local.name}-flow-log"
  }
}
