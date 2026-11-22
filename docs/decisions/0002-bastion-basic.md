# 0002: Azure Bastion Basic, switched on only when needed

**Status:** Accepted · **Date:** 2026-11-22

## Context

Administrators need SSH access to VMs in both spokes. Security requires that no VM has a public IP and that no SSH port is open to the internet.

## Options considered

1. **Public IP and SSH on each VM, locked to an office IP.** Cheap, but every VM is exposed, office IPs change, and keys must be managed per VM.
2. **A jump box VM in the hub.** One exposed VM instead of many, but it still needs a public IP, patching and hardening.
3. **Azure Bastion, Developer SKU.** Free, but it only connects to VMs in the same VNet. It does not work across peering, so it can't reach the spokes from the hub.
4. **Azure Bastion, Basic SKU.** A managed service in the hub that reaches peered VNets. Charged by the hour.

## Decision

Option 4: Bastion Basic in `AzureBastionSubnet` (10.10.0.0/26, the name and minimum size Azure requires), behind the `enable_bastion` switch in `terraform.tfvars`. It is switched on through a pull request when needed and switched off straight after.

## Consequences

- No VM has a public IP. The only inbound SSH rule is from the Bastion subnet (`app-allow-ssh-bastion`). Tested: SSH session to `dev-app` through the portal worked; IP flow verify allowed port 22 from 10.10.0.10 and denied it from the web tier.
- Basic is the largest hourly cost in the project (about £0.15–0.20 an hour). Leaving it on for a month would cost over £100, which is why it has its own switch.
- Creating Bastion takes about 10 minutes, so access isn't instant. Acceptable for a lab; in production it would stay on.
- Basic only supports connecting through the portal. Connecting from a local SSH client (`az network bastion ssh`) needs the Standard SKU, which I'd choose in production.
