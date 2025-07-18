# haproxy

Renders a complete `haproxy.cfg` from variables: frontends with optional TLS
termination, backends with health checks, a runtime admin socket and a
loopback-bound stats listener with the built-in Prometheus exporter.

## Requirements

- Debian 11/12, Ubuntu 20.04/22.04/24.04, or RHEL/Rocky/Alma 8/9 (HAProxy 2.2+)
- Privilege escalation (`become: true`)
- For TLS binds: a PEM file containing key **and** certificate

## Role variables

### Global

| Variable | Default | Purpose |
|---|---|---|
| `haproxy_maxconn` | `20000` | Process-wide connection ceiling |
| `haproxy_nbthread` | `0` | `0` leaves the automatic thread count |
| `haproxy_log_target` / `haproxy_log_facility` | `/dev/log` / `local0` | syslog target |
| `haproxy_chroot` | `/var/lib/haproxy` | Chroot after binding |
| `haproxy_stats_socket` | `/run/haproxy/admin.sock` | Runtime API; lets a deploy drain a server without editing the config |
| `haproxy_stats_socket_level` | `admin` | Required for `set server … state maint` |
| `haproxy_hard_stop_after` | `5m` | Upper bound on a graceful shutdown |

### TLS

| Variable | Default | Purpose |
|---|---|---|
| `haproxy_ssl_min_version` | `TLSv1.2` | Applied through `ssl-default-bind-options` |
| `haproxy_ssl_bind_ciphers` | ECDHE AEAD suites | TLS 1.2 cipher list |
| `haproxy_ssl_bind_ciphersuites` | AES-GCM, ChaCha20 | TLS 1.3 suites |
| `haproxy_ssl_bind_options` | `prefer-client-ciphers no-tls-tickets` | Extra bind options |
| `haproxy_ssl_dh_param_size` | `2048` | Only used by non-ECDHE suites |

### Defaults section

| Variable | Default | Purpose |
|---|---|---|
| `haproxy_default_mode` | `http` | Section default |
| `haproxy_default_retries` | `3` | Connection retries |
| `haproxy_default_options` | `httplog`, `dontlognull`, `redispatch` | Emitted as `option …` |
| `haproxy_timeouts` | connect 5s, client/server 30s, … | Mapping of `timeout <name> <value>` |
| `haproxy_default_server_options` | `inter 3s fall 3 rise 2 slowstart 20s` | Applied to every server |
| `haproxy_manage_error_pages` | `true` | Reference the distribution error pages |

### Frontends

```yaml
haproxy_frontends:
  - name: web
    binds:
      - {address: 198.51.100.10, port: 80}
      - address: 198.51.100.10
        port: 443
        ssl: true
        certificate: /etc/haproxy/certs/app.example.com.pem
        alpn: h2,http/1.1
    options: [forwardfor]
    acls:
      - {name: is_api, criterion: "path_beg /api/"}
    http_requests:
      - "redirect scheme https code 308 unless { ssl_fc }"
    use_backends:
      - {backend: api_pool, condition: is_api}
    default_backend: web_pool
```

### Backends

```yaml
haproxy_backends:
  - name: web_pool
    balance: roundrobin
    health_check:
      uri: /healthz
      method: GET
      host: app.example.com
      expect_status: 200
    servers:
      - {name: web1, address: 203.0.113.11, port: 8080}
      - {name: web2, address: 203.0.113.12, port: 8080, options: "maxconn 200"}
```

Health checks are emitted in the modern form (`option httpchk` plus
`http-check send`), which is the only form that can set a `Host` header —
necessary as soon as the backend serves more than one virtual host.

### Stats listener

| Variable | Default | Purpose |
|---|---|---|
| `haproxy_stats_enabled` | `true` | Install the `listen stats` section |
| `haproxy_stats_bind_address` | `127.0.0.1` | Loopback: the page exposes the whole backend topology |
| `haproxy_stats_bind_port` | `8404` | Listener port |
| `haproxy_stats_uri` | `/haproxy-status` | Not `/` — keeps it off casual scans |
| `haproxy_stats_user` / `haproxy_stats_password` | `""` | Empty disables basic auth |
| `haproxy_stats_prometheus` | `true` | Built-in exporter, no sidecar |
| `haproxy_stats_prometheus_uri` | `/metrics` | Scrape path |

## Handlers

| Handler | Triggered by |
|---|---|
| `Reload haproxy` | Configuration change; a reload drains existing connections instead of dropping them |

## Notes

- HAProxy keeps everything in one file, so the template's `validate` hook
  (`haproxy -c -f %s`) checks the real candidate configuration — including
  certificate paths and ACL syntax — before it is installed. A broken change
  fails the task and never reaches `/etc/haproxy`.
- The Prometheus exporter is served on the stats listener without
  authentication so a scraper does not need credentials; the listener is bound
  to loopback for exactly that reason.
- `haproxy_stats_password` belongs in Ansible Vault, not in plain group_vars.

## Molecule

```bash
molecule test -s default   # run from roles/haproxy
```

The scenario builds a two-backend topology with an ACL-routed API pool and a
TLS bind, then asserts against the running process: `haproxy -c` accepts the
file, the admin socket exists, the stats page returns 401 without credentials
and lists both pools with them, `/metrics` emits `haproxy_backend_up`, and the
TLS bind refuses TLS 1.1 while accepting TLS 1.2.
