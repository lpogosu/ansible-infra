# node_exporter

Installs a pinned, checksum-verified `node_exporter` release under a dedicated
system account and a systemd unit that takes away everything the exporter does
not need. Includes a textfile collector directory for custom metrics.

## Requirements

- Debian 11/12, Ubuntu 20.04/22.04/24.04, or RHEL/Rocky/Alma 8/9
- systemd 240+ (for `ProtectKernelLogs`, `ProtectClock`, `ProtectProc`)
- Outbound access to `github.com` for the release tarball
- Privilege escalation (`become: true`)

## Role variables

### Version and integrity

| Variable | Default | Purpose |
|---|---|---|
| `node_exporter_version` | `1.12.1` | Upstream release tag without the `v` |
| `node_exporter_checksums` | `{amd64: …, arm64: …}` | SHA-256 from the release's `sha256sums.txt`; a missing entry fails the role rather than installing unverified bytes |
| `node_exporter_architecture` | derived from facts | `x86_64` → `amd64`, `aarch64` → `arm64` |
| `node_exporter_download_url` | GitHub release URL | Point at an internal mirror if egress is closed |

### Layout

| Variable | Default | Purpose |
|---|---|---|
| `node_exporter_release_dir` | `/opt/node_exporter` | Releases unpacked into `<dir>/<release name>/` |
| `node_exporter_binary_path` | `/usr/local/bin/node_exporter` | Installed binary |
| `node_exporter_state_dir` | `/var/lib/node_exporter` | Only writable path in the unit |
| `node_exporter_textfile_dir` | `/var/lib/node_exporter/textfile_collector` | `*.prom` files, mode `0775` |

### Runtime

| Variable | Default | Purpose |
|---|---|---|
| `node_exporter_listen_address` | `127.0.0.1:9100` | Loopback by default; the exporter publishes the host's full inventory |
| `node_exporter_telemetry_path` | `/metrics` | Scrape path |
| `node_exporter_collectors_enabled` | `processes`, `textfile` | `systemd` is deliberately absent, see below |
| `node_exporter_collectors_disabled` | `arp`, `bcache`, `nfs`, `zfs`, … | Collectors with no meaning on a typical server |
| `node_exporter_extra_args` | `[]` | Raw flags appended to `ExecStart` |

### Sandbox

| Variable | Default | Purpose |
|---|---|---|
| `node_exporter_protect_system` | `strict` | Entire hierarchy read-only except the paths below |
| `node_exporter_protect_home` | `read-only` | Not `yes`: a masked `/home` would make the filesystem collector report the mask instead of the real mount |
| `node_exporter_private_devices` | `true` | No `/dev` access |
| `node_exporter_memory_deny_write_execute` | `true` | No W+X mappings |
| `node_exporter_system_call_filter` | `@system-service` | seccomp allow-list |
| `node_exporter_restrict_address_families` | `AF_INET AF_INET6 AF_UNIX` | Everything else is blocked |
| `node_exporter_read_write_paths` | `[/var/lib/node_exporter]` | The only writable location |

The unit also sets `CapabilityBoundingSet=` (empty), `NoNewPrivileges`,
`ProtectKernelTunables/Modules/Logs`, `ProtectControlGroups`, `ProtectClock`,
`ProtectHostname`, `RestrictNamespaces`, `RestrictSUIDSGID`, `LockPersonality`,
`SystemCallArchitectures=native` and `UMask=0077`.

## Handlers

| Handler | Triggered by |
|---|---|
| `Reload systemd units` | Unit file change |
| `Restart node_exporter` | Binary or unit change |

## Notes

- The `systemd` collector is not enabled. It talks to `/run/systemd/private`,
  which needs root and a writable `/run`, so enabling it means giving up
  `ProtectSystem=strict` and the empty capability set for a handful of
  unit-state series. Export those from a textfile script instead.
- Releases are unpacked into a versioned directory and the binary is copied,
  not symlinked, so the previous release stays on disk and a rollback is a
  variable change rather than another download.
- The role does not open a firewall port. Binding to loopback and scraping
  through a tunnel, or an explicit firewall rule from another role, are both
  deliberate decisions that do not belong in an exporter role.

## Molecule

```bash
molecule test -s default   # run from roles/node_exporter
```

Verification reads the sandbox back from `systemctl show` rather than from the
template, writes a `.prom` file into the textfile directory and asserts the
metric appears in a live scrape, and checks that the disabled collectors are
absent from `node_scrape_collector_success`.
