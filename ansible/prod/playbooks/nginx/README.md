# Nginx Playbooks — PROD

Ansible playbooks for the external Nginx LXC (`ex-nginx`) — the dumb layer-7
pass-through in front of the Kubernetes cluster that forwards anything
matching `*.lab.local` to the K8s workers on port 30080. From there the
ingress-nginx controller inside K8s does the real host-based routing.

For the broader ingress architecture (why two layers, ingress-nginx controller,
per-app Ingress CRDs, DNS fallback story) see
[`../../../../deployment-docs/13-endpoint-dns-ingress-setup-guide.md`](../../../../deployment-docs/13-endpoint-dns-ingress-setup-guide.md).

---

## Playbooks

| Playbook | Purpose | Target |
|----------|---------|--------|
| `nginx_setup.yml` | Install Nginx + deploy main `nginx.conf` + deploy the catch-all site config | `nginx` |
| `apply_new_config.yml` | Re-apply the catch-all site config after template changes (validates with `nginx -t` then reloads) | `nginx` |

## Templates

| File | Purpose |
|------|---------|
| `templates/nginx.conf.j2` | Main nginx config. Defines the `upstream log format` with `$upstream_addr`, `$request_time`, `$upstream_response_time` — the debugging gold for incidents |
| `templates/k8s-ingress.conf.j2` | Single catch-all site: `server_name *.lab.local`, `upstream k8s_workers` (least_conn, 3 workers:30080), `client_max_body_size 500m`, `proxy_read_timeout 300s` |

## When these run

- `nginx_setup.yml` — once after the ex-nginx LXC is provisioned and enrolled in FreeIPA. Runs via `prod-nginx-full-setup.yml` workflow.
- `apply_new_config.yml` — whenever the catch-all site template changes. Safe to re-run; validates before reloading.

## Key points about this setup

- **One site config, not per-app.** Earlier versions had per-app nginx
  templates (`wordpress.conf.j2`, `grafana.conf.j2`, etc.). Current pattern:
  one catch-all config that forwards everything to the ingress-nginx
  controller inside K8s. Adding a new app doesn't touch ex-nginx at all —
  only the app's own Ingress CRD changes.
- **`least_conn` load balancing across the 3 workers** — not round-robin.
  Workloads like Grafana dashboard renders have variable completion times;
  least-conn handles that gracefully.
- **`client_max_body_size 500m`** — aligned with the WordPress Ingress'
  `proxy-body-size` annotation. The two layers must match for large uploads.

## Related

- [`../../../../deployment-docs/13-endpoint-dns-ingress-setup-guide.md`](../../../../deployment-docs/13-endpoint-dns-ingress-setup-guide.md) — full ingress story (2-layer architecture, per-app Ingress CRDs, DNS)
- [`../../../../deployment-docs/signal-flows/ingress-nginx.txt`](../../../../deployment-docs/signal-flows/ingress-nginx.txt) — request trace from external client through ex-nginx + ingress controller to the app pod
- [`../../../../kubernetes/prod/deployments/infrastructure/ingress/`](../../../../kubernetes/prod/deployments/infrastructure/ingress/) — ingress-nginx controller HelmRelease
- [`../../../../troubleshooting/nginx/`](../../../../troubleshooting/nginx/) — nginx-specific TS cases
