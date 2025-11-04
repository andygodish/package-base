# Istio

## Ambient Mode

- Each node (L4 at the node level) gets its own `ztunnel`
- No sidecar proxies are deployed
- Pod-to-pod communication is intercepted by the istio CNI plugin and redirected to the local `ztunnel`
- src ztunnel will encrypt, dst ztunnel will decrypt

## Istiod

- A SPIFFE identity is a standardized, cryptographically verifiable identifier for a workload.
  - Istiod issues SPIFFE identities to workloads in the mesh, which are used for mutual TLS authentication and authorization between services.
  - It issues each workload an X.509 certificate whose Subject Alternative Name (SAN) is its SPIFFE ID.

```bash
spiffe://<trust-domain>/ns/<namespace>/sa/<service-account>
```
