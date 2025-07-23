# nginx

Installs nginx, replaces the distribution configuration with a hardened one and
renders virtual hosts from a variable list. Modern TLS only, security headers on
every response, rate-limit zones declared once and referenced per location.

## Requirements

- Debian 11/12, Ubuntu 20.04/22.04/24.04, or RHEL/Rocky/Alma 8/9
- Privilege escalation (`become: true`)
- TLS material already on the host (the role does not issue certificates)

## Role variables

### Switches and service

| Variable | Default | Purpose |
|---|---|---|
| `nginx_manage_main_config` | `true` | Own `nginx.conf` and the shared snippets |
| `nginx_manage_vhosts` | `true` | Render `nginx_vhosts` into `conf.d` |
| `nginx_remove_default_vhost` | `true` | Delete the distribution placeholder site |
| `nginx_listen_ipv6` | `true` | Emit `listen [::]:…`; set false where there is no IPv6 stack |
| `nginx_modules_include` | per-OS glob | Keeps the distribution's dynamic-module loader working after `nginx.conf` is replaced; set to `""` to omit |
| `nginx_service_state` / `nginx_service_enabled` | `started` / `true` | Passed to `systemd_service` |

### Tuning

| Variable | Default | Purpose |
|---|---|---|
| `nginx_worker_processes` | `auto` | One worker per core |
| `nginx_worker_connections` | `4096` | Per-worker connection slots |
| `nginx_worker_rlimit_nofile` | `65536` | Must exceed `worker_connections` × 2 |
| `nginx_keepalive_timeout` | `65` | Idle upstream-facing keepalive |
| `nginx_client_max_body_size` | `16m` | Global upload ceiling; overridable per vhost |
| `nginx_client_body_timeout` / `nginx_client_header_timeout` | `15` | Slowloris budget |
| `nginx_log_format` | includes `rt=` and `urt=` | Request and upstream response time in every line |

### TLS

| Variable | Default | Purpose |
|---|---|---|
| `nginx_ssl_protocols` | `TLSv1.2 TLSv1.3` | Nothing older is negotiable |
| `nginx_ssl_ciphers` | ECDHE + AES-GCM / ChaCha20 | Mozilla intermediate, AEAD only |
| `nginx_ssl_prefer_server_ciphers` | `false` | The client's order is the better one with an AEAD-only list |
| `nginx_ssl_ecdh_curve` | `X25519:prime256v1:secp384r1` | Curve preference |
| `nginx_ssl_session_tickets` | `false` | nginx cannot rotate ticket keys, so tickets would weaken forward secrecy |
| `nginx_ssl_stapling` | `true` | OCSP stapling; needs `nginx_resolver` |
| `nginx_resolver` | `127.0.0.53` | Resolver used for the OCSP responder |
| `nginx_ssl_dhparam` | `""` | Path to a DH parameter file; unused with an ECDHE-only list |
| `nginx_hsts_value` | `max-age=63072000; includeSubDomains` | Emitted per vhost when `tls.hsts` is true |

### Headers and rate limiting

| Variable | Default | Purpose |
|---|---|---|
| `nginx_security_headers` | 5 headers | Rendered into `snippets/security-headers.conf` with `always` |
| `nginx_hide_server_tokens` | `true` | `server_tokens off` |
| `nginx_limit_req_zones` | `general` 30r/s, `auth` 5r/m | Declared in `http`, referenced by name |
| `nginx_limit_conn_zones` | `addr` | Per-address connection zones |
| `nginx_limit_req_status` | `429` | nginx defaults to 503, which monitoring misreads as a backend outage |

### Virtual hosts

`nginx_vhosts` is a list; `enabled` defaults to `true` and a disabled entry is
removed from `conf.d` rather than left behind.

```yaml
nginx_vhosts:
  - name: app
    server_name: [app.example.com]
    tls:
      enabled: true
      certificate: /etc/ssl/certs/app.example.com.pem
      certificate_key: /etc/ssl/private/app.example.com.key
      trusted_certificate: /etc/ssl/certs/chain.pem   # for OCSP stapling
      redirect_http: true
      hsts: true
    client_max_body_size: 32m
    upstream:
      name: app_backend
      keepalive: 32
      servers:
        - address: 203.0.113.21:8080
          options: max_fails=3 fail_timeout=10s
        - address: 203.0.113.22:8080
          options: max_fails=3 fail_timeout=10s
    locations:
      - path: /
        proxy_pass: http://app_backend
      - path: /login
        proxy_pass: http://app_backend
        limit_req: {zone: auth, burst: 5}
      - path: /static/
        alias: /srv/app/static/
        extra: ["expires 7d;", "access_log off;"]
```

| Key | Required | Notes |
|---|---|---|
| `name` | yes | File name under `conf.d` |
| `server_name` | yes | List of names |
| `enabled` | no | Defaults to true |
| `listen_port` / `default_server` | no | `80` / `false` |
| `root`, `index` | no | Static document root, created by the role |
| `tls` | no | `enabled`, `port`, `certificate`, `certificate_key`, `trusted_certificate`, `redirect_http`, `hsts` |
| `upstream` | no | `name`, `keepalive`, `servers: [{address, options}]` |
| `locations` | no | `path`, `proxy_pass`, `alias`, `root`, `try_files`, `return`, `limit_req`, `limit_conn`, `extra` |
| `rate_limit` / `limit_conn` | no | Applied at server level |
| `extra_config` | no | Raw directives appended to the server block |

## Handlers

| Handler | Triggered by |
|---|---|
| `Validate nginx configuration` | Any managed file; defined first so it always runs before the reload |
| `Reload nginx` | Same notifications |

## Notes

- `nginx.conf` is installed through the template's `validate` hook
  (`nginx -t -c %s`), so a broken main config never lands on disk.
- A vhost fragment has no enclosing `http` block and therefore cannot be
  validated in isolation. The role instead parses the whole tree after
  rendering (`tasks/validate.yml`) and again in the handler chain before the
  reload: a bad fragment fails the play while the running process keeps serving
  the previous configuration.
- The `http2` directive moved out of `listen` in nginx 1.25.1. The role reads
  the installed version and emits the right form instead of branching on the
  distribution.

## Molecule

```bash
molecule test -s default   # run from roles/nginx
```

The scenario renders three vhosts — static, TLS with an upstream, and a disabled
one — then asserts on live responses: security headers, the 308 to HTTPS, HSTS
on the TLS listener, and that `openssl s_client -tls1_1` is refused while
`-tls1_2` succeeds.
