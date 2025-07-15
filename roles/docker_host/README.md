# docker_host

Installs the Docker engine from the upstream Docker repository, writes an
opinionated `daemon.json`, manages `docker` group membership and schedules a
prune timer so the host does not run out of disk between deploys.

## Requirements

- Debian 11/12, Ubuntu 20.04/22.04/24.04, or RHEL/Rocky/Alma 8/9
- Outbound access to `download.docker.com`
- Privilege escalation (`become: true`)

## Role variables

### Feature switches

| Variable | Default | Purpose |
|---|---|---|
| `docker_host_manage_repository` | `true` | Configure the upstream APT/YUM repository |
| `docker_host_manage_daemon_config` | `true` | Write `/etc/docker/daemon.json` |
| `docker_host_manage_users` | `true` | Manage `docker` group membership |
| `docker_host_manage_prune` | `true` | Install the prune service and timer |

### Repository and packages

| Variable | Default | Purpose |
|---|---|---|
| `docker_host_repository_channel` | `stable` | Upstream channel |
| `docker_host_apt_key_path` | `/etc/apt/keyrings/docker.asc` | Key location referenced by `signed_by=` |
| `docker_host_packages` | `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin` | May carry a version spec, e.g. `docker-ce=5:27.3.1-1~debian.12~bookworm` |
| `docker_host_install_compose_plugin` | `true` | Also install `docker-compose-plugin` |
| `docker_host_service_state` | `started` | Passed to `systemd_service` |
| `docker_host_service_enabled` | `true` | Start at boot |

### Daemon configuration

| Variable | Default | Purpose |
|---|---|---|
| `docker_host_daemon_config` | see below | The opinionated base mapping |
| `docker_host_daemon_config_extra` | `{}` | Merged recursively over the base; use this for registry mirrors, proxies, per-host tweaks |

Base policy:

| Key | Value | Why |
|---|---|---|
| `log-driver` / `log-opts` | `json-file`, 50 MB × 5 | Unbounded container logs are the most common cause of a full root filesystem |
| `live-restore` | `true` | Containers survive a daemon restart during an engine upgrade |
| `userland-proxy` | `false` | Removes one `docker-proxy` process per published port and preserves the client source address |
| `storage-driver` | `overlay2` | Explicit rather than autodetected |
| `default-address-pools` | `10.201.0.0/16` /24 | The stock `172.17/16` collides with plenty of corporate ranges |
| `no-new-privileges` | `true` | Default `no_new_privs` for containers |
| `icc` | `false` | Containers on the default bridge cannot talk to each other; user-defined networks are unaffected |
| `metrics-addr` | `127.0.0.1:9323` | Engine metrics for a local scraper only |

### Group membership and prune

| Variable | Default | Purpose |
|---|---|---|
| `docker_host_group` | `docker` | Group granting socket access |
| `docker_host_users` | `[]` | Users appended to that group |
| `docker_host_prune_schedule` | `Sun 03:20` | `OnCalendar` expression |
| `docker_host_prune_randomized_delay` | `1800` | Spreads the fleet over half an hour |
| `docker_host_prune_until` | `168h` | Images newer than this survive, so a rollback needs no pull |
| `docker_host_prune_volumes` | `false` | Off by default: a stray named volume is usually somebody's data |
| `docker_host_prune_build_cache` | `true` | Also prune the BuildKit cache |

## Handlers

| Handler | Triggered by |
|---|---|
| `Restart docker` | `daemon.json` change |
| `Reload systemd units` | Prune unit or timer change |

## Notes

- Membership in `docker_host_users` is equivalent to passwordless root: any
  member can bind-mount `/` into a container. The list is deliberately empty by
  default.
- `daemon.json` is serialised from a mapping with `to_nice_json`, so the file is
  syntactically valid by construction; `dockerd --validate` is then used as the
  template's `validate` hook to catch unknown keys before the file is installed.

## Molecule

```bash
molecule test -s default   # run from roles/docker_host
```

The scenario runs a real `dockerd` inside a privileged container, overriding the
storage driver to `vfs` because an overlayfs container root cannot back
`overlay2`. Verification runs `hello-world` rather than only reading files back.
