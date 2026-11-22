# 0004: Private subnets with no default outbound internet

**Status:** Accepted · **Date:** 2026-11-22

## Context

Historically, Azure gave any VM without an explicit outbound method a hidden, shared public IP for internet access ("default outbound access"). Microsoft is retiring this, and VNets created from 31 March 2026 have private subnets by default. Security wants nothing in the network calling out to the internet unexpectedly.

## Options considered

1. **Rely on default outbound access.** VMs can install updates without extra resources, but outbound traffic leaves from an IP the company doesn't own or control, and the feature is being retired.
2. **Private subnets plus a NAT gateway.** Controlled outbound internet through a known public IP. Charged by the hour plus data.
3. **Private subnets with no outbound internet.** Nothing can call out at all.

## Decision

Option 3 for this project: every subnet has `default_outbound_access_enabled = false`, set explicitly in Terraform rather than relying on the new default.

## Consequences

- Nothing inside the network can reach the internet. Tested: from `dev-app` through Bastion, `curl https://example.com` failed.
- The test VMs can't install packages, so the tests only use tools already on the Ubuntu image (Bash's `/dev/tcp`, Python's `http.server`), and commands are run with Run Command, which goes through Azure's management channel rather than the VM's network.
- Azure services still work through private endpoints (ADR 0003).
- Real workloads will need updates. Production would add a NAT gateway, or route outbound traffic through a firewall in the hub so it can be filtered and logged.
