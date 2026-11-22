# 0006: VNet flow logs with traffic analytics

**Status:** Accepted · **Date:** 2026-11-22

## Context

Security wants a record of network traffic, both allowed and denied, for audits and troubleshooting, queryable without downloading raw log files.

## Options considered

1. **NSG flow logs.** The older option, logged per NSG. Azure no longer allows new NSG flow logs to be created and is retiring them.
2. **VNet flow logs to storage only.** Raw JSON files per hour; complete, but hard to search.
3. **VNet flow logs with traffic analytics.** Flow logs go to storage and are also processed into a Log Analytics table (`NTANetAnalytics`) that can be queried with KQL.

## Decision

Option 3. One flow log per VNet (hub, dev and prod), version 2, 7-day retention in `stjwnetflow`, traffic analytics every 10 minutes into `log-jwnet`. The workspace has a 0.2 GB daily cap. Flow logs belong to Network Watcher, so they live in `NetworkWatcherRG`, where the pipeline has Network Contributor.

## Consequences

- Allowed and denied flows can be queried by source, destination, port and NSG rule. Tested: rows showed port 8080 from 10.20.0.10 allowed by `app-allow-8080-web` and port 22 denied by `app-deny-vnet`.
- Data is not real-time: it took about `___` minutes after a test for rows to appear.
- Traffic with no route never reaches an NSG, so it isn't logged as "Denied". The dev-to-prod attempt didn't appear at all. Not every blocked connection shows in the logs.
- Charges are per GB collected and processed. They're pennies at lab volumes, and the daily cap limits ingestion, but it could hide data on a busy network. Production would size the cap and retention to the audit requirement.
- Creating three flow logs at once once failed with an `InternalServerError` from Azure; deleting the failed one and re-running `apply` fixed it.
