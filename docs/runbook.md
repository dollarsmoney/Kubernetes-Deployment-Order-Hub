# Runbook — Jollof Run

Every command, what you should see, and what to do when you do not see it.

> **Cost reminder:** the full stack is ~$6/day. `terraform destroy` when you
> finish each session. See [`cost.md`](cost.md).

---

## Staged applies — how we build this incrementally

The whole stack is written. To build it *phase by phase* we use `-target`,
which restricts an apply to a resource and everything it depends on.

> **`-target` is normally a code smell.** HashiCorp's own docs call it an
> escape hatch for recovering from mistakes, because it applies a *partial*
> configuration and the next full plan may show surprising drift.
>
> We use it here for one reason: **pedagogy**. It lets you build the VPC, look
> at it, understand it, and only then create a cluster inside it. In a real
> pipeline you would run a plain `terraform apply` and get everything at once.
> Know that the shortcut exists and know why it is a shortcut.

If you would rather build everything in one go, skip straight to
[Phase 10](#phase-10--cloudwatch) and run a plain `terraform apply`.

---

## Phase 2 — Terraform + VPC

### Build

```bash
cd terraform
terraform init
terraform fmt -check      # should print nothing
terraform validate        # "Success! The configuration is valid."

# Plan only the network layer
terraform plan \
  -target=aws_route_table_association.public \
  -target=aws_route_table_association.private \
  -target=aws_flow_log.main

terraform apply \
  -target=aws_route_table_association.public \
  -target=aws_route_table_association.private \
  -target=aws_flow_log.main
```

`-target=aws_flow_log.main` pulls in the KMS key and its IAM role automatically
— Terraform always includes a target's dependencies.

### What you should see

~20 resources created in about 2–3 minutes. The NAT Gateway is the slow one.

### Verify

```bash
VPC=$(terraform output -raw vpc_id)

# 4 subnets, 2 public + 2 private, across 2 AZs
aws ec2 describe-subnets --region us-east-1 \
  --filters Name=vpc-id,Values=$VPC \
  --query 'Subnets[].{Name:Tags[?Key==`Name`]|[0].Value,CIDR:CidrBlock,AZ:AvailabilityZone,PublicIP:MapPublicIpOnLaunch}' \
  --output table

# The load-bearing ALB discovery tag must be on the PUBLIC subnets
aws ec2 describe-subnets --region us-east-1 \
  --filters Name=vpc-id,Values=$VPC Name=tag:kubernetes.io/role/elb,Values=1 \
  --query 'length(Subnets)'
# -> 2      (if this is 0, Phase 6 WILL fail)

# The public route table has a route to the IGW
aws ec2 describe-route-tables --region us-east-1 \
  --filters Name=vpc-id,Values=$VPC \
  --query 'RouteTables[].{Name:Tags[?Key==`Name`]|[0].Value,Routes:Routes[].{Dest:DestinationCidrBlock,GW:GatewayId,NAT:NatGatewayId}}' \
  --output json
```

Expected: the public table shows `0.0.0.0/0 -> igw-…`, each private table
shows `0.0.0.0/0 -> nat-…`.

### Hands-on

Draw the diagram from memory, then check yourself against
[`architecture.md` §3](architecture.md). Specifically be able to say:

1. What makes a subnet "public"? *(a route table entry, nothing else)*
2. Why is the NAT Gateway in a **public** subnet if it serves private ones?
3. How will a public ALB reach a pod that has no internet route?

### Common errors

| Error | Cause | Fix |
|---|---|---|
| `AddressLimitExceeded` | 5 EIPs already allocated in the region | Release unassociated EIPs in the EC2 console |
| `VpcLimitExceeded` | 5 VPCs already exist | Delete an unused VPC, or request a quota increase |
| `InvalidParameterValue: CIDR overlaps` | `vpc_cidr` collides with an existing VPC you peer with | Change `vpc_cidr` |
| Apply hangs ~10 min on NAT | Normal. NAT Gateways take 2–5 minutes | Wait |

---

## Phase 3 — Docker application (local)

**No AWS involved. Nothing billable.** Prove the containers work before adding
Kubernetes to the list of things that could be broken.

### Build and run each image by hand first

```bash
cd /c/Users/USER/Desktop/DevopsWaf

# Frontend — multi-stage: node builds, nginx serves
docker build -t jollof-frontend:local ./frontend
docker run --rm -p 8080:8080 jollof-frontend:local
# -> http://localhost:8080  (the site renders with the "Demo data" badge,
#    because no backend is running yet — that is correct)
# Ctrl-C to stop

# Backend — needs a database, so it will fail to start on its own.
# That failure IS the lesson:
docker run --rm -p 8000:8000 jollof-backend:local 2>&1 | head -20
```

You should see the backend refuse to start with:

```
RuntimeError: No database credentials found. Expected one of:
  1. a CSI-mounted secret at /mnt/secrets-store/db-credentials  (EKS, preferred)
  2. DB_SECRET_NAME set, for a direct Secrets Manager fetch
  3. DATABASE_URL set, for local docker-compose only
Refusing to start with a guessed default.
```

**That is a feature.** `backend/db.py` has no default connection string, so it
can never silently connect to the wrong database or fall back to a hardcoded
credential.

### Now run the whole stack

```bash
docker compose up --build
```

### What you should see

```
jollof-postgres  | database system is ready to accept connections
jollof-backend   | INFO  jollof.db  Reading database credentials from ...
jollof-backend   | INFO  jollof.db  Applying schema and seed data
jollof-backend   | INFO  jollof.api Database ready
jollof-backend   | INFO  Uvicorn running on http://0.0.0.0:8000
jollof-frontend  | ... /docker-entrypoint.sh: Configuration complete; ready
```

- **http://localhost:8080** — the full homepage, with a green **"Live from
  API"** badge bottom-left
- **http://localhost:8000/docs** — FastAPI's generated API docs

### Hands-on

```bash
# The API directly
curl -s localhost:8000/health | python -m json.tool
curl -s localhost:8000/restaurants | python -m json.tool | head -30

# Through nginx's proxy — the SAME path the browser uses
curl -s localhost:8080/api/restaurants | python -m json.tool | head -20

# Prove parameterization works. This searches for a restaurant whose NAME
# literally contains the payload. It returns an empty list. It does not
# error, and it certainly does not drop a table.
curl -s "localhost:8080/api/restaurants?search=%27%20OR%201%3D1--" | python -m json.tool

# Image sizes — see what multi-stage bought you
docker images | grep -E 'jollof|REPOSITORY'
```

Expect the frontend at ~50 MB and the backend at ~250 MB. A single-stage
frontend build would be ~450 MB.

### Common errors

| Symptom | Cause | Fix |
|---|---|---|
| `port is already allocated` | Something else on 8080/8000/5432 | Change the host port, or stop the other process |
| Backend restarts in a loop | Postgres not ready yet | The `depends_on: condition: service_healthy` handles this; give it 20s |
| Frontend shows "Demo data" | nginx cannot reach `backend-service` | `docker compose logs backend-service` |
| `exec format error` | Built on Apple Silicon for arm64 | `docker build --platform linux/amd64` |
| Blank page, 404s on `/assets/*` | Stale build | `docker compose build --no-cache frontend` |

### Clean up

```bash
docker compose down -v      # -v also removes the postgres volume
```

---

## Phase 4 — EKS

```bash
cd terraform
terraform apply \
  -target=aws_eks_addon.coredns \
  -target=aws_eks_addon.kube_proxy \
  -target=aws_eks_addon.vpc_cni \
  -target=aws_ecr_repository.app
```

**This takes 15–20 minutes.** The control plane alone is ~10 minutes. Go and
make tea; it is not stuck.

### Connect kubectl

```bash
aws eks update-kubeconfig --region us-east-1 --name jollof-run

kubectl get nodes -o wide
kubectl get pods -A
```

### What you should see

```
NAME                         STATUS   ROLES    AGE   VERSION
ip-10-0-34-xxx.ec2.internal  Ready    <none>   3m    v1.34.x
ip-10-0-51-xxx.ec2.internal  Ready    <none>   3m    v1.34.x
```

Two nodes, `Ready`, with **10.0.32.x / 10.0.48.x** addresses — i.e. in the
**private** subnets. In `kube-system`: `aws-node` (the CNI), `kube-proxy`, and
`coredns`, all Running.

### Hands-on — see the layers

```bash
# The control plane is AWS-managed; you get an endpoint, not a server
kubectl cluster-info

# Nodes are ordinary EC2 instances that you own
aws ec2 describe-instances --region us-east-1 \
  --filters "Name=tag:eks:cluster-name,Values=jollof-run" \
  --query 'Reservations[].Instances[].{ID:InstanceId,Type:InstanceType,AZ:Placement.AvailabilityZone,PrivateIP:PrivateIpAddress,PublicIP:PublicIpAddress}' \
  --output table
# PublicIP is empty for every node. They are private. That is the point.

# How many pods fit on a node? (the t3.small = 11 limit from variables.tf)
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.allocatable.pods}{"\n"}{end}'

# The OIDC issuer — the foundation of IRSA in Phase 8
aws eks describe-cluster --name jollof-run --region us-east-1 \
  --query 'cluster.identity.oidc.issuer' --output text
```

### Common errors

| Error | Cause | Fix |
|---|---|---|
| `error: You must be logged in to the server (Unauthorized)` | kubeconfig points elsewhere, or a different IAM identity | Re-run `update-kubeconfig`; confirm `aws sts get-caller-identity` matches the cluster creator |
| Node group creation times out (~20 min) | Nodes cannot reach the EKS API — usually NAT or route-table trouble | Check the private route table has `0.0.0.0/0 -> nat-…` |
| Nodes `NotReady` | The CNI addon failed | `kubectl -n kube-system logs -l k8s-app=aws-node --tail=50` |
| `coredns` pods `Pending` | No nodes yet — the addon raced the node group | The `depends_on` prevents this; if it happens, `kubectl -n kube-system rollout restart deploy/coredns` |

---

## Phase 5 — Deployments and Services

### Push the images

```bash
cd /c/Users/USER/Desktop/DevopsWaf
./scripts/build-and-push.sh
```

### Deploy

```bash
kubectl apply -f kubernetes/namespace.yaml
kubectl apply -f kubernetes/frontend-deployment.yaml
kubectl apply -f kubernetes/frontend-service.yaml

# The backend needs Secrets Manager (Phase 8) to start, so leave it for now.
kubectl get pods -n jollof-run -w
```

### What you should see

```
NAME                        READY   STATUS    RESTARTS   AGE
frontend-7d4b8c9f5-abcde    1/1     Running   0          45s
frontend-7d4b8c9f5-fghij    1/1     Running   0          45s
```

### Hands-on 1 — the controller hierarchy

```bash
kubectl get deployment,replicaset,pod -n jollof-run -l app=frontend
```

One Deployment → one ReplicaSet → two Pods. Now trace the ownership:

```bash
POD=$(kubectl get pod -n jollof-run -l app=frontend -o jsonpath='{.items[0].metadata.name}')
kubectl get pod $POD -n jollof-run -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}{"\n"}'
# -> ReplicaSet/frontend-7d4b8c9f5
```

### Hands-on 2 — self-healing

```bash
# Terminal 1
kubectl get pods -n jollof-run -w

# Terminal 2
kubectl delete pod $POD -n jollof-run
```

Watch terminal 1. Within milliseconds:

```
frontend-7d4b8c9f5-abcde   1/1   Terminating         0     5m
frontend-7d4b8c9f5-klmno   0/1   Pending             0     0s
frontend-7d4b8c9f5-klmno   0/1   ContainerCreating   0     0s
frontend-7d4b8c9f5-klmno   1/1   Running             0     3s
```

**Note the new pod has a different name.** Kubernetes did not restart your pod
— the ReplicaSet noticed the count was 1 instead of 2 and created a brand new
one. Pods are cattle.

```bash
kubectl get events -n jollof-run --sort-by=.lastTimestamp | tail -10
```

### Hands-on 3 — rolling update

```bash
# Terminal 1
kubectl get pods -n jollof-run -w

# Terminal 2 — force a rollout
kubectl rollout restart deployment/frontend -n jollof-run
kubectl rollout status deployment/frontend -n jollof-run

# Two ReplicaSets now exist: the old one at 0, the new one at 2
kubectl get rs -n jollof-run

# Which is why this works
kubectl rollout history deployment/frontend -n jollof-run
kubectl rollout undo deployment/frontend -n jollof-run
```

With `maxUnavailable: 0`, ready replicas never drop below 2. That is zero-
downtime deployment, in one line of YAML.

### Hands-on 4 — service discovery

```bash
kubectl apply -f kubernetes/backend-service.yaml

kubectl run -it --rm dnstest --image=busybox:1.36 --restart=Never -n jollof-run -- sh
```

Inside the pod:

```sh
cat /etc/resolv.conf          # note the search path
nslookup frontend-service     # short name resolves
nslookup frontend-service.jollof-run.svc.cluster.local
wget -qO- frontend-service/healthz    # -> ok
exit
```

```bash
# A Service with no matching pods has no endpoints — this is the #1
# cause of "my Service returns 503"
kubectl get endpoints -n jollof-run
```

### Common errors

| Symptom | Cause | Fix |
|---|---|---|
| `ImagePullBackOff` | ECR repo empty, wrong account ID, or node role lacks ECR read | `kubectl describe pod <pod>`; re-run `build-and-push.sh` |
| `CrashLoopBackOff` | App exits on start | `kubectl logs <pod> --previous` |
| `Pending`, "Too many pods" | t3.small's 11-pod cap | `terraform apply -var="node_instance_type=t3.medium"` |
| `Pending`, "Insufficient cpu" | Requests exceed node capacity | Lower `resources.requests` or add a node |
| Service has no ENDPOINTS | Selector does not match pod labels | Compare `spec.selector` with `template.metadata.labels` |
| `403` from nginx | `runAsUser` does not match the image's user | Must be `101` for nginx-unprivileged |

---

## Phase 6 — AWS Load Balancer Controller + Ingress

### Create the IRSA role

```bash
cd terraform
terraform apply -target=aws_iam_role_policy_attachment.alb_controller
terraform output -raw alb_controller_role_arn
```

### Install the controller

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

CLUSTER=jollof-run
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
VPC_ID=$(terraform -chdir=terraform output -raw vpc_id)

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --version 1.17.1 \
  --set clusterName=$CLUSTER \
  --set region=us-east-1 \
  --set vpcId=$VPC_ID \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=arn:aws:iam::${ACCOUNT}:role/jollof-run-alb-controller-irsa" \
  --set replicaCount=2

kubectl -n kube-system rollout status deploy/aws-load-balancer-controller
```

> **Version note:** chart `1.17.1` installs controller `v2.17.1`. Chart 3.x /
> controller v3.x also exists and requires applying CRDs separately. The v2
> line has far more matching documentation, which is why we pin it.

### Create the Ingress

```bash
kubectl apply -f kubernetes/ingress.yaml

# Watch it appear. Takes 2-3 minutes.
kubectl get ingress -n jollof-run -w
```

### What you should see

```
NAME                 CLASS   HOSTS   ADDRESS                                          PORTS
jollof-run-ingress   alb     *       k8s-jollofr-jollofr-abc123-456.us-east-1.elb.amazonaws.com   80
```

```bash
ALB=$(kubectl get ingress jollof-run-ingress -n jollof-run \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -I http://$ALB
open http://$ALB     # or paste into a browser
```

**The site is now live on the internet.**

### Hands-on — trace the request

```bash
# 1. The Ingress object (inert data)
kubectl get ingress jollof-run-ingress -n jollof-run -o yaml | head -40

# 2. The controller that acted on it
kubectl logs -n kube-system deploy/aws-load-balancer-controller --tail=40

# 3. The ALB it created
aws elbv2 describe-load-balancers --region us-east-1 \
  --query "LoadBalancers[?contains(LoadBalancerName,'k8s-jollof')].{Name:LoadBalancerName,DNS:DNSName,Scheme:Scheme,State:State.Code}" \
  --output table

# 4. The target group, registering POD IPs (not node IPs) because target-type: ip
TG=$(aws elbv2 describe-target-groups --region us-east-1 \
      --query "TargetGroups[?contains(TargetGroupName,'k8s-jollof')].TargetGroupArn" --output text | head -1)
aws elbv2 describe-target-health --target-group-arn $TG --region us-east-1 \
  --query 'TargetHealthDescriptions[].{Target:Target.Id,Port:Target.Port,Health:TargetHealth.State}' --output table

# 5. Compare with the pod IPs — they match
kubectl get pods -n jollof-run -l app=frontend -o wide
```

### Save the ALB ARN suffix for Phase 10

```bash
ALB_SUFFIX=$(aws elbv2 describe-load-balancers --region us-east-1 \
  --query "LoadBalancers[?contains(LoadBalancerName,'k8s-jollof')].LoadBalancerArn" \
  --output text | cut -d'/' -f2-)
echo $ALB_SUFFIX
```

### Common errors

| Error | Cause | Fix |
|---|---|---|
| ADDRESS stays empty forever | Controller cannot find subnets | Confirm the `kubernetes.io/role/elb=1` tag: `aws ec2 describe-subnets --filters Name=tag:kubernetes.io/role/elb,Values=1` |
| `couldn't auto-discover subnets` | Same as above | Re-apply `vpc.tf` |
| `AccessDenied` in controller logs | IRSA role/trust policy wrong | Check the `sub` condition is `system:serviceaccount:kube-system:aws-load-balancer-controller` |
| `no ingress class` | `ingressClassName` missing | It is set to `alb` in our manifest — confirm it applied |
| Targets `unhealthy` | ALB health check path wrong | Must be `/healthz`; check `frontend-service.yaml` annotations |
| `502 Bad Gateway` | No healthy targets | `kubectl get pods -n jollof-run` |

---

## Phase 7 — RDS

```bash
cd terraform
terraform apply -target=aws_db_instance.main
```

**Takes 8–12 minutes.**

```bash
terraform output rds_endpoint
terraform output rds_address
```

### Verify it is private

```bash
# No public IP
aws rds describe-db-instances --db-instance-identifier jollof-run-db \
  --region us-east-1 \
  --query 'DBInstances[0].{Public:PubliclyAccessible,Encrypted:StorageEncrypted,MultiAZ:MultiAZ,Subnets:DBSubnetGroup.Subnets[].SubnetIdentifier}' \
  --output json

# The security group allows 5432 from ONE source SG, not a CIDR
aws ec2 describe-security-groups --region us-east-1 \
  --filters Name=group-name,Values=jollof-run-rds-sg \
  --query 'SecurityGroups[0].IpPermissions' --output json
```

Expect `IpRanges: []` and a populated `UserIdGroupPairs` — the source is a
security group, not an IP range.

### Hands-on — prove you cannot reach it

```bash
RDS=$(terraform output -raw rds_address)

# From your laptop: this should HANG then time out.
# A timeout is correct. "Connection refused" would mean it is routable.
timeout 10 bash -c "cat < /dev/null > /dev/tcp/$RDS/5432" \
  && echo "REACHABLE - that is wrong!" \
  || echo "Timed out - correct, RDS is private"

# From inside the cluster: this connects.
kubectl run -it --rm pgtest --image=postgres:16-alpine --restart=Never \
  -n jollof-run -- sh -c "nc -zv -w 5 $RDS 5432"
# -> open
```

That contrast is the whole lesson: **same hostname, same port, different
network position.**

### Common errors

| Error | Cause | Fix |
|---|---|---|
| `InvalidParameterCombination: Cannot find version 16.4` | Version retired | `aws rds describe-db-engine-versions --engine postgres --query 'DBEngineVersions[].EngineVersion'` then set `db_engine_version` |
| `DBSubnetGroupDoesNotCoverEnoughAZs` | Fewer than 2 AZs | `az_count` must be ≥ 2 |
| Timeout from inside the cluster too | SG source wrong | Confirm `referenced_security_group_id` is the EKS **cluster** SG |
| `InvalidParameterValue` on the password | Special character RDS rejects | `override_special` in `secrets.tf` already excludes them |

---

## Phase 8 — Secrets Manager + IRSA

### Create the secret and the IRSA role

```bash
cd terraform
terraform apply \
  -target=aws_secretsmanager_secret_version.db \
  -target=aws_iam_role_policy_attachment.backend_secrets

terraform output secret_name
terraform output backend_irsa_role_arn
```

### Install the Secrets Store CSI Driver + AWS provider

```bash
helm repo add secrets-store-csi-driver \
  https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm repo update

helm install csi-secrets-store \
  secrets-store-csi-driver/secrets-store-csi-driver \
  --namespace kube-system \
  --set syncSecret.enabled=false \
  --set enableSecretRotation=true

kubectl apply -f https://raw.githubusercontent.com/aws/secrets-store-csi-driver-provider-aws/main/deployment/aws-provider-installer.yaml

# Both are DaemonSets — one pod per node
kubectl get pods -n kube-system -l 'app in (secrets-store-csi-driver,csi-secrets-store-provider-aws)'
```

### Deploy the backend

```bash
kubectl apply -f kubernetes/serviceaccount.yaml
kubectl apply -f kubernetes/secretproviderclass.yaml
kubectl apply -f kubernetes/backend-deployment.yaml
kubectl apply -f kubernetes/backend-service.yaml

kubectl get pods -n jollof-run -w
```

### What you should see

```
backend-6f8d9c7b4-pqrst    1/1   Running   0   90s
backend-6f8d9c7b4-uvwxy    1/1   Running   0   90s
```

```bash
kubectl logs -n jollof-run -l app=backend --tail=20
```

```
INFO  jollof.db   Reading database credentials from CSI mount: /mnt/secrets-store/db-credentials
INFO  jollof.db   Database engine initialised
INFO  jollof.db   Applying schema and seed data
INFO  jollof.db   Schema ready
INFO  jollof.api  Database ready
INFO  Uvicorn running on http://0.0.0.0:8000
```

Reload the site — the badge should now read **"Live from API"** in green.

### Hands-on — walk the IRSA chain

```bash
POD=$(kubectl get pod -n jollof-run -l app=backend -o jsonpath='{.items[0].metadata.name}')

# 1. The SA carries the role annotation
kubectl get sa backend-sa -n jollof-run -o yaml | grep role-arn

# 2. The EKS webhook injected these — you never wrote them
kubectl exec -n jollof-run $POD -- printenv | grep AWS
#   AWS_ROLE_ARN=arn:aws:iam::609898225411:role/jollof-run-backend-irsa
#   AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/secrets/eks.amazonaws.com/serviceaccount/token
#   AWS_REGION=us-east-1
# Note what is ABSENT: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY

# 3. The projected token is a JWT. Decode its claims:
kubectl exec -n jollof-run $POD -- \
  cat /var/run/secrets/eks.amazonaws.com/serviceaccount/token \
  | cut -d. -f2 | base64 -d 2>/dev/null | python -m json.tool
# Look at:  "sub": "system:serviceaccount:jollof-run:backend-sa"
#           "aud": ["sts.amazonaws.com"]
# Those two claims are exactly what the IAM trust policy checks.

# 4. The secret is mounted as a file
kubectl exec -n jollof-run $POD -- ls -la /mnt/secrets-store/

# 5. Confirm the KEYS without printing the values
kubectl exec -n jollof-run $POD -- cat /mnt/secrets-store/db-credentials \
  | python -c "import json,sys; print(sorted(json.load(sys.stdin)))"
# -> ['dbname', 'engine', 'host', 'password', 'port', 'username']
```

### Hands-on — prove least privilege

```bash
# The role can read ITS secret. It cannot read any other.
aws iam get-role-policy --role-name jollof-run-backend-irsa \
  --policy-name x 2>/dev/null || \
aws iam list-attached-role-policies --role-name jollof-run-backend-irsa

POLICY=$(aws iam list-policies --scope Local \
  --query "Policies[?PolicyName=='jollof-run-backend-secrets-policy'].Arn" --output text)
VER=$(aws iam get-policy --policy-arn $POLICY --query 'Policy.DefaultVersionId' --output text)
aws iam get-policy-version --policy-arn $POLICY --version-id $VER \
  --query 'PolicyVersion.Document' --output json | python -m json.tool
```

Read the `Resource` fields. They are **specific ARNs**, not `"*"`. That is the
difference between least privilege and a shrug.

### Common errors

| Error | Cause | Fix |
|---|---|---|
| Pod stuck `ContainerCreating`, `failed to mount` | CSI driver or AWS provider not installed | `kubectl get pods -n kube-system \| grep -i secret` |
| `AccessDeniedException ... secretsmanager:GetSecretValue` | Trust policy `sub` mismatch | Must be exactly `system:serviceaccount:jollof-run:backend-sa` |
| `AccessDeniedException ... kms:Decrypt` | Missing KMS permission | `secrets.tf` encrypts with a CMK; the policy needs `kms:Decrypt` on that key |
| `ResourceNotFoundException` | Secret name mismatch | `terraform output -raw secret_name` must equal `objectName` in the SecretProviderClass |
| Pod runs but uses the NODE role | `serviceAccountName` missing from the Deployment | It is set; confirm with `kubectl get pod $POD -o yaml \| grep serviceAccount` |
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | OIDC provider not registered, or `aud` wrong | `aws iam list-open-id-connect-providers` |

---

## Phase 9 — AWS WAF

### Create the Web ACL

```bash
cd terraform
terraform apply -target=aws_wafv2_web_acl_logging_configuration.main
WAF_ARN=$(terraform output -raw waf_web_acl_arn)
echo $WAF_ARN
```

### Attach it to the ALB

Uncomment the annotation in [`kubernetes/ingress.yaml`](../kubernetes/ingress.yaml)
and paste the ARN, or do it in one command:

```bash
kubectl annotate ingress jollof-run-ingress -n jollof-run \
  alb.ingress.kubernetes.io/wafv2-acl-arn="$WAF_ARN" --overwrite

kubectl logs -n kube-system deploy/aws-load-balancer-controller --tail=20 | grep -i waf
```

Also edit the YAML so the change survives a re-apply — an annotation set only
with `kubectl annotate` is lost the next time you `kubectl apply -f`.

### Verify the association

```bash
ALB_ARN=$(aws elbv2 describe-load-balancers --region us-east-1 \
  --query "LoadBalancers[?contains(LoadBalancerName,'k8s-jollof')].LoadBalancerArn" --output text)

aws wafv2 get-web-acl-for-resource --resource-arn "$ALB_ARN" --region us-east-1 \
  --query 'WebACL.Name' --output text
# -> jollof-run-web-acl
```

### Test it

```bash
./scripts/waf-test.sh
```

Expected: everything in Part 1 returns **200**, everything in Parts 2 and 3
returns **403**.

### See what was blocked

```bash
# Live tail of blocked requests
aws logs tail aws-waf-logs-jollof-run --region us-east-1 --since 10m --format short

# Which rule fired, per request
aws logs filter-log-events --log-group-name aws-waf-logs-jollof-run \
  --region us-east-1 --start-time $(( ($(date +%s) - 600) * 1000 )) \
  --query 'events[].message' --output text \
  | python -c "
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try: e = json.loads(line)
    except: continue
    print(e.get('action'), '|', e.get('terminatingRuleId'), '|', e['httpRequest']['uri'][:70])
"
```

In the console: **WAF → Web ACLs → jollof-run-web-acl → Sampled requests**
shows the actual payloads, which is indispensable when debugging a false
positive.

### Explain it

| Concept | Meaning |
|---|---|
| **Web ACL** | The container. Attaches to one or more ALBs/API Gateways. |
| **Rule** | One condition + one action. Evaluated in priority order. |
| **Managed rule group** | AWS-maintained bundle of rules. You cannot see the regexes; AWS updates them. |
| **Priority** | Lower number = evaluated first. The first *terminating* action wins. |
| **Allow** | Terminating. Stops evaluation, forwards the request. |
| **Block** | Terminating. Returns 403 immediately. |
| **Count** | **Not** terminating. Records a match and carries on. This is how you test a rule safely. |
| **Default action** | What happens when nothing matched. Ours is Allow (blocklist model). |
| **Metrics** | `AllowedRequests`, `BlockedRequests`, `CountedRequests` in `AWS/WAFV2`. |

### And say this out loud

> WAF is a pattern matcher. It blocks *recognisable* attacks and buys time, but
> it can be evaded with novel encoding and it cannot see an attack that does not
> look like one. `backend/db.py` uses bound parameters, so the database never
> parses user input as SQL — turn WAF off entirely and the application is still
> not injectable. WAF is defence in depth. Parameterization is the control.

### Common errors

| Symptom | Cause | Fix |
|---|---|---|
| Injection payloads return 200 | WAF not associated | `aws wafv2 get-web-acl-for-resource` |
| Everything returns 403 | Default action set to Block, or a broad false positive | Check `default_action` is `allow`; read Sampled requests |
| Legitimate POSTs blocked | `SizeRestrictions_BODY` | Add a `rule_action_override` to `count {}` |
| `WAFInvalidParameterException` on the log group | Name lacks the `aws-waf-logs-` prefix | It is correct in `waf.tf` |
| Controller error after annotating | Malformed ARN | Re-copy from `terraform output -raw waf_web_acl_arn` |

---

## Phase 10 — CloudWatch

### Apply everything, now with ALB alarms

```bash
cd terraform
ALB_SUFFIX=$(aws elbv2 describe-load-balancers --region us-east-1 \
  --query "LoadBalancers[?contains(LoadBalancerName,'k8s-jollof')].LoadBalancerArn" \
  --output text | cut -d'/' -f2-)

terraform apply \
  -var="alb_arn_suffix=$ALB_SUFFIX" \
  -var="alert_email=itojedollars3@gmail.com"
```

**Check your email and confirm the SNS subscription.** Until you click that
link, no alarm will ever reach you.

```bash
aws sns list-subscriptions-by-topic \
  --topic-arn $(terraform output -raw sns_topic_arn) --region us-east-1 \
  --query 'Subscriptions[].SubscriptionArn'
# "PendingConfirmation" means you have not clicked yet
```

### The four concepts

| | What it is | Where |
|---|---|---|
| **Metric** | A time series of numbers | `AWS/ApplicationELB`, `AWS/RDS`, `AWS/WAFV2`, `ContainerInsights` |
| **Log** | Timestamped text lines, in log groups/streams | `/aws/containerinsights/…`, `aws-waf-logs-…` |
| **Alarm** | Watches one metric, changes state on a threshold | 8 of them, prefix `jollof-run-` |
| **Dashboard** | A saved arrangement of widgets | `jollof-run-overview` |

### Exercise — generate traffic and watch it land

```bash
terraform output -raw dashboard_url    # open this in a browser

./scripts/generate-traffic.sh 300 6    # 5 minutes at ~6 req/s
```

Wait 3–5 minutes (CloudWatch is not real-time), then refresh the dashboard.

**What you should see:** `RequestCount` rises to a plateau; `HTTPCode_Target_2XX`
tracks just below it; a small steady `4XX` line from the deliberate `/9999`
requests; `TargetResponseTime` p95 under ~100 ms.

```bash
# The same data from the CLI
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB --metric-name RequestCount \
  --dimensions Name=LoadBalancer,Value=$ALB_SUFFIX \
  --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time   $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 --statistics Sum --region us-east-1 \
  --query 'sort_by(Datapoints,&Timestamp)[].[Timestamp,Sum]' --output table
```

### Exercise — logs

```bash
# Pod logs, direct from Kubernetes
kubectl logs -n jollof-run -l app=backend --tail=30

# The same lines, shipped to CloudWatch by Container Insights
aws logs tail /aws/containerinsights/jollof-run/application \
  --region us-east-1 --since 15m --format short | head -30
```

Then **Console → CloudWatch → Logs Insights**, log group
`/aws/containerinsights/jollof-run/application`:

```
fields @timestamp, log
| filter kubernetes.container_name = "backend"
| parse log /status=(?<status>\d+)/
| stats count() as requests by status
| sort requests desc
```

```
fields @timestamp, log
| filter kubernetes.container_name = "backend"
| parse log /duration_ms=(?<ms>[\d.]+)/
| stats avg(ms) as avg_ms, pct(ms, 95) as p95_ms, max(ms) as max_ms by bin(1m)
```

### Exercise — trigger an alarm on purpose

```bash
# Temporarily make the RDS CPU alarm impossible to satisfy
aws cloudwatch put-metric-alarm \
  --alarm-name jollof-run-rds-cpu-high \
  --namespace AWS/RDS --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=jollof-run-db \
  --statistic Average --period 60 --evaluation-periods 1 \
  --threshold 0.1 --comparison-operator GreaterThanThreshold \
  --alarm-actions $(terraform output -raw sns_topic_arn) \
  --region us-east-1

# Watch it flip (2-3 minutes)
watch -n 30 'aws cloudwatch describe-alarms --alarm-names jollof-run-rds-cpu-high \
  --region us-east-1 --query "MetricAlarms[0].[StateValue,StateReason]" --output text'
```

You should get an email. Then put the real threshold back:

```bash
terraform apply -var="alb_arn_suffix=$ALB_SUFFIX" -var="alert_email=itojedollars3@gmail.com"
```

You can also flip an alarm instantly without waiting for data:

```bash
aws cloudwatch set-alarm-state --alarm-name jollof-run-alb-5xx \
  --state-value ALARM --state-reason "manual test" --region us-east-1
```

### Common errors

| Symptom | Cause | Fix |
|---|---|---|
| Dashboard widgets empty | No traffic, or metrics lag | Run `generate-traffic.sh`, wait 5 min |
| EKS widgets blank | Container Insights not running | `kubectl get pods -n amazon-cloudwatch` |
| Alarms stuck `INSUFFICIENT_DATA` | Metric not published yet | Normal for ~15 min after creation |
| No alarm emails | SNS subscription unconfirmed | Check your inbox and spam folder |
| `Invalid dimension` on ALB alarms | Wrong `alb_arn_suffix` | It must start with `app/` and have no leading slash |

---

## Phase 11 — CloudTrail

CloudTrail was created by the full apply in Phase 10.

```bash
aws cloudtrail get-trail-status --name jollof-run-trail --region us-east-1
aws s3 ls s3://$(terraform -chdir=terraform output -raw cloudtrail_bucket)/AWSLogs/ --recursive | head
```

### The anatomy of an event

| Field | Answers |
|---|---|
| `eventTime` | **When** (always UTC) |
| `eventName` | **What** — the API call, e.g. `AuthorizeSecurityGroupIngress` |
| `eventSource` | **Which service** — `ec2.amazonaws.com`, `rds.amazonaws.com` |
| `userIdentity` | **Who** — type, ARN, `userName`, and `sessionContext` if a role was assumed |
| `sourceIPAddress` | **From where** — your IP, or an AWS service name |
| `awsRegion` | **Which region** |
| `requestParameters` | **Exactly what was asked for** — the ports, CIDRs, resource IDs |
| `responseElements` | What AWS returned |
| `errorCode` | Present when the call was denied — this is how you find someone probing permissions |

### Exercise — do something, then find it

```bash
# ---- ACTION 1: modify a security group -------------------------------------
SG=$(aws ec2 describe-security-groups --region us-east-1 \
      --filters Name=group-name,Values=jollof-run-rds-sg \
      --query 'SecurityGroups[0].GroupId' --output text)

# Add a harmless tag (a WRITE event, but changes no access)
aws ec2 create-tags --resources $SG \
  --tags Key=CloudTrailDemo,Value=phase11 --region us-east-1

# ---- ACTION 2: read the secret ---------------------------------------------
aws secretsmanager get-secret-value \
  --secret-id jollof-run/db-credentials --region us-east-1 \
  --query 'ARN' --output text

# ---- ACTION 3: a deliberately DENIED call ----------------------------------
# This should fail. The failure is the interesting part.
aws iam create-user --user-name cloudtrail-demo-should-fail 2>&1 | head -3
```

**Wait 5–15 minutes.** CloudTrail delivery is not instant.

### Find them — three ways

**1. The console.** CloudTrail → Event history → filter by Event name.

**2. `lookup-events` (fastest, last 90 days, management events):**

```bash
# Everything you did, most recent first
aws cloudtrail lookup-events --region us-east-1 \
  --lookup-attributes AttributeKey=Username,AttributeValue=DevopsClass \
  --max-results 10 \
  --query 'Events[].{Time:EventTime,Name:EventName,Source:EventSource}' --output table

# One specific call, with full detail
aws cloudtrail lookup-events --region us-east-1 \
  --lookup-attributes AttributeKey=EventName,AttributeValue=CreateTags \
  --max-results 1 --query 'Events[0].CloudTrailEvent' --output text \
  | python -m json.tool
```

Read that JSON carefully. Find `userIdentity.arn`, `sourceIPAddress` (your
public IP), `eventTime`, and `requestParameters` showing the exact tag.

**3. Logs Insights** — Console → CloudWatch → Logs Insights, log group
`/aws/cloudtrail/jollof-run`:

```
fields @timestamp, eventName, userIdentity.arn, sourceIPAddress, awsRegion
| filter eventName like /SecurityGroup/
| sort @timestamp desc
| limit 20
```

```
# Who read the database credentials?
fields @timestamp, userIdentity.arn, sourceIPAddress, requestParameters.secretId
| filter eventName = "GetSecretValue"
| sort @timestamp desc
```

```
# Denied calls — a permissions probe looks exactly like this
fields @timestamp, eventName, errorCode, userIdentity.arn, sourceIPAddress
| filter ispresent(errorCode)
| stats count() by errorCode, eventName
| sort count desc
```

```
# Every write action, by actor
fields @timestamp, eventName, userIdentity.arn
| filter readOnly = false
| stats count() as actions by userIdentity.arn
| sort actions desc
```

### The alarm should have fired too

`cloudtrail.tf` defines a metric filter on security-group events plus an alarm.

```bash
aws cloudwatch describe-alarms --alarm-names jollof-run-security-group-changed \
  --region us-east-1 --query 'MetricAlarms[0].{State:StateValue,Reason:StateReason}'
```

This is the pattern worth remembering: **log pattern → metric → alarm →
notification.** It turns CloudTrail from a forensic archive into a detective
control.

### CloudWatch vs CloudTrail

```
"The API is 500ing and latency spiked at 14:20"     -> CLOUDWATCH  (what)
"Who changed the RDS security group at 14:19?"      -> CLOUDTRAIL  (who)
```

Not substitutes. CloudWatch says the system is sick; CloudTrail names the
change that made it sick.

### Common errors

| Symptom | Cause | Fix |
|---|---|---|
| No events found | Delivery lag | Wait 15 minutes |
| Empty S3 bucket | Bucket policy wrong | `aws cloudtrail get-trail-status` shows delivery errors |
| Logs Insights returns nothing | Querying the S3 copy, not the CloudWatch one | Select log group `/aws/cloudtrail/jollof-run` |
| `InsufficientS3BucketPolicyException` | Policy missing the `aws:SourceArn` condition | Already handled in `cloudtrail.tf` |
| Data events missing | We log management events only | Deliberate — data events cost $0.10/100k |

---

## Phase 12 — Security testing

```bash
./scripts/verify.sh
```

Runs all ten tests and prints a pass/fail summary. Individual walkthroughs for
each are in the phases above:

| # | Test | Phase |
|---|---|---|
| 1 | Website loads | 6 |
| 2 | Frontend reaches backend | 8 |
| 3 | Backend reaches RDS | 8 |
| 4 | Internet cannot reach RDS | 7 |
| 5 | Backend reads Secrets Manager | 8 |
| 6 | Pod self-healing | 5 |
| 7 | WAF blocks SQL injection | 9 |
| 8 | CloudWatch metrics flowing | 10 |
| 9 | Alarm triggers | 10 |
| 10 | Action visible in CloudTrail | 11 |

---

## Phase 13 — Teardown

**Order matters.** `terraform destroy` alone will fail or leave billable
resources behind.

```bash
# 1. Kubernetes-created AWS resources FIRST.
#    Terraform did not create the ALB and cannot delete it.
kubectl delete ingress jollof-run-ingress -n jollof-run
kubectl delete namespace jollof-run

#    Wait ~2 minutes, then confirm the ALB is gone
aws elbv2 describe-load-balancers --region us-east-1 \
  --query "LoadBalancers[?contains(LoadBalancerName,'k8s-jollof')].LoadBalancerName" --output text
#    -> should be empty

# 2. Helm-managed controllers
helm uninstall aws-load-balancer-controller -n kube-system
helm uninstall csi-secrets-store -n kube-system

# 3. Now Terraform
cd terraform
terraform destroy
```

**Takes 15–25 minutes.** RDS and the EKS control plane are the slow ones.

### Verify you are at zero

```bash
aws elbv2 describe-load-balancers --region us-east-1 --query 'LoadBalancers[].LoadBalancerArn'
aws ec2 describe-instances --region us-east-1 \
  --filters Name=instance-state-name,Values=running --query 'Reservations[].Instances[].InstanceId'
aws eks list-clusters --region us-east-1
aws rds describe-db-instances --region us-east-1 --query 'DBInstances[].DBInstanceIdentifier'
aws ec2 describe-nat-gateways --region us-east-1 \
  --filter Name=state,Values=available --query 'NatGateways[].NatGatewayId'
aws ec2 describe-addresses --region us-east-1 --query 'Addresses[].PublicIp'
```

All six should be empty.

### What survives on purpose

| Resource | Why | Action |
|---|---|---|
| **KMS key** | 7-day mandatory pending-deletion window | Nothing. $1/mo until it elapses; it cannot be cancelled. |
| **CloudWatch log groups** | Container Insights creates some outside Terraform | `aws logs describe-log-groups --log-group-name-prefix /aws/containerinsights` then delete |
| **Orphaned ALB + `k8s-*` SGs** | Only if you skipped step 1 | Delete the LB in the EC2 console, then its security groups |

If `terraform destroy` hangs deleting the VPC, it is almost always an
orphaned ALB security group holding an ENI. Go back and do step 1.

### Rebuild tomorrow

```bash
cd terraform && terraform apply     # ~25 minutes, everything at once
```

Then Phases 5, 6, 8, 9 again for the Kubernetes side — or just:

```bash
./scripts/build-and-push.sh
kubectl apply -f kubernetes/
```
