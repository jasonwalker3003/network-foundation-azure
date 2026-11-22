# 0001: Hub-and-spoke topology

**Status:** Accepted · **Date:** 2026-11-22

## Context

The company needs separate dev and prod networks that can never reach each other, plus shared services (admin access, later DNS and firewalls) that both environments use. More environments will follow.

## Options considered

1. **One VNet with subnets per environment.** Simplest, but dev and prod share one routing domain: every subnet can reach every other by default, and isolation depends entirely on NSG rules being right.
2. **Full mesh.** A VNet per environment, each peered to every other. Isolation is lost again, and the number of peerings grows quickly (n × (n − 1) / 2).
3. **Hub-and-spoke.** A hub VNet holds shared services; each environment is a spoke peered only to the hub.

## Decision

Option 3. `vnet-jwnet-hub` (10.10.0.0/16) holds Bastion and a management subnet; `vnet-jwnet-dev` (10.20.0.0/16) and `vnet-jwnet-prod` (10.30.0.0/16) are spokes, each peered to the hub only.

## Consequences

- VNet peering is not transitive, so dev and prod have no route to each other at all. Isolation comes from routing, not just from NSG rules. Tested: `show-next-hop` from `dev-app` to `prod-app` returned `None`, and a TCP connection test failed.
- Shared services are deployed once, in the hub, and every spoke can use them.
- Adding an environment means one new spoke and one pair of peerings, not a peering to every existing VNet.
- If spokes ever do need to talk (for example a shared API), it must go through a firewall or network virtual appliance in the hub, with user-defined routes. That is deliberately out of scope here, and is the main production addition.
- Address ranges must never overlap or peering fails, so the address plan (see `docs/requirements.md`) was fixed before building, with /16 per VNet to leave room to grow.
