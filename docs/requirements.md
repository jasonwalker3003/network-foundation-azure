# Requirements: Network foundation in Azure

**Project:** network-foundation-azure · **Author:** Jason Walker · **Date:** 2026-11-21 · **Status:** Agreed before build

## 1. The business problem

A company is moving its first applications to Azure. Before any application is deployed, the security team wants a network foundation that:

- exposes nothing to the internet except through controlled entry points
- keeps dev and prod apart, so a mistake in dev can never affect production
- gives administrators access to servers without opening SSH ports to the internet
- records network traffic, allowed and denied, for audits and troubleshooting

Every later project (load balancers, containers, databases) will be built on top of this network, so it must be repeatable and cheap to keep running.

## 2. Scope

**In scope:** a hub network for shared services, two spoke networks (dev and prod), subnets and traffic rules for three tiers, secure admin access, private access to one platform service (Key Vault), traffic logging, and a CI/CD pipeline that deploys all of it through pull requests.

**Out of scope (for this project):** spoke-to-spoke routing through a firewall, outbound internet for VMs (NAT gateway), hybrid connectivity (VPN or ExpressRoute), DNS for on-premises names, and real application workloads. These are listed under "What I'd do in production" in the README.

## 3. Functional requirements

| ID | Requirement |
| --- | --- |
| FR-1 | Dev and prod have separate networks that share common services through a central hub. |
| FR-2 | Administrators can reach any VM over SSH without the VM having a public IP address. |
| FR-3 | Each spoke has web, app and data tiers, with traffic rules between them. |
| FR-4 | Platform services (Key Vault) are reached over private IP addresses only, with no public access. |
| FR-5 | Network traffic, both allowed and denied, is recorded and can be queried. |
| FR-6 | All infrastructure is defined in Terraform and changed only through reviewed pull requests. |

## 4. Non-functional requirements

| Requirement | Target | How it's met |
| --- | --- | --- |
| Isolation | Dev cannot reach prod by any path | Spokes peer to the hub only; peering is not transitive |
| Least exposure | No public IPs on VMs; no SSH open to the internet | Azure Bastion in the hub; private subnets with no default outbound access |
| Tier separation | Only expected traffic between tiers | An NSG per subnet, with an explicit deny of all other internal traffic |
| Auditability | Allowed and denied flows queryable within about 30 minutes | VNet flow logs with traffic analytics, sent to Log Analytics |
| Repeatability | A new spoke in minutes, with identical rules | One Terraform module, called once per environment |
| Security of the pipeline | No stored cloud secrets in GitHub | OpenID Connect (federated credentials) for GitHub Actions |
| Cost | Close to £0 when idle | Hourly-billed parts (VMs, private endpoint, Bastion) behind on/off switches |

## 5. Address plan

Ranges must never overlap, or the networks can't be peered. Each VNet is a /16 so new subnets can be added later without renumbering.

| Network | Range | Subnet | Range | Purpose |
| --- | --- | --- | --- | --- |
| Hub (`vnet-jwnet-hub`) | 10.10.0.0/16 | AzureBastionSubnet | 10.10.0.0/26 | Azure Bastion (name and minimum /26 size are fixed by Azure) |
| | | snet-management | 10.10.1.0/24 | Reserved for shared tools; a "not allowed" source in tests |
| Dev spoke (`vnet-jwnet-dev`) | 10.20.0.0/16 | snet-web | 10.20.0.0/24 | Web tier; test VM `dev-web` at 10.20.0.10 |
| | | snet-app | 10.20.1.0/24 | App tier; test VM `dev-app` at 10.20.1.10 |
| | | snet-data | 10.20.2.0/24 | Data tier; Key Vault private endpoint |
| Prod spoke (`vnet-jwnet-prod`) | 10.30.0.0/16 | snet-web | 10.30.0.0/24 | Web tier |
| | | snet-app | 10.30.1.0/24 | App tier; test VM `prod-app` at 10.30.1.10 |
| | | snet-data | 10.30.2.0/24 | Data tier |

Reserved for later spokes: 10.40.0.0/16 and above.

## 6. Traffic rules

Each subnet has its own NSG. Rules are listed in priority order; anything not allowed between internal networks is denied by an explicit rule at priority 4000, which sits above Azure's default `AllowVnetInBound` rule (65000).

| Subnet | Allowed in | Everything else |
| --- | --- | --- |
| web | HTTPS (443) from the internet | Internal traffic denied |
| app | SSH (22) from the Bastion subnet only; 8080 from the web tier | Internal traffic denied |
| data | 443 and 1433 from the app tier only | Internal traffic denied |

## 7. Acceptance criteria

The build is accepted when each test below passes and the evidence is saved in the README.

| Requirement | Test | Expected result |
| --- | --- | --- |
| FR-1, Isolation | Effective routes and next hop from `dev-app` to `prod-app`; a TCP connection test | No route to 10.30.0.0/16; next hop `None`; connection fails |
| FR-3, Tier separation | From `dev-web` to `dev-app` on ports 8080 and 22 | 8080 open, 22 blocked |
| FR-3 | IP flow verify on `dev-app` port 22 from the Bastion subnet and from the web tier | Allowed by `app-allow-ssh-bastion`; denied by `app-deny-vnet` |
| FR-4 | Resolve and connect to the Key Vault from a laptop, `dev-app` and `prod-app` | Laptop: public IP, access refused. Dev: private IP, reachable. Prod: private IP, not reachable |
| FR-5, Auditability | KQL query on `NTANetAnalytics` | Rows showing 8080 allowed and 22 denied from 10.20.0.10 |
| FR-2, Least exposure | SSH to `dev-app` through Bastion; test outbound internet | Session opens; no internet access from the VM |
| FR-6 | Turn a lab switch on and off through pull requests | Plan shown on the pull request; deploy runs only after merge |
| Cost | Cost Management for `rg-jwnet` after testing | Under £1 for the test session; near zero when switches are off |

## 8. Assumptions and constraints

- Region: UK South. Single subscription, pay-as-you-go.
- Terraform (azurerm provider 4.x) with remote state in Azure Storage; GitHub Actions for CI/CD.
- Test VMs are Standard_B1s running Ubuntu 24.04 LTS, and exist only while testing.
- Bastion uses the Basic SKU, because the free Developer SKU doesn't support peered networks.
- VMs have no outbound internet, so they can't install packages. Tests use tools already on the image (Bash, Python 3).
- Network Watcher must be enabled in UK South; flow logs are created in `NetworkWatcherRG`.
