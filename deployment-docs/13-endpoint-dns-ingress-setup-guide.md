# Endpoint DNS + Ingress + External Nginx — Setup Guide (DEV)

Note: If you face issues during deployment, check:
  troubleshooting/nginx/, troubleshooting/kubernetes/, troubleshooting/linux/,
  troubleshooting/identity/

---

## Overview

Three things get wired up to complete the east-west path from an external client
to a K8s-hosted app:

  1. ex-nginx LXC                — dumb catch-all forwarding *.lab.local to
                                   K8s workers:30080
  2. ingress-nginx controller    — 3-replica HelmRelease inside K8s, does the
                                   real Host-based routing
  3. Per-app Ingress CRD         — each app ships a manifest saying "my host
                                   lands at my service"

Older pattern (pre-consolidation): ex-nginx held per-app config files with
per-app upstreams. Current pattern pushes routing intelligence INTO the cluster
via ingress-nginx; ex-nginx becomes a single rule. Adding a new app is now a
one-file change inside K8s, not a two-sided Ansible-and-K8s change.

Request chain:

```
External Client (AWS / VPN over 10.0.0.0/16)
  │
  │  DNS resolves *-dev.lab.local → 10.0.65.10
  │  (Route53 Private Zone from AWS side; FreeIPA DNS from on-prem)
  ▼
ex-nginx LXC (10.0.65.10 dev / 10.0.55.10 prod)
  server_name *.lab.local
  upstream k8s_workers (least_conn): 10.0.64.10-12:30080
  │
  ▼
K8s worker (NodePort 30080 → ingress-nginx-controller Service)
  │
  ▼
ingress-nginx controller pod (3 replicas, anti-affinity)
  matches Host header against Ingress.spec.rules[*].host
  │
  ▼
App Service (ClusterIP) → App pod
```

Full step-by-step request trace:
  deployment-docs/signal-flows/ingress-nginx.txt

---

## Prerequisites

- FreeIPA running (freeipa-initial-setup-guide.txt).
- K8s cluster running (k8s-initial-setup-guide.txt). Masters + workers Ready.
- Flux reconciling kubernetes/dev/deployments/infrastructure/ + apps/.
- VPN tunnel to AWS with 10.0.0.0/16 routed.
- AWS Route53 Private Zone (lab.local) associated with VPC.
- ex-nginx LXC container already provisioned on Proxmox (from golden LXC template).

---

## Section 1: ex-nginx LXC — enroll in FreeIPA

Container settings (already applied when LXC was cloned from golden template):
  Hostname:   ex-nginx
  IP / VLAN:  10.0.65.10/24, VLAN 65 (dev)   — 10.0.55.10/24, VLAN 55 (prod)
  Gateway:    10.0.65.1 (dev) / 10.0.55.1 (prod)

Enroll the host in FreeIPA:

  cd ansible/dev/
  ansible-playbook -i inventory/inventory.ini playbooks/freeipa/add_hosts_to_ipa.yml --limit nginx
  ansible-playbook -i inventory/inventory.ini playbooks/freeipa/domain_config.yml --limit nginx
  ansible-playbook -i inventory/inventory.ini playbooks/freeipa/fix_lxc_krb5_keyring.yml --limit nginx

Full FreeIPA story (domain model, UID range, krb5 FILE cache, NTP skip):
  freeipa-overview.md

---

## Section 2: Deploy ingress-nginx controller (inside K8s)

Manifests committed in:
  kubernetes/dev/deployments/infrastructure/ingress/
    helm-repository.yaml
    helm-release.yaml
    kustomization.yaml

Chart: ingress-nginx v4.15.1. Key values already set in the HelmRelease:
  replicaCount:                 3
  service.type:                 NodePort
  service.nodePorts.http:       30080
  service.nodePorts.https:      30443
  ingressClassResource.name:    nginx   (registered as default IngressClass)
  priorityClassName:            system-cluster-critical
  affinity.podAntiAffinity:     preferredDuringScheduling (spread across workers)

