<div align="center">

# 🍚 Jollof Run

**Production-shaped Kubernetes on AWS EKS.**

A Nigerian food-delivery platform used as a vehicle for the infrastructure
underneath it — flat Terraform, per-pod IAM, and a CI/CD pipeline that
authenticates to AWS without a single stored credential.

[![CI/CD](https://github.com/dollarsmoney/Kubernetes-Deployment-Order-Hub/actions/workflows/ci-cd.yml/badge.svg)](https://github.com/dollarsmoney/Kubernetes-Deployment-Order-Hub/actions/workflows/ci-cd.yml)
![Terraform](https://img.shields.io/badge/Terraform-1.9-7B42BC?logo=terraform&logoColor=white)
![EKS](https://img.shields.io/badge/AWS%20EKS-1.34-FF9900?logo=amazonwebservices&logoColor=white)
![Tests](https://img.shields.io/badge/tests-90%20passing-3FB950)
![License](https://img.shields.io/badge/license-MIT-blue)

</div>

---

## What this actually is

A deliberately small application carrying a deliberately realistic
infrastructure. The React storefront and the FastAPI service are not the point.
**The point is the path a request takes**, and being able to explain every hop:

```
                              INTERNET
                                 │
                                 ▼
                    ┌────────────────────────┐
                    │        AWS WAF         │  SQLi · XSS · known-bad inputs
                    │  rules by priority     │  rate limit 2000/5min/IP
                    └───────────┬────────────┘
                    BLOCK ◄─────┤ 403 returned HERE — the ALB, the cluster
                                │ and the app never see the request
                        ALLOW   ▼
                    ┌────────────────────────┐
                    │        AWS ALB         │  public subnets, 2 AZs
                    └───────────┬────────────┘
                                │  created BY the AWS Load Balancer Controller
                                │  FROM kubernetes/ingress.yaml
                                ▼
        ══════════ PRIVATE SUBNETS (no route to the IGW) ══════════
                                │
                    ┌───────────▼────────────┐
                    │  frontend-service      │  ClusterIP
                    │  → frontend pods       │  nginx + built React
                    └───────────┬────────────┘
                                │  nginx proxies /api/* SERVER-SIDE
                                ▼
                    ┌────────────────────────┐
                    │  backend-service       │  ClusterIP, NO Ingress rule.
                    │  → backend pods        │  Not reachable from the internet.
                    └───────────┬────────────┘
                                │  ServiceAccount → OIDC → STS → IAM
                                ▼
                    ┌────────────────────────┐
                    │  AWS Secrets Manager   │  KMS-encrypted
                    │  mounted via CSI driver│  never in etcd, YAML or Git
                    └───────────┬────────────┘
                                ▼
                    ┌────────────────────────┐
                    │  RDS PostgreSQL        │  private · encrypted
                    │  SG allows 5432 from   │  no public IP
                    │  the node SG ONLY      │
                    └────────────────────────┘
```

📖 **[docs/architecture.md](docs/architecture.md)** — every layer, explained
🛠 **[docs/runbook.md](docs/runbook.md)** — every command, expected output, and failure mode
💰 **[docs/cost.md](docs/cost.md)** — itemised pricing and teardown

---

## What's actually in here

Most EKS portfolio repos ship two Deployments with `replicas: 1`, no probes,
and credentials in a Secret. These are the things that make this one different,
and every one of them is a file you can open:

| | Where | Why it matters |
|---|---|---|
| **Zero-downtime rollouts** | `maxUnavailable: 0`, `maxSurge: 1` | Ready replicas never dip below 2 during a deploy |
| **Three distinct probes** | `startup` / `liveness` / `readiness` | Liveness deliberately does **not** touch the database — otherwise one RDS blip restarts every pod at once and a hiccup becomes an outage |
| **`preStop` sleep** | `frontend-deployment.yaml` | Closes the endpoint-deregistration race that causes 502s on *every* rolling update |
| **Topology spread** | both Deployments | Stops the scheduler putting both replicas on one node, which would make the replica count decorative |
| **Per-pod IAM (IRSA)** | `serviceaccount.yaml` + `iam.tf` | The backend can read **one** secret and decrypt with **one** key. The frontend has no AWS identity at all |
| **Hardened containers** | `runAsNonRoot`, `readOnlyRootFilesystem`, `drop: [ALL]`, `automountServiceAccountToken: false` | Enforced again at the namespace by `restricted` Pod Security Admission |
| **Keyless CI → AWS** | `github-oidc.tf` | No `AWS_ACCESS_KEY_ID` anywhere. Nothing to rotate, nothing to leak |
| **Namespace-scoped CD** | `AmazonEKSEditPolicy` on one namespace | A compromised workflow cannot read `kube-system` secrets. The pipeline asserts this on every run |
| **Parameterised SQL, proven** | `backend/db.py` + 25 query tests | Injection payloads return **0 rows**, not an error — the value never reaches the SQL parser |

---

## CI/CD

```
 pull_request                        push to main
      │                                    │
      ├────────────────────────────────────┤
      ▼                                    ▼
  ┌────────┐ ┌──────────────┐ ┌───────────────┐ ┌──────────────┐
  │  lint  │ │ test-backend │ │ test-frontend │ │ scan-source  │
  │ ruff   │ │ pytest + a   │ │ vitest + RTL  │ │ trivy fs     │
  │ eslint │ │ REAL postgres│ │ 38 tests      │ │ trivy config │
  │ tf fmt │ │ 52 tests     │ │               │ │              │
  │hadolint│ └──────┬───────┘ └───────┬───────┘ └──────┬───────┘
  │shellchk│        │                 │                │
  │kubeconf│        │                 │                │
  └────┬───┘        │                 │                │
       └────────────┴────────┬────────┴────────────────┘
                             ▼
                    ┌─────────────────┐
                    │   build-scan    │  docker build · trivy image
                    │   → SARIF       │  → GitHub Security tab
                    └────────┬────────┘
                             ▼        main only · packages: write
                    ┌─────────────────┐
                    │      push       │  GITHUB_TOKEN → GHCR
                    └────────┬────────┘  :$GITHUB_SHA + :latest
                             ▼        main only · id-token: write
                    ┌─────────────────┐
                    │     deploy      │  OIDC → EKS
                    └────────┬────────┘  set image · rollout status · auto-undo
                             ▼        always() · failures + main deploys
                    ┌─────────────────┐
                    │     notify      │  → Slack incoming webhook
                    └─────────────────┘  names the stage that broke
```

### Registry

One registry, **GHCR**, and it is what EKS pulls from:

```
ghcr.io/dollarsmoney/kubernetes-deployment-order-hub/backend:<sha>
ghcr.io/dollarsmoney/kubernetes-deployment-order-hub/frontend:<sha>
```

Both packages are **public**, which is load-bearing: it is what lets the nodes
pull anonymously, so there is no `imagePullSecret` and no registry PAT living
in the cluster. Making them private would require exactly that — a long-lived
credential to store and rotate — which is the thing this project is built to
avoid.

Publishing needs no stored credential either: `packages: write` on that one job
lets it use the `GITHUB_TOKEN` GitHub mints for the run and discards after.
Because it touches no AWS, the `push` job does not request `id-token: write` at
all — `deploy` is the only job in the workflow that can obtain an OIDC
assertion.

> The ECR repositories in `terraform/ecr.tf` still exist but no longer receive
> pushes. They are left in place deliberately so the switch is reversible;
> removing them is a separate change, and `terraform apply` after deleting that
> file would destroy the registries and every image in them.

### Repository secrets

| Secret | Used by | Notes |
|---|---|---|
| `SLACK_WEBHOOK_URL` | `notify` | Incoming webhook. The only stored secret in the repo; it can post to one channel and nothing else. The job no-ops with a notice if it is unset, so fork PRs stay green. |

There is no AWS access key and no registry PAT — both are OIDC or per-run tokens.

### The OIDC exchange — no stored credentials

```
GitHub Actions job (permissions: id-token: write)
      │  requests a signed JWT describing itself
      ▼
token.actions.githubusercontent.com   ← registered as an IAM identity provider
      │  sts:AssumeRoleWithWebIdentity
      ▼
IAM trust policy checks BOTH claims:
      aud = sts.amazonaws.com
      sub = repo:dollarsmoney/Kubernetes-Deployment-Order-Hub:ref:refs/heads/main
                                                              ^^^^^^^^^^^^^^^^^^
      not `:*` — a fork, a PR, or any other branch is refused by STS
      ▼
~1 hour of temporary credentials, scoped to one namespace on one cluster
```

**This repository is public**, so fork PRs are a real threat model. Three
independent guards, any one of which would be sufficient:

1. `permissions` are declared **per job** — only `deploy` ever requests
   `id-token: write`, and only `push` ever requests `packages: write`
2. Both are gated on `github.event_name == 'push' && github.ref == 'refs/heads/main'`,
   which a `pull_request` event cannot satisfy
3. The IAM trust policy pins the branch ref, so a leaked token from anywhere
   else fails at STS

The `deploy` job then **asserts its own least privilege** before touching
anything — if `kubectl auth can-i delete pods -n kube-system` ever succeeds,
the build fails on the spot.

---

## Repository layout

```
├── .github/workflows/ci-cd.yml   the pipeline above
├── terraform/                    flat, one file per concern — no modules
│   ├── vpc.tf                    VPC · subnets · IGW · NAT · route tables
│   ├── eks.tf                    cluster · node group · OIDC provider · addons
│   ├── iam.tf                    cluster/node roles · ALB controller · backend IRSA
│   ├── github-oidc.tf            keyless CI access + namespace-scoped EKS entry
│   ├── rds.tf                    private PostgreSQL · SG scoped to the node SG
│   ├── secrets.tf                KMS CMK · generated password · Secrets Manager
│   ├── waf.tf                    WAFv2 Web ACL · managed rule groups · logging
│   ├── cloudwatch.tf             dashboard · 8 alarms · SNS
│   └── cloudtrail.tf             multi-region trail → S3 + Logs Insights
├── kubernetes/                   plain manifests, no Helm chart of our own
├── frontend/                     React 18 · Vite · Tailwind · Framer Motion
├── backend/                      FastAPI · SQLAlchemy · pytest
├── scripts/                      build-and-push · verify · waf-test · generate-traffic
└── docs/                         architecture · runbook · cost
```

---

## Run it locally

Nothing below touches AWS. **Cost: $0.**

```bash
git clone https://github.com/dollarsmoney/Kubernetes-Deployment-Order-Hub.git
cd Kubernetes-Deployment-Order-Hub
docker compose up --build
```

- **http://localhost:8080** — the storefront
- **http://localhost:8000/docs** — the generated API reference

The homepage shows a **"Live from API"** badge bottom-left when the full chain
is working, and **"Demo data"** when the backend is unreachable. That badge is
deliberate instrumentation, not decoration — it turns an invisible integration
into something you can point at.

Try it: `docker compose stop backend-service`, reload, watch it flip to amber.

### Prove the injection defence, with no WAF in front of it

```bash
curl -s "localhost:8080/api/restaurants?search=%27%20OR%201%3D1--" | python -m json.tool
curl -s "localhost:8080/api/foods" | python -m json.tool | grep -c '"id"'
```

Zero results and 30 dishes still present. The payload is searched for as
literal text; it never reaches the SQL parser. **WAF is defence in depth —
parameterisation is the control.**

---

## Tests

**90 tests.** Run them the same way CI does:

```bash
# Backend — needs PostgreSQL (docker compose up -d postgres)
pip install -r backend/requirements-dev.txt
DATABASE_URL=postgresql+psycopg2://jollofadmin:localdev@localhost:5432/jollofrun \
  pytest backend

# Frontend
npm --prefix frontend ci
npm --prefix frontend run lint
npm --prefix frontend run test -- --run
```

| Suite | Count | Covers |
|---|--:|---|
| `test_credentials.py` | 12 | Resolution order · the refuse-to-start path · URL encoding of generated passwords |
| `test_queries.py` | 25 | Real SQL against real PostgreSQL · 8 injection payloads returning 0 rows |
| `test_api.py` | 15 | HTTP contract · 422 before the handler runs · injection over the wire |
| `frontend` | 38 | Relative-URL contract · fallback behaviour · scene structure |

Backend integration tests run against a **real `postgres:16-alpine`**, never
SQLite — `db.py` uses `ILIKE` and `CAST(:x AS TEXT)`, so a SQLite run would pass
while proving nothing.

---

## Deploy to AWS

⚠️ **Not free tier.** EKS control plane ($73/mo), NAT Gateway ($33/mo) and ALB
($16/mo) are never free at any account age. **≈ $6/day** all in.

Follow **[docs/runbook.md](docs/runbook.md)** — it builds the stack in stages so
you can look at each layer before the next one sits on top of it. Each phase has
exact commands, expected output, a hands-on exercise, and a common-errors table.

```bash
cd terraform && terraform init && terraform apply     # ~25 min
```

### Tear down — order matters

```bash
kubectl delete ingress jollof-run-ingress -n jollof-run   # ALB first!
kubectl delete namespace jollof-run
helm uninstall aws-load-balancer-controller -n kube-system
cd terraform && terraform destroy
```

Terraform did not create the ALB — the controller did — so it cannot delete it.
Skip step one and you get an orphaned load balancer quietly billing you and a
VPC that refuses to delete. Full checklist in [docs/cost.md](docs/cost.md).

---

## Known limitations

Stated plainly, because a portfolio that only lists strengths is not credible:

- **Terraform state is local.** `provider.tf` explains the trade-off and shows
  the S3 + KMS + DynamoDB backend a real team would use. CI therefore runs
  `fmt -check` and `validate` only — never `plan` or `apply`.
- **HTTP, not HTTPS.** ACM needs a domain you control; you cannot get a public
  certificate for an ALB's own DNS name. `ingress.yaml` carries the exact
  annotations to add once a domain exists.
- **One NAT Gateway, not one per AZ.** Saves ~$33/month; costs AZ-b its egress
  if AZ-a fails. A deliberate learning-build choice, flagged in `variables.tf`.
- **The generated DB password reaches `terraform.tfstate`.** It never touches
  source, `.env`, YAML, or a container image — but state records every managed
  value, which is exactly why state is gitignored and why remote state matters.
- **`t3.small` caps at 11 pods/node.** The workload needs ~18 across two nodes.
  It fits, but tightly; `t3.medium` if anything sits `Pending`.

---

## Licence & attribution

MIT. Brand name, logo, copy, illustrations and implementation are original to
this project. The hero street scene is hand-authored SVG, not traced from any
existing artwork. Food photography is hotlinked from
[Unsplash](https://unsplash.com) under the Unsplash Licence.

Not affiliated with, and not a clone of, any existing delivery service.
