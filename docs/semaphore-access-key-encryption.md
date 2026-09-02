# Semaphore access-key encryption

Semaphore encrypts Key Store entries and Variable Group secrets at rest. The key
that does this is held in `/etc/semaphore/config.json`, **inside the container
filesystem** — it is not on a volume.

`SEMAPHORE_ACCESS_KEY_ENCRYPTION` must therefore be pinned in `.env`. It is not
optional, and `docker-compose.yml` refuses to start the stack without it.

## What happens if it is not pinned

On start, the entrypoint finds no config and re-runs `semaphore setup`, which
generates a **new random encryption key**. The database volume
(`semaphore_db_data_pg18`) survives the recreate, still holding every secret
encrypted under the *previous* key. Semaphore can no longer decrypt any of them.

The symptoms do not point at the cause:

| What you see | What is actually happening |
|---|---|
| `Network Error` in the New Task dialog | `AddTask` panics server-side, so the browser gets a dropped connection rather than an error |
| Empty playbook dropdown on a Task Template | The repository's access key cannot be decrypted |
| A previously working Key Store entry stops authenticating | Same, for that key |

The only honest diagnosis comes from the container log:

```bash
docker compose logs semaphore | grep -i keyset
```

```
encryption key id "..." not found in keyset (the key encrypting this value is missing)
```

Because the encryption is per-value, this is silent until something actually
reads a secret — which is usually the first time you try to run a task, well
after the recreate that caused it.

## Setting it up

```bash
task semaphore:genkey
```

Put the value in `.env`:

```
SEMAPHORE_ACCESS_KEY_ENCRYPTION=<the generated value>
```

**Back it up in a password manager.** This is the one piece of Semaphore state
that cannot be rebuilt from this repository. Without it, the contents of the
database are cryptographically unrecoverable — not inconvenient, gone.

Then verify the running container agrees with `.env`:

```bash
task semaphore:encryption-check
```

## Recovering an instance that already hit this

The orphaned rows cannot be decrypted; the key that would do it no longer
exists. There is no repair, only a rebuild.

On an instance with little in it, drop the database volume and recreate the
Semaphore objects:

```bash
docker compose down -v
task up
```

`docker compose down -v` **destroys every volume in the stack**, which here
includes Vault, Wiki.js, Portainer and Nginx Proxy Manager — not just Semaphore.
Do not run it on an established stack. To remove only Semaphore's database:

```bash
docker compose rm -sf semaphore semaphore-db
docker volume rm devops-server_semaphore_db_data_pg18
task up
```

Check the volume's actual name first with `docker volume ls`; the prefix follows
the compose project name, which defaults to the directory.

Afterwards, recreate the Key Store entries, Repositories, Inventories, Variable
Groups and Task Templates. Nothing else in the stack is affected.

## Why not store the key in Vault

Vault is in this stack and is the natural home for a secret like this, but it
cannot be the source here: Semaphore needs the value at process start, before
Vault is reliably unsealed, and a sealed Vault would leave Semaphore unable to
start at all. Keep the operative copy in `.env` and treat Vault or the password
manager as the backup of record.