Deployment happens automatically via Flux. Verify:

  kubectl get pods -n ingress-nginx
  # expect: 3 x ingress-nginx-controller-xxxxx   1/1   Running

  kubectl get ingressclass
  # expect: nginx   IS_DEFAULT=true

  kubectl get svc -n ingress-nginx
  # expect: ingress-nginx-controller NodePort, http:30080/TCP, https:30443/TCP

---

## Section 3: Configure ex-nginx as catch-all pass-through

The pattern shift from the old guide matters here. ex-nginx is no longer
per-app — one server block matches *.lab.local and forwards to workers:30080.
All per-app routing lives in K8s.

Install + configure via Ansible:

  cd ansible/dev/
  ansible-playbook -i inventory/inventory.ini playbooks/nginx/nginx_setup.yml

Templates (committed):
  ansible/dev/playbooks/nginx/templates/nginx.conf.j2       → main config with
                                                              upstream log format
                                                              (upstream_addr +
                                                              request_time +
                                                              upstream_response_time)
  ansible/dev/playbooks/nginx/templates/k8s-ingress.conf.j2 → catch-all site:
                                                              upstream k8s_workers,
                                                              least_conn,
                                                              server_name *.lab.local,
                                                              proxy_pass → upstream,
                                                              client_max_body_size 500m,
                                                              proxy_read/send_timeout 300s

The upstream log format is the debugging gold. Every "something didn't reach
the app" incident has been one `tail -f` on the ex-nginx access log away from
pointing at the right layer.

To re-apply config changes without reinstalling:

  ansible-playbook -i inventory/inventory.ini playbooks/nginx/apply_new_config.yml

Old per-app templates (wordpress.conf.j2, grafana.conf.j2, nginx-test.conf.j2)
are gone. If any are still present on a running ex-nginx, remove them.

---

## Section 4: Add DNS records (FreeIPA + AWS Route53)

Every app's hostname resolves to ex-nginx's IP. Both DNS sources point at the
same IP because both client populations need to reach it.

### On-prem (FreeIPA DNS)

Loop-based playbook — add a line per app:

  ansible/dev/playbooks/freeipa/add_dns_records.yml

  loop entries (current):
    - { name: "wordpress-dev",   ip: "10.0.65.10" }
    - { name: "grafana-dev",     ip: "10.0.65.10" }
    - { name: "prometheus-dev",  ip: "10.0.65.10" }
    - { name: "loki-dev",        ip: "10.0.65.10" }
    - { name: "vault",           ip: "10.0.62.100" }   ← VIP, NOT ex-nginx
    - { name: "k8s",             ip: "10.0.61.100" }   ← VIP, NOT ex-nginx

  ansible-playbook -i inventory/inventory.ini playbooks/freeipa/add_dns_records.yml

Full DNS story (forwarders, node-side fallback, CoreDNS hosts plugin for the
vault.lab.local + k8s.lab.local VIPs that pods MUST resolve even during an
IPA outage): freeipa-overview.md

### AWS side (Route53 private zone)

Terraform for_each loop — add app name to the list:

  terraform/dev/aws/network/main.tf

    locals.dns_records = ["wordpress", "grafana", "prometheus", "loki"]

  terraform/dev/aws/network/variables.tf
    var.dns_ingress_ip = 10.0.65.10   (default)

Commit to dev branch. The workflow .github/workflows/dev-aws-network.yml
auto-plans on push, waits 3 min, auto-applies. Low-risk DNS state, no lock
by design.

---

## Section 5: Create the Ingress CRD per app

Routing intelligence lives here. Each app ships an Ingress resource in its
own manifest folder.

Current in-cluster state:

  kubectl get ingress -A

  NAMESPACE    NAME                             CLASS   HOSTS                     PORTS
  apps         ingress-wordpress                nginx   wordpress-dev.lab.local   80
  monitoring   kube-prometheus-stack-grafana    nginx   grafana-dev.lab.local     80

Committed example manifests:
  kubernetes/dev/deployments/apps/wordpress/     → Ingress + Service + Deployment
  kubernetes/dev/deployments/apps/monitoring/    → Grafana Ingress (from Helm values)

