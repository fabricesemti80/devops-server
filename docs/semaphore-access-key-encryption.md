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

Generate a 32-byte random value, base64-encoded:

```bash
task semaphore:genkey
```

Or directly, if Task is not installed yet — `.env` normally gets filled in
before the rest of the tooling is up:

```bash
openssl rand -base64 32
```

Any 32 bytes of cryptographic randomness will do; these are equivalent:

```bash
head -c 32 /dev/urandom | base64
python3 -c 'import os,base64; print(base64.b64encode(os.urandom(32)).decode())'
```

Put the value in `.env`:

```
SEMAPHORE_ACCESS_KEY_ENCRYPTION=<the generated value>
```

Do not reuse a password or a value from elsewhere, and do not commit it —
`.env` is gitignored; `.env.example` carries the name only.

**Back it up in a password manager.** This is the one piece of Semaphore state
that cannot be rebuilt from this repository. Without it, the contents of the
database are cryptographically unrecoverable — not inconvenient, gone.

Back up the **`.env` value**, not `/etc/semaphore/config.json`. That file also
carries the Postgres password, is regenerated on every start, and — see below —
does not hold the key actually in use. If you do copy it out for any reason,
delete the copy afterwards; nothing in `.gitignore` covers it.

## Why config.json shows a different key

`/etc/semaphore/config.json` will contain an `access_key_encryption` value that
**does not match** `.env`. This is expected and harmless, and it is worth
knowing before it costs you an afternoon.

On every start, the entrypoint runs `semaphore setup`, which generates a fresh
random key and writes it to `config.json`. The Semaphore binary then loads that
file and applies environment overrides on top of it. The config struct carries
both bindings:

```
AccessKeyEncryption  json:"access_key_encryption,omitempty" env:"SEMAPHORE_ACCESS_KEY_ENCRYPTION,sensitive"
```

The environment value wins, so `config.json`'s copy is an unused artefact of
setup. Verified empirically on v2.19.12: with the variable set, Key Store
entries survive `docker compose up -d --force-recreate semaphore` and remain
usable, even though `config.json` holds a different value before and after.

The practical consequences:

- **Do not diff `.env` against `config.json`** to check the pin. They differ by
  design, and treating that as a fault sends you looking for a problem that
  isn't there.
- `task semaphore:encryption-check` therefore validates the variable itself —
  present, valid base64, 32 bytes — and nothing else. That is the whole of what
  is statically checkable.
- The only real proof is behavioural: create a Key Store entry, force-recreate
  the container, and confirm the entry still works. Take a copy of
  `config.json` first and that test is fully reversible — restore it with
  `docker cp` and `docker restart semaphore` if anything goes wrong.

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
