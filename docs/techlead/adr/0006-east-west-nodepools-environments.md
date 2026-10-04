# ADR 0006: East-west traffic, node pools and environments

## Status
Accepted

## Context
A design review listed three apparent omissions: no internal load balancer for east-west traffic, a single node pool, and a single production stack. Each is a decision, not an oversight.

## Decisions
- **East-west traffic uses Multi-Cluster Services plus the managed service mesh, not internal load balancers.** app2 reaches app1 through the ServiceImport-derived name (`net.gke.io/derived-service`). This gives cross-region discovery, mTLS-capable Envoy sidecars, retries and telemetry without a regional internal load balancer per service. The per-region proxy-only subnets are reserved if an internal load balancer is ever needed.
- **One `primary` node pool per cluster.** Both apps have the same shape, the cluster autoscaler already scales it from 2 to 6 nodes, and GKE system pods can share it. Split into system and workload pools when workloads need different machine types, taints or Spot/on-demand mixes.
- **One production stack.** The brief asks for a single production environment. The modules and `envs/prod` pattern make a `dev` or `staging` stack a new directory with different variables (project, regions, CIDRs), not new code.

## Consequences
- Cross-cluster calls depend on MCS and the mesh being healthy; there is no load-balancer fallback path.
- Infrastructure changes are tested through plans and static checks, not in a separate environment.
