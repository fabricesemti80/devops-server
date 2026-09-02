# Semaphore host-management prerequisites

The repository builds a thin image on top of the official Semaphore image so
the dependencies needed for Windows management and Linux password
authentication survive container recreation.

## Included runtime dependencies

| Package | Used for | Typical error when missing |
|---|---|---|
| `pywinrm` | Connecting to Windows hosts through WinRM | `No module named 'winrm'` |
| `requests-ntlm` | WinRM connections using NTLM transport | NTLM negotiation fails |
| `sshpass` | Password-based SSH to Linux hosts | `you must install the sshpass program` |

The Python packages are installed into the Ansible virtual environment inherited
from the official Semaphore image. The image build fails if `sshpass` cannot
be found or either Python module cannot be imported.

## Build and deploy

Normal host:

```bash
task up
```

Host behind TLS inspection:

```bash
task up:ca-trust
```

Both tasks build the custom Semaphore image before starting the stack. To force
a fresh base-image pull and rebuild:

```bash
task build:semaphore
task up:ca-trust
```

## Verify the running container

```bash
task semaphore:prereqs
```

The task fails if `sshpass`, `winrm`, or `requests_ntlm` is unavailable.

## Semaphore configuration guidance

Store connection credentials in Semaphore's Key Store rather than committing
passwords to inventories or repositories.

For Windows inventory groups, configure the appropriate Ansible connection
variables, for example:

```yaml
windows:
  vars:
    ansible_connection: winrm
    ansible_winrm_transport: ntlm
    ansible_port: 5986
    ansible_winrm_server_cert_validation: ignore
```

Use `ansible_winrm_server_cert_validation: ignore` only where the WinRM
listener certificate cannot yet be validated. Prefer distributing the issuing
CA and validating the certificate.

For Linux hosts using passwords, select a login/password key in Semaphore and
use the normal SSH connection. Public-key authentication remains preferable
where it is available.
