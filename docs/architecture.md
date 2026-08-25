# Jollof Run — Architecture

> *"Your jollof, running to you."*
> A Nigerian food-delivery platform running on AWS EKS, used as a vehicle for
> learning Kubernetes, Terraform, and AWS security/observability primitives.

---

## 1. The one-paragraph version

A React single-page app and a FastAPI microservice run as pods on an **EKS**
cluster spread across two Availability Zones. Public traffic hits an **AWS WAF**
Web ACL, passes to an **Application Load Balancer** that the **AWS Load Balancer
Controller** created from a Kubernetes **Ingress** object, and lands on the
frontend pods. The frontend's nginx reverse-proxies `/api/*` to the backend over
cluster-internal DNS. The backend obtains its database credentials from **AWS
Secrets Manager** via the **Secrets Store CSI Driver**, authenticating with an
**IAM role assumed through IRSA** — no password exists in Git, YAML, env files,
or application code. It then queries a **private RDS PostgreSQL** instance that
is unreachable from the internet. **KMS** encrypts the secret and the database
volume. **CloudWatch** answers *what is happening*; **CloudTrail** answers
*who did what*.

---

## 2. Request path — the diagram you should be able to draw from memory

```
                              INTERNET
                                 |
                                 |  http://<alb-dns-name>/
                                 v
                        +--------------------+
                        |     AWS WAF        |   Web ACL, REGIONAL scope
                        |  +--------------+  |   - CommonRuleSet      (p1)
                        |  | rule eval    |  |   - SQLiRuleSet        (p2)
                        |  | by priority  |  |   - KnownBadInputs     (p3)
                        |  +--------------+  |   - RateLimit 2000/5m  (p4)
                        +---------+----------+
                       BLOCK <----+  403 returned here. The request never
                                  |  reaches the ALB, the cluster, or the app.
                          ALLOW   v
                        +--------------------+
                        |       AWS ALB      |   internet-facing, in the
                        |   (Layer 7 / HTTP) |   PUBLIC subnets, 2 AZs
                        +---------+----------+
                                  |  ALB listener rules were written by...
                                  v
                     +--------------------------+
                     |  AWS Load Balancer Ctlr  |  a pod in kube-system that
                     |  (watches the K8s API)   |  turns Ingress objects into
                     +---------+----------------+  real AWS load balancers
                               | reconciles
                               v
                     +--------------------------+
                     |   Kubernetes Ingress     |  kubernetes/ingress.yaml
                     |   host/path routing      |  "/" -> frontend-service:80
                     +---------+----------------+
                               |  target-type: ip  -> ALB targets pod IPs direct
                               v
        =============== PRIVATE SUBNETS (no route to IGW) ================
                               |
                     +---------v----------+
                     |  frontend-service  |  ClusterIP  (Service)
                     +---------+----------+
                               v
                     +--------------------+
                     |   Frontend Pods    |  replicas: 2   nginx + built React
                     |   +--------------+ |
                     |   | nginx proxy  | |  location /api/ {
                     |   |   /api/*     | |    proxy_pass http://backend-service
                     |   +------+-------+ |                 .jollof-run.svc
                     +----------+---------+                 .cluster.local:8000;
                                |                         }
                                v
                     +--------------------+
                     |  backend-service   |  ClusterIP - NOT exposed to the
                     +---------+----------+  internet, no Ingress rule at all
                               v
                     +--------------------+
                     |   Backend Pods     |  replicas: 2   FastAPI + uvicorn
                     |   serviceAccount:  |
                     |     backend-sa ----+--+
                     +---------+----------+  |  IRSA: projected SA token
                               |             |  exchanged with AWS STS for
                               |             v  temporary IAM credentials
                               |   +----------------------+
                               |   |  AWS Secrets Manager |  jollof-run/db
                               |   |  (KMS-encrypted)     |  {username,password,
                               |   +----------+-----------+   host,port,dbname}
                               |              | mounted at
                               |              | /mnt/secrets-store/db-credentials
                               |<-------------+ by Secrets Store CSI Driver
                               |
                               |  psycopg2 -> TCP 5432
                               v
                     +--------------------+
                     |  RDS PostgreSQL    |  db.t3.micro, private subnets,
                     |  publicly_         |  storage_encrypted = true (KMS),
                     |  accessible=false  |  SG allows 5432 from NODE SG ONLY
                     +--------------------+
```

---

## 3. Network layering — why each subnet exists

