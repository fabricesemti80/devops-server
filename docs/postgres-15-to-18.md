# PostgreSQL 15 to 18 migration

This migration uses logical backups so PostgreSQL 18 never opens PostgreSQL 15
data files. The old named volumes are retained unchanged for rollback, while
PostgreSQL 18 receives new version-specific volumes.

## What changes

| Database | PostgreSQL 15 volume | PostgreSQL 18 volume |
|---|---|---|
| Wiki.js | `devops-server_wikijs_db_data` | `devops-server_wikijs_db_data_pg18` |
| Semaphore | `devops-server_semaphore_db_data` | `devops-server_semaphore_db_data_pg18` |

PostgreSQL 18 changes the official image's persistent mount point from
`/var/lib/postgresql/data` to `/var/lib/postgresql`. The new Compose
configuration uses the PostgreSQL 18 mount point.

## Preconditions

- Merge or check out this migration branch, but do not run `task up` yet.
- Confirm the existing PostgreSQL 15 volumes:
  ```bash
  docker volume ls | grep devops-server
  ```
- Confirm `.env` contains the existing database usernames, passwords and names.
- Ensure enough free disk space for two logical backups and two new database volumes.
- Take a VM/storage snapshot as an additional rollback point if available.

If the Compose project previously used another directory or project name, set
`WIKI_PG15_VOLUME` and `SEMAPHORE_PG15_VOLUME` in `.env` to the actual
legacy Docker volume names.

## 1. Back up PostgreSQL 15

```bash
task postgres:backup:15
```

This task:

1. confirms both legacy volumes exist;
2. stops the application stack without deleting volumes;
3. attaches each old volume to a temporary PostgreSQL 15 container;
4. creates custom-format logical dumps in `backups/postgres-15`;
5. writes SHA-256 hashes and source-volume names to `manifest.txt`.

Inspect the output before continuing:

```bash
cat backups/postgres-15/manifest.txt
ls -lh backups/postgres-15/*.dump
```

Copy this backup directory off-host before a production migration.

## 2. Restore into PostgreSQL 18

```bash
task postgres:restore:18
```

This starts only the two PostgreSQL 18 services, initializes their new volumes,
restores both dumps and runs verification. It does not delete or modify the
PostgreSQL 15 volumes.

## 3. Start and validate the applications

On a normal host:

```bash
task up
```

On a host behind TLS inspection:

```bash
task up:ca-trust
```

Then validate:

```bash
task postgres:verify:18
docker compose ps
docker compose logs --tail=100 wikijs semaphore wikijs-db semaphore-db
```

Functional checks:

- sign in to Semaphore and run a repository-backed template;
- sign in to Wiki.js and confirm existing pages are present;
- create a disposable record/page in each application and confirm it persists
  after container recreation.

## Rollback

Do not delete the PostgreSQL 15 volumes until the migration has been accepted.

To roll back:

1. stop the PostgreSQL 18 stack with `task down` or `task down:ca-trust`;
2. check out the last PostgreSQL 15 revision;
3. run `task up` or `task up:ca-trust`;
4. verify that the applications reconnect to the retained PostgreSQL 15 volumes.

Data written after PostgreSQL 18 goes live is not automatically copied back to
PostgreSQL 15. If rollback occurs after users resume work, preserve the
PostgreSQL 18 volumes and reconcile that data separately.

## Cleanup

After the acceptance period and a verified off-host backup, identify both old
volumes explicitly:

```bash
docker volume inspect devops-server_wikijs_db_data
docker volume inspect devops-server_semaphore_db_data
```

Remove them only through a separately reviewed change or manual maintenance
step. The migration tasks intentionally never delete database volumes.
