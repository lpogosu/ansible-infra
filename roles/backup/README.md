# backup

Scheduled restic backups: a pinned checksum-verified binary, a repository that
is initialised only if it does not already exist, a wrapper script with
pre/post hooks and healthcheck pings, a systemd timer, retention with pruning,
periodic repository verification and log rotation.

## Requirements

- Debian 11/12, Ubuntu 20.04/22.04/24.04, or RHEL/Rocky/Alma 8/9
- Privilege escalation (`become: true`)
- `backup_repository`, `backup_password` and `backup_paths` must be set; the
  role refuses to run otherwise

## Role variables

### Binary

| Variable | Default | Purpose |
|---|---|---|
| `backup_restic_version` | `0.19.1` | Upstream release tag without the `v` |
| `backup_restic_checksums` | `{amd64: …, arm64: …}` | SHA-256 from the release `SHA256SUMS` |
| `backup_restic_binary_path` | `/usr/local/bin/restic` | Installed binary |
| `backup_restic_release_dir` | `/opt/restic` | Versioned copies, so a rollback needs no download |

### Repository

| Variable | Default | Purpose |
|---|---|---|
| `backup_repository` | *required* | `s3:…`, `sftp:…`, `rest:…` or a local path |
| `backup_password` | *required* | Keep it in Ansible Vault |
| `backup_password_file` | `/etc/restic/repository.password` | Mode `0600`; passed by path so it never appears in `ps` |
| `backup_env_file` | `/etc/restic/backup.env` | Mode `0600`; backend credentials |
| `backup_environment` | `{}` | e.g. `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` |
| `backup_init_repository` | `true` | Probe with `restic cat config`, initialise only if it fails |

### Contents

| Variable | Default | Purpose |
|---|---|---|
| `backup_paths` | *required* | Paths passed to `restic backup` |
| `backup_excludes` | pseudo-filesystems, caches, `/var/lib/docker` | Rendered into `backup_exclude_file` |
| `backup_one_file_system` | `true` | Keeps a bind mount or container overlay out of the snapshot |
| `backup_tags` | `[ansible]` | Applied to `backup` and matched by `forget` |
| `backup_extra_backup_args` | `[]` | Raw flags appended to `restic backup` |

### Retention and verification

| Variable | Default | Purpose |
|---|---|---|
| `backup_retention` | last 3, daily 7, weekly 4, monthly 6, yearly 1 | Rendered as `--keep-<unit>` |
| `backup_prune` | `true` | Without it `forget` only drops references and reclaims nothing |
| `backup_check_enabled` | `true` | Run `restic check` after every backup |
| `backup_check_read_data_subset` | `5%` | A full `--read-data` re-downloads the whole repository |

### Hooks and monitoring

| Variable | Default | Purpose |
|---|---|---|
| `backup_pre_commands` | `[]` | Shell lines run before the snapshot; a failure aborts the run |
| `backup_post_commands` | `[]` | Shell lines run after a successful snapshot |
| `backup_healthcheck_url` | `""` | `/start` before, bare URL on success, `/fail` with the log tail on error |
| `backup_healthcheck_timeout` | `10` | A monitoring outage never fails the backup |

### Schedule and limits

| Variable | Default | Purpose |
|---|---|---|
| `backup_schedule` | `*-*-* 02:30:00` | `OnCalendar` expression |
| `backup_randomized_delay` | `3600` | Spreads a fleet across the following hour |
| `backup_persistent` | `true` | Catch up after a missed window |
| `backup_nice` / `backup_io_scheduling_class` | `10` / `idle` | Keeps the backup out of the way of the workload |
| `backup_limit_upload_kib` / `backup_limit_download_kib` | `0` | `0` disables the limit |
| `backup_timeout_sec` | `14400` | Upper bound on one run |

### Logging

| Variable | Default | Purpose |
|---|---|---|
| `backup_log_file` | `/var/log/restic-backup.log` | Also duplicated to the journal |
| `backup_logrotate_rotate` | `14` | Rotations kept |
| `backup_logrotate_frequency` | `weekly` | Rotation interval |

## Handlers

| Handler | Triggered by |
|---|---|
| `Reload systemd units` | Unit or timer change |

## Notes

- The wrapper runs under `set -Eeuo pipefail` with an `ERR` trap, so any failing
  step — including a pre-hook — stops the run, pings `/fail` with the last 40
  log lines and exits non-zero. A backup that "succeeded" while a database dump
  failed is worse than no backup.
- The wrapper is installed through the template's `validate` hook
  (`bash -n %s`), and the logrotate drop-in through `logrotate --debug %s`;
  logrotate refuses to run at all when one config file is malformed, so a bad
  drop-in would silently stop rotating every other log on the host.
- `copytruncate` is used deliberately: the wrapper keeps the log open through a
  `tee` for the whole run, so renaming the file would leave the running backup
  writing into an unlinked inode.

## Molecule

```bash
molecule test -s default   # run from roles/backup
```

Verification is behavioural rather than declarative: it starts the unit, checks
that exactly one tagged snapshot appeared, restores it to a scratch directory
and compares the checksum of the restored file with the source. The pre-hook
writes a file and the post-hook deletes it, so the file being *in the restore*
and *absent on disk* proves both hooks ran, in the right order, inside the same
run.
