# ADR 0001 - Multi-cluster Gateway API for global load balancing

**Status:** Accepted

## Context
We need one public entry point that spreads traffic across two GKE clusters in different regions and fails over automatically.

## Options
1. **MultiClusterIngress / MultiClusterService CRDs**: older, still supported, but GKE-specific.
2. **Multi-cluster Gateway** (`gke-l7-global-external-managed-mc`): built on the Kubernetes Gateway API standard, lets each team own its own route, and supports policies (`HealthCheckPolicy`, `GCPBackendPolicy` with Cloud Armor).
3. A self-managed global LB in Terraform pointing at standalone NEGs: works, but the NEG names are created by GKE, so Terraform and Kubernetes would fight over them.

## Decision
Option 2.

## Consequences
- One cluster is the **config cluster** (`gke-usc1`) and holds the Gateway objects. If it goes down, existing load balancer config **keeps serving**, but no changes can be made until it's back.
- Needs fleet registration plus the MCS and MCI hub features (`modules/fleet`).
- The first deploy takes 5-10 minutes before the LB is ready.