Annotations worth knowing (set on each app's Ingress):
  nginx.ingress.kubernetes.io/proxy-body-size    → must align with ex-nginx's
                                                    client_max_body_size (500m)
  nginx.ingress.kubernetes.io/affinity: cookie   → sticky session (WordPress admin)
  nginx.ingress.kubernetes.io/session-cookie-*   → cookie name + expiry

Important:
  - App Services are type ClusterIP, NOT NodePort. The only NodePort in the
    cluster is the ingress-nginx controller Service. If any older app manifest
    still has NodePort, remove it.
  - Apps that need Vault-injected secrets follow the standard pattern — see
    vault-k8s-integration-guide.txt for the annotation template.

---

## Section 6: Readiness probes → endpoint membership

The ingress controller talks to each app's Service ClusterIP. The Service
routes to the current set of endpoints — pods that pass their readiness probe.

  kubectl get endpointslice -n apps

If a pod's readiness probe fails, it's dropped from the endpoint list
automatically. The controller sees the update (via its watch on
Services/Endpoints) and stops routing new traffic to the failing pod.
Existing connections drain naturally.

Every app pod MUST have a real readiness probe (HTTP GET that 200s only when
the app is actually ready — not `tcpSocket` on a port that's open even during
startup). This is the built-in health gating; no external circuit breaker
needed.

---

## Section 7: Multi-controller pattern (future, not deployed)

If public vs internal traffic ever needs isolation:

  1. Deploy a second ingress-nginx controller with
       ingressClassResource.name: nginx-external
       service.nodePorts.http:    30081
  2. Each Ingress picks its class via .spec.ingressClassName (nginx-external
     for public, nginx for internal).
  3. Route ex-nginx's 30081 upstream to public-facing paths, keep 30080 for
     internal.

Noted in: deployment-docs/signal-flows/ingress-nginx.txt

---

## Section 8: Verification

### DNS

  dig wordpress-dev.lab.local   # on-prem → 10.0.65.10
  dig grafana-dev.lab.local     # on-prem → 10.0.65.10

From an EC2 in the VPC:

  dig wordpress-dev.lab.local   # Route53 private zone → 10.0.65.10

### Full request path

  curl -v -H "Host: wordpress-dev.lab.local" http://wordpress-dev.lab.local

If it fails, trace each hop:

  # Hop 1 — reach ex-nginx
  curl -v http://10.0.65.10/ -H "Host: wordpress-dev.lab.local"

  # Hop 2 — ex-nginx forwarding (watch access log)
  ssh ex-nginx.lab.local 'tail -f /var/log/nginx/nginx-test-dev.log'

  # Hop 3 — ingress controller received it
  kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=20

  # Hop 4 — Ingress object exists and matches host
  kubectl get ingress -A
  kubectl describe ingress ingress-wordpress -n apps

  # Hop 5 — service has healthy endpoints
  kubectl get endpointslice -n apps
  kubectl get pods -n apps -l app=wordpress -o wide

---

## Adding a new app — short checklist

1. Commit the app's Deployment + Service (ClusterIP) + Ingress manifest
   under kubernetes/dev/deployments/apps/<app>/.
2. Add DNS:
     FreeIPA: new line in ansible/dev/playbooks/freeipa/add_dns_records.yml,
              run the playbook.
     AWS:     add app name to locals.dns_records in
              terraform/dev/aws/network/main.tf, commit to dev.
3. Test: curl http://<app>-dev.lab.local

No ex-nginx change needed. Catch-all already forwards *.lab.local; routing
decision is in the Ingress CRD.

---

## File Reference

| Component                        | Path                                                                    |
|----------------------------------|-------------------------------------------------------------------------|
| ex-nginx setup playbook          | ansible/dev/playbooks/nginx/nginx_setup.yml                             |
| ex-nginx config-apply playbook   | ansible/dev/playbooks/nginx/apply_new_config.yml                        |
| ex-nginx main nginx.conf         | ansible/dev/playbooks/nginx/templates/nginx.conf.j2                     |
| ex-nginx catch-all site          | ansible/dev/playbooks/nginx/templates/k8s-ingress.conf.j2               |
| ex-nginx group_vars              | ansible/dev/inventory/group_vars/nginx.yml                              |
| FreeIPA DNS records playbook     | ansible/dev/playbooks/freeipa/add_dns_records.yml                       |
| ingress-nginx HelmRelease        | kubernetes/dev/deployments/infrastructure/ingress/helm-release.yaml     |
| ingress-nginx HelmRepository     | kubernetes/dev/deployments/infrastructure/ingress/helm-repository.yaml  |
| ingress-nginx Kustomize          | kubernetes/dev/deployments/infrastructure/ingress/kustomization.yaml    |
| CoreDNS hosts-plugin ConfigMap   | kubernetes/dev/deployments/infrastructure/coredns/coredns-custom.yaml   |
| App Ingress examples             | kubernetes/dev/deployments/apps/{wordpress,monitoring}/                 |
| AWS Route53 Terraform            | terraform/dev/aws/network/main.tf                                       |
| AWS Route53 variables            | terraform/dev/aws/network/variables.tf                                  |
| AWS Route53 workflow             | .github/workflows/dev-aws-network.yml                                   |
| Signal flow (detailed trace)     | deployment-docs/signal-flows/ingress-nginx.txt                          |
| FreeIPA overview (DNS + deps)    | freeipa-overview.md                                                     |
| Vault injection pattern          | vault-k8s-integration-guide.txt                                         |
| Vault overview (layer map)       | vault-overview.md                                                       |
| DR test (IPA-down DNS cascade)   | disaster-recovery/network-ipa-dns-outage.md                             |

Prod mirror: same paths under ansible/prod/, kubernetes/prod/, terraform/prod/.

---

## IP Reference

| Environment | ex-nginx IP | K8s Workers          | VLAN | ingress NodePort |
|-------------|-------------|----------------------|------|------------------|
| Dev         | 10.0.65.10  | 10.0.64.10-12:30080  | 65   | 30080 / 30443    |
| Prod        | 10.0.55.10  | 10.0.54.10-12:30080  | 55   | 30080 / 30443    |

---

## Troubleshooting

| Symptom                                       | Likely cause / check                                                         |
|-----------------------------------------------|------------------------------------------------------------------------------|
| DNS not resolving (on-prem)                   | FreeIPA DNS record missing, or IPA is down. Check add_dns_records.yml + IPA. |
| DNS not resolving (AWS)                       | Route53 private zone not associated with VPC, or record missing.             |
| Connection timeout from client                | VPN tunnel down, or 10.0.0.0/16 route missing on AWS VPC.                    |
| 502 Bad Gateway at ex-nginx                   | Workers unreachable on 30080. Check ingress-nginx NodePort svc + worker state. |
| 502 Bad Gateway at ingress controller         | App Service has no healthy endpoints. Check readiness probes + pod state.    |
| 404 Not Found with correct host               | No Ingress resource matches the Host header. Check `kubectl get ingress -A`. |
| ex-nginx config syntax error                  | Ansible halts before reload. Run `nginx -t` on ex-nginx to see the line.     |
| Large WordPress upload fails                  | client_max_body_size mismatch between ex-nginx and Ingress annotation.       |
| Sticky session dropping                       | Ingress missing affinity/session-cookie annotations, or cookie expiry short. |
| New pod stuck in Init during IPA outage       | CoreDNS + vault.lab.local resolution. See TS-K8S-033 + freeipa-overview.md. |
| WordPress slow during IPA outage              | Node-side fallback missing. Run ansible/.../freeipa/dns_fallback.yml.        |

---

## DNS resolution — what breaks when IPA is down

Short version (full detail in freeipa-overview.md):
  - pods → CoreDNS hosts plugin answers vault.lab.local + k8s.lab.local directly
           (new pod startup still works for Vault injection)
  - pods → other *.lab.local names fail (no fallback for IPA-authoritative names)
  - nodes → external DNS (google.com, etc.) works via 8.8.8.8 fallback after
           dns_fallback.yml has been applied
  - external clients → *.lab.local fails (no fallback answers the zone)

See: disaster-recovery/network-ipa-dns-outage.md, TS-K8S-033, TS-K8S-034, TS-LNX-003.
