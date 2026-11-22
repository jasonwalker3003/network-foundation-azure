# 0005: One spoke module, NSG rules as separate resources

**Status:** Accepted · **Date:** 2026-11-22

## Context

Dev and prod must have identical subnets and traffic rules, and new environments will be added later. Copying Terraform code per environment would let them drift apart.

## Options considered

**Code structure**

1. **Copy the resources per environment.** Easy to read, but every rule change must be made twice, and mistakes are likely.
2. **One module called with `for_each`.** One definition; each environment passes only its name and address range.

**NSG rules**

1. **Rules inline in the NSG resource.** Terraform owns the whole NSG and removes any rule it didn't create.
2. **Rules as separate `azurerm_network_security_rule` resources.** Rules can be added from a map with `for_each`, and other code can add rules to the same NSG.

## Decision

`infra/modules/spoke` builds a spoke's VNet, three subnets (`cidrsubnet()` from the /16), NSGs, rules, an application security group and both directions of peering. `network.tf` calls it with `for_each = { dev = "10.20.0.0/16", prod = "10.30.0.0/16" }`. The seven rules live in one `locals.rules` map and are created as separate resources.

## Consequences

- Dev and prod are guaranteed identical, and a new environment is one line in the map.
- The address range is validated (/16 only) so a bad value fails at plan time.
- Separate rule resources have a cost: Terraform doesn't notice rules added by hand. Tested: I added an "allow 22 from Any" rule in the portal and `terraform plan` reported `___`. A rule like that would silently weaken security.
- Production fix: either define rules inline so Terraform removes anything unexpected, or use Azure Policy to deny NSG rules that allow SSH from the internet. I'd do both.
