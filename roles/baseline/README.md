# baseline

CIS-informed hardening applied to every managed host: SSH daemon, kernel and
network tunables, auditd, password policy, unattended security updates,
journald retention, time synchronisation, login banners and blacklisted
filesystem modules.

Each block is behind its own switch, so a host group can opt out of a single
control without forking the role.

## Requirements

- Debian 11/12, Ubuntu 20.04/22.04/24.04, or RHEL/Rocky/Alma 8/9
- `ansible.posix` collection (kernel tunables)
- Privilege escalation (`become: true`)

## Role variables

### Feature switches

| Variable | Default | Purpose |
|---|---|---|
| `baseline_manage_packages` | `true` | Install the base package set, remove telnet/rsh clients |
| `baseline_manage_sshd` | `true` | Write the sshd hardening drop-in |
| `baseline_manage_sysctl` | `true` | Apply kernel and network tunables |
| `baseline_manage_auditd` | `true` | Install and configure the audit daemon |
| `baseline_manage_accounts` | `true` | Password ageing, complexity, umask |
| `baseline_manage_auto_updates` | `true` | unattended-upgrades / dnf-automatic |
| `baseline_manage_journald` | `true` | Bound journal size and retention |
| `baseline_manage_time` | `true` | chrony, with systemd-timesyncd masked |
| `baseline_manage_banner` | `true` | `/etc/issue` and `/etc/issue.net` |
| `baseline_manage_filesystems` | `true` | Blacklist unused filesystem modules |

### SSH daemon

| Variable | Default | Purpose |
|---|---|---|
| `baseline_sshd_dropin_path` | `/etc/ssh/sshd_config.d/01-hardening.conf` | Where the drop-in is written |
| `baseline_sshd_ensure_include` | `true` | Add the `Include` directive if the distro config lacks it |
| `baseline_sshd_port` | `22` | Listening port |
| `baseline_sshd_permit_root_login` | `"no"` | Also accepts `prohibit-password` |
| `baseline_sshd_password_authentication` | `false` | Keys only |
| `baseline_sshd_max_auth_tries` | `3` | Failed attempts before disconnect |
| `baseline_sshd_login_grace_time` | `30` | Seconds to complete authentication |
| `baseline_sshd_client_alive_interval` | `300` | Idle keepalive probe interval |
| `baseline_sshd_allow_groups` | `[sudo, wheel]` | `AllowGroups`; empty list omits the directive |
| `baseline_sshd_ciphers` | ChaCha20 / AES-GCM / AES-CTR | No CBC |
| `baseline_sshd_kex_algorithms` | sntrup761x25519, curve25519, DH group 16/18 | No SHA-1, no NIST curves |
| `baseline_sshd_macs` | SHA-2 ETM, umac-128-etm | Encrypt-then-MAC only |
| `baseline_sshd_host_key_algorithms` | ed25519, rsa-sha2 | No `ssh-rsa` (SHA-1) |

### Kernel tunables

| Variable | Default | Purpose |
|---|---|---|
| `baseline_sysctl_file` | `/etc/sysctl.d/99-hardening.conf` | Drop-in written by the role |
| `baseline_sysctl_settings` | 33 keys | Mapping of sysctl key to value; replace wholesale or merge with `combine` |

### auditd

| Variable | Default | Purpose |
|---|---|---|
| `baseline_auditd_rules_file` | `/etc/audit/rules.d/99-hardening.rules` | Rule file loaded by `augenrules` |
| `baseline_auditd_immutable` | `false` | Append `-e 2`; rule changes then need a reboot |
| `baseline_auditd_buffer_size` | `8192` | Kernel backlog (`-b`) |
| `baseline_auditd_max_log_file` | `32` | Megabytes per log file |
| `baseline_auditd_num_logs` | `5` | Rotated files kept |
| `baseline_auditd_admin_space_left_action` | `halt` | Action when the audit partition is nearly full |
| `baseline_auditd_watch_files` | 9 paths | `{path, permissions, key}` watches |
| `baseline_auditd_watch_syscalls` | 5 groups | `{syscall, key}`, emitted for b32 and b64 |
| `baseline_auditd_extra_rules` | `[]` | Raw rule lines appended verbatim |

### Accounts and passwords

| Variable | Default | Purpose |
|---|---|---|
| `baseline_login_defs` | `PASS_MAX_DAYS: 365`, … | Key/value pairs enforced in `/etc/login.defs` |
| `baseline_umask` | `"027"` | Default umask for interactive shells |
| `baseline_manage_pwquality` | `true` | Install and configure `pam_pwquality` |
| `baseline_pwquality` | `minlen: 14`, `minclass: 4`, … | Rendered into `pwquality.conf` |
| `baseline_useradd_inactive_days` | `30` | `INACTIVE=` in `/etc/default/useradd` |

### Updates, logs, time, banners

| Variable | Default | Purpose |
|---|---|---|
| `baseline_auto_updates_apply_updates` | `true` | Install security updates, not just download them |
| `baseline_auto_updates_reboot` | `false` | Never reboot on the package manager's schedule by default |
| `baseline_auto_updates_random_sleep` | `1800` | Spread fleet-wide mirror load |
| `baseline_auto_updates_blacklist` | `[]` | Packages excluded from automatic upgrades |
| `baseline_journald_system_max_use` | `512M` | Hard cap on journal size |
| `baseline_journald_max_retention` | `30day` | Retention window |
| `baseline_chrony_servers` | `*.pool.ntp.org` | List of `{address, options}` |
| `baseline_banner_text` | legal notice | Written to `/etc/issue` and `/etc/issue.net` |
| `baseline_disabled_filesystems` | cramfs, freevxfs, … | Modules blacklisted in `/etc/modprobe.d/` |

## Handlers

| Handler | Triggered by |
|---|---|
| `Restart sshd` | Drop-in or `Include` change |
| `Restart auditd` | `auditd.conf` change (SysV wrapper on RHEL, systemd on Debian) |
| `Reload audit rules` | Rule file change; runs `augenrules --load` |
| `Restart journald` | journald drop-in change |
| `Restart chrony` | `chrony.conf` change |

## Notes

- The sshd drop-in is validated with `sshd -t -f` *before* it is installed, so a
  malformed template cannot lock the operator out of the host.
- Kernel tunables are the only settings applied through a module rather than a
  template: a rendered file guarantees the value at next boot, the module also
  pushes it into the running kernel.
- Loaded blacklisted modules are not unloaded. `modprobe -r` fails on a module
  that is in use, and on an unused one it changes nothing that the blacklist has
  not already covered for the next boot.

## Molecule

```bash
molecule test -s default   # run from roles/baseline
```

The scenario disables auditd and chrony management, and narrows the sysctl set
to network-namespaced keys — see the comments in `molecule/default/molecule.yml`
for why a container cannot exercise those controls honestly.
