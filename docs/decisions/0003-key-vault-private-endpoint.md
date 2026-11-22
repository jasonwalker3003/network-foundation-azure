# 0003: Key Vault through a private endpoint and private DNS

**Status:** Accepted · **Date:** 2026-11-22

## Context

Applications will need secrets from Key Vault. Security requires that platform services are reached over private IP addresses, with no route from the internet.

## Options considered

1. **Public endpoint with the Key Vault firewall** allowing selected VNets (service endpoints). Simple and free, but the vault keeps a public endpoint, and traffic still goes to a public IP address.
2. **Private endpoint with public access disabled.** The vault gets a private IP inside a spoke; private DNS makes its normal name resolve to that IP.

## Decision

Option 2. `kv-jwnet-lab` has `public_network_access_enabled = false`. Private endpoint `pe-jwnet-kv` sits in the dev data subnet, and the private DNS zone `privatelink.vaultcore.azure.net` is linked to all three VNets. The endpoint is behind the `enable_private_endpoint` switch; the vault and DNS zone stay on, as they cost almost nothing.

## Consequences

- From the internet the vault refuses all access. Tested: from my laptop, the name resolved to a public IP and `az keyvault secret list` failed with `ForbiddenByConnection`.
- From `dev-app` the name resolved to the private IP (`___`) and port 443 was reachable.
- From `prod-app` the name **also** resolved to the private IP (the DNS zone is linked to every VNet), but the connection failed, because prod has no route to dev. DNS and routing are separate layers: having the right address is not the same as having a path to it. Production would put shared endpoints in the hub, or give each environment its own vault.
- A private endpoint is charged by the hour, so it is switched off between tests.
- Managing the vault's contents now also needs network access: with public access disabled, even I can't list secrets from my laptop. Production would use a build agent or a VM inside the network.