```
Internet
   |
   +--> Internet Gateway --> PUBLIC subnets  (10.0.0.0/20, 10.0.16.0/20)
   |                          - the ALB lives here (needs a public IP)
   |                          - the NAT Gateway lives here
   |
   |                              | outbound only
   |                              v
   +------------------------  PRIVATE subnets (10.0.32.0/20, 10.0.48.0/20)
                                  - EKS worker nodes live here
                                  - RDS lives here
                                  - NO route from the internet inward
```

**The rule to internalise:** a *public* subnet is simply one whose route table
has `0.0.0.0/0 -> igw-xxxx`. A *private* subnet's default route points at a NAT
Gateway instead. NAT is one-directional — nodes can pull container images from
ECR and call AWS APIs, but nothing on the internet can open a connection inward.

**Why the ALB can still reach private pods:** the ALB has network interfaces in
the public subnets, but it routes *inside the VPC* to pod IPs in the private
subnets. VPC-internal traffic doesn't need a public route. That is the entire
trick.

**Why RDS is unreachable even from a compromised laptop:** it has no public IP
(`publicly_accessible = false`), sits in private subnets, and its security group
permits inbound 5432 **only from the EKS node security group** — a source-SG
reference, not a CIDR. There is no `0.0.0.0/0 -> 5432` rule anywhere.

**AZ spread:** two AZs (`us-east-1a`, `us-east-1b`). The ALB requires at least
two subnets in different AZs. We run **one** NAT Gateway (in AZ-a) rather than
one per AZ — that saves ~$33/month at the cost of an AZ-a NAT outage taking out
AZ-b's egress. A production build would run one per AZ; know the trade-off.

---

## 4. Component glossary — say these out loud in an interview

### Kubernetes

| Thing | What it actually is |
|---|---|
| **Pod** | The smallest deployable unit: one or more containers sharing a network namespace and IP. Mortal — never created directly in production. |
| **ReplicaSet** | A controller whose only job is "keep exactly N pods matching this label selector alive". |
| **Deployment** | A controller that manages ReplicaSets, giving you rolling updates and rollback. You write Deployments; it writes ReplicaSets; they write Pods. |
| **Service** | A stable virtual IP + DNS name in front of an ever-changing set of pod IPs. `ClusterIP` = internal only. Solves "pods die and get new IPs". |
| **Namespace** | A logical partition of the cluster. Ours is `jollof-run`. Also the middle segment of internal DNS names. |
| **Ingress** | An *object* describing HTTP routing rules (host/path -> Service). It is inert data; something must act on it. |
| **Ingress Controller** | The *program* that watches Ingress objects and configures real load balancing. Ours is the AWS Load Balancer Controller. |
| **ServiceAccount** | A pod's identity inside the cluster. With IRSA, also its identity to AWS. |

### The four things people conflate

```
Kubernetes Service        an in-cluster virtual IP. Layer 4. No HTTP awareness.
Kubernetes Ingress        a YAML object. Routing rules. Does nothing by itself.
Ingress Controller        a pod that reads Ingress objects and acts on them.
AWS Load Balancer Ctlr    the specific ingress controller that speaks AWS APIs.
AWS ALB                   the actual managed load balancer AWS bills you for.
```

**The lifecycle:** you `kubectl apply -f ingress.yaml` -> the API server stores
the object -> the ALB Controller pod's watch fires -> the controller calls
`elasticloadbalancing:CreateLoadBalancer`, `CreateTargetGroup`, `CreateRule` ->
AWS provisions an ALB -> the controller writes the ALB's DNS name back into
`status.loadBalancer.ingress` on the Ingress object -> `kubectl get ingress`
shows you an address. Roughly 2-3 minutes.

### AWS

| Thing | Role here |
|---|---|
| **EKS control plane** | AWS-managed API server + etcd + scheduler. You never SSH to it. $0.10/hr. |
| **Managed node group** | EC2 instances AWS registers as workers for you. Ours: 2x t3.small, private subnets. |
| **IRSA** | OIDC federation: the cluster gets an OIDC issuer URL, IAM trusts it, a pod's projected ServiceAccount token is exchanged at STS for temporary IAM credentials. Per-pod IAM without node-wide permissions. |
| **Secrets Manager** | Stores the DB credential JSON, encrypted with our KMS CMK. |
| **Secrets Store CSI Driver** | A DaemonSet that mounts external secrets into pods as files at `volumeMounts` time. |
| **KMS** | One customer-managed key encrypts the secret, the RDS volume, the CloudTrail bucket, and log groups. |
| **WAF** | Layer 7 request inspection in front of the ALB. Managed rule groups evaluated by priority. |
| **CloudWatch** | Metrics, logs, alarms, dashboards. *What is happening?* |
| **CloudTrail** | An audit log of every AWS API call. *Who did what, from where, when?* |

