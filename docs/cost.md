# Cost — Jollof Run

All prices are **us-east-1, on-demand, August 2026**. Verify against the
[AWS Pricing Calculator](https://calculator.aws) before quoting them anywhere —
AWS changes prices and this file will drift.

---

## Itemised, for the lean build we are actually deploying

| Service | What we run | Unit price | Per hour | Per day | Per 30 days |
|---|---|---|---|---|---|
| **EKS control plane** | 1 cluster | $0.10/hr | $0.100 | $2.40 | **$73.00** |
| **EC2 (worker nodes)** | 2x `t3.small` | $0.0208/hr ea | $0.042 | $1.00 | **$30.00** |
| **NAT Gateway** | 1 gateway | $0.045/hr + $0.045/GB | $0.045 | $1.08 | **$32.85** + data |
| **RDS PostgreSQL** | `db.t3.micro`, single-AZ | $0.018/hr | $0.018 | $0.43 | **$13.00** |
| **RDS storage** | 20 GB gp3 | $0.115/GB-mo | — | $0.08 | **$2.30** |
| **ALB** | 1 load balancer | $0.0225/hr + LCU | $0.023 | $0.54 | **$16.43** + LCU |
| **WAF Web ACL** | 1 ACL | $5.00/mo | — | $0.17 | **$5.00** |
| **WAF rules** | 4 rule groups | $1.00/mo ea | — | $0.13 | **$4.00** |
| **WAF requests** | test traffic only | $0.60/million | — | ~$0.00 | **~$0.01** |
| **KMS** | 1 customer-managed key | $1.00/mo | — | $0.03 | **$1.00** |
| **Secrets Manager** | 1 secret | $0.40/mo | — | $0.01 | **$0.40** |
| **CloudWatch dashboard** | 1 dashboard | $3.00/mo | — | $0.10 | **$3.00** |
| **CloudWatch alarms** | 7 standard alarms | $0.10/mo ea | — | $0.02 | **$0.70** |
| **CloudWatch Logs** | ~1 GB/mo ingest, 7-day retention | $0.50/GB + $0.03/GB-mo | — | $0.02 | **~$0.53** |
| **CloudTrail** | 1 trail, management events | first trail free | — | $0.00 | **$0.00** |
| **S3 (CloudTrail logs)** | ~0.5 GB | $0.023/GB-mo | — | ~$0.00 | **~$0.02** |
| **ECR** | ~1 GB of images | $0.10/GB-mo | — | $0.00 | **$0.10** |
| | | | | | |
| **TOTAL** | | | **~$0.25/hr** | **~$6.00/day** | **~$182/month** |

### The three things that dominate the bill

```
EKS control plane   $73/mo   40%   fixed, charged whether or not pods run
EC2 nodes           $30/mo   16%   scales with node count and size
NAT Gateway         $33/mo   18%   fixed hourly + $0.045 per GB processed
                    -------
                    $136/mo  74% of total
```

Everything else combined is under $50/month.

---

## Free-tier reality check

If your account is inside its first 12 months you get some relief, but **not on
the expensive parts**:

| Covered by free tier | Not covered |
|---|---|
| 750 hr/mo `db.t3.micro` RDS | EKS control plane — **never free** |
| 750 hr/mo `t2.micro`/`t3.micro` EC2 (we use `t3.small`) | NAT Gateway — **never free** |
| 20 GB RDS storage | ALB (only 750 hr of *Classic* LB is free) |
| 5 GB S3 | WAF |
| 10 CloudWatch alarms, 5 GB logs | |
| 1 CloudTrail management trail | |

**Do not assume free tier saves you here.** EKS + NAT + ALB alone is ~$122/month
regardless of account age.

---

## How to minimise cost

### 1. Destroy every day (biggest lever by far)

The single most effective habit. `terraform apply` takes ~20 minutes, so a
build-test-destroy cycle costs about **$2–3** rather than $182/month.

```bash
cd terraform
terraform destroy -auto-approve
```

### 2. Scale the node group to zero overnight

Cheaper than a full destroy if you want to keep the cluster and RDS state, but
you still pay the $2.40/day control plane and $1.08/day NAT.

```bash
aws eks update-nodegroup-config \
  --cluster-name jollof-run \
  --nodegroup-name jollof-run-nodes \
  --scaling-config minSize=0,maxSize=2,desiredSize=0 \
  --region us-east-1
```

Bring it back with `desiredSize=2`.

### 3. Stop RDS temporarily

RDS can be stopped for up to 7 days; AWS restarts it automatically after that.
You still pay for storage while stopped.

```bash
aws rds stop-db-instance --db-instance-identifier jollof-run-db --region us-east-1
```

### 4. Delete the Ingress before destroying

The ALB is created by the controller, **not** by Terraform, so
`terraform destroy` does not know about it. Deleting the Ingress first lets the
controller clean up the ALB and its security groups properly. Skip this and you
get an orphaned ALB quietly billing you and a VPC that refuses to delete.

```bash
kubectl delete ingress jollof-run-ingress -n jollof-run
```

### 5. Keep log retention short

All log groups are created with `retention_in_days = 7`. The default is
"never expire", which quietly accumulates cost forever.

### 6. Set a billing alarm on day one

Before Phase 2, in the console: **Billing -> Budgets -> Create budget ->
Cost budget -> $20/month -> alert at 80%**. Do this even though we have
CloudWatch alarms later; a budget alarm catches things Terraform never created.

---

## Teardown order

`terraform destroy` alone is **not** sufficient. Follow this order:

```bash
# 1. Kubernetes-created AWS resources first (ALB + its security groups)
kubectl delete ingress jollof-run-ingress -n jollof-run
kubectl delete namespace jollof-run
#    wait ~2 minutes and confirm the ALB is gone:
aws elbv2 describe-load-balancers --region us-east-1 \
  --query "LoadBalancers[].LoadBalancerName" --output table

# 2. Uninstall Helm-managed controllers
helm uninstall aws-load-balancer-controller -n kube-system
helm uninstall csi-secrets-store -n kube-system

# 3. Now Terraform can tear down cleanly
cd terraform
terraform destroy
```

### What survives `terraform destroy` and needs manual cleanup

| Resource | Why it survives | How to clean up |
|---|---|---|
| **ALB + its security groups** | Created by the ALB controller, not Terraform | Delete the Ingress first (step 1). If orphaned: delete the LB in EC2 console, then its `k8s-*` security groups. |
| **ECR images** | Nothing — `ecr.tf` sets `force_delete = true` for this learning project | None. (A real registry would leave this off, and then you would need `aws ecr delete-repository --force`.) |
| **CloudTrail S3 objects** | Nothing — `cloudtrail.tf` sets `force_destroy = true`, which deletes all objects *and all versions* | None. **Never set this on a real audit bucket** — the point of an audit log is surviving the person deleting it. |
| **CloudWatch log groups** | Container Insights creates `/aws/containerinsights/*` groups outside Terraform | `aws logs delete-log-group --log-group-name /aws/containerinsights/jollof-run/application` |
| **KMS key** | Enters a 7–30 day pending-deletion window, not deleted immediately | Nothing to do — it stops billing at deletion. You cannot cancel the $1/mo until the window ends. |
| **RDS final snapshot** | Only if you change `skip_final_snapshot` to `false` | Delete the snapshot in the RDS console. |

### Verify you are actually at zero

```bash
# Any load balancers left?
aws elbv2 describe-load-balancers --region us-east-1 --query "LoadBalancers[].LoadBalancerArn"

# Any running instances?
aws ec2 describe-instances --region us-east-1 \
  --filters Name=instance-state-name,Values=running \
  --query "Reservations[].Instances[].InstanceId"

# Any EKS clusters?
aws eks list-clusters --region us-east-1

# Any RDS instances?
aws rds describe-db-instances --region us-east-1 --query "DBInstances[].DBInstanceIdentifier"

# Any NAT gateways? (these bill by the hour and are easy to miss)
aws ec2 describe-nat-gateways --region us-east-1 \
  --filter Name=state,Values=available --query "NatGateways[].NatGatewayId"
```

All five should return empty. Then check **Billing -> Bills** the next morning —
AWS billing data lags by several hours, so same-day zero is not proof.