---

## 5. Where the password actually lives

This is the part most portfolio projects get wrong, so be precise about it.

```
random_password resource          generates a 24-char password at apply time
        |
        +--> aws_secretsmanager_secret_version   <- the ONLY place the app reads
        |        (encrypted at rest with our KMS CMK)
        |
        +--> terraform.tfstate                   <- (!) ALSO ends up here
```

**What we achieve:** the password is never in source code, never in a `.env`,
never in a Kubernetes manifest, never in a container image, never in Git.

**What we must be honest about:** Terraform state records every managed value,
including generated passwords. That is why `.gitignore` excludes `*.tfstate` and
`*.tfplan`, and why a real team stores state in an S3 bucket with KMS
encryption, versioning, and a DynamoDB lock table rather than on a laptop. We
use local state for learning simplicity — and we say so, rather than pretending
the problem doesn't exist.

**The runtime path has no password in it at all:**

```
Backend Pod starts
   +-> kubelet sees a `secrets-store.csi.k8s.io` volume
        +-> Secrets Store CSI Driver + AWS provider
             +-> reads the pod's projected ServiceAccount token
                  +-> sts:AssumeRoleWithWebIdentity
                       +-> IAM role  jollof-run-backend-irsa
                            +-> policy allows EXACTLY:
                                  secretsmanager:GetSecretValue on ONE secret ARN
                                  kms:Decrypt                   on ONE key ARN
                                 (never AdministratorAccess, never a wildcard)
                                 +-> credential JSON written to
                                      /mnt/secrets-store/db-credentials
                                      +-> FastAPI reads the file at startup
                                           +-> connects to RDS over 5432
```

---

## 6. Defence in depth — and what WAF is *not*

```
Layer 1  WAF          blocks obvious SQLi/XSS payloads before they reach compute
Layer 2  Network      RDS in private subnets, SG scoped to the node SG
Layer 3  IAM          least-privilege IRSA role, scoped to one secret + one key
Layer 4  Encryption   KMS at rest for RDS, Secrets Manager, logs, CloudTrail S3
Layer 5  Application  parameterized SQL - the ONLY layer that actually makes
                      SQL injection impossible
Layer 6  Audit        CloudTrail records every API call, CloudWatch alarms on
                      anomalies
```

**Say this in the interview:** WAF is a pattern matcher. It blocks *recognisable*
attacks and buys you time, but it can be bypassed with sufficiently novel
encoding, and it cannot see attacks that don't look like attacks. Removing WAF
from a correctly parameterized application changes nothing about that
application's SQL-injection risk. Removing parameterization and relying on WAF
is a vulnerability with a speed bump in front of it. We use SQLAlchemy bound
parameters throughout; WAF is the outer layer, never the control.

---

## 7. Two questions, two services

```
"The API is returning 500s and latency spiked at 14:20."
        +-> CLOUDWATCH   metrics, alarms, dashboards, pod + WAF logs
                         -> TargetResponseTime, HTTPCode_Target_5XX_Count,
                            RDS DatabaseConnections, container logs

"Why did the RDS security group change at 14:19?"
        +-> CLOUDTRAIL   eventTime, eventName=AuthorizeSecurityGroupIngress,
                         eventSource=ec2.amazonaws.com,
                         userIdentity.arn, sourceIPAddress, requestParameters
```

CloudWatch tells you the system is unhealthy. CloudTrail tells you which human
or role made the change that caused it. You need both, and they are not
substitutes.

---

## 8. Build order

| Phase | Deliverable | AWS cost incurred |
|---|---|---|
| 1 | Architecture, repo scaffold, docs | none |
| 2 | Terraform + VPC | ~$1.10/day (NAT) |
| 3 | Docker apps, running locally | none |
| 4 | EKS cluster + node group + ECR | +$3.40/day |
| 5 | Deployments + Services | none |
| 6 | ALB Controller + Ingress | +$0.60/day |
| 7 | RDS PostgreSQL | +$0.60/day |
| 8 | Secrets Manager + IRSA + KMS | +$0.05/day |
| 9 | WAF | +$0.25/day |
| 10 | CloudWatch dashboards + alarms | +$0.10/day |
| 11 | CloudTrail + S3 | +$0.05/day |
| 12 | Security testing | none |
| 13 | README + teardown | none |

Full stack running is roughly **$6/day**. See `docs/cost.md` for the itemised
breakdown and the destroy procedure. The intended pattern for a learning project
is *build -> test -> `terraform destroy` the same day*.
