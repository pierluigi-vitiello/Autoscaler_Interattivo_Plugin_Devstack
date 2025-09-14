# Interactive Autoscaler – DevStack Plugin

DevStack plugin + interactive tools to **resize an OpenStack VM** (e.g., `as.small` ⇄ `as.medium`) via a **colored, one‑key TUI** and an optional **demo mode**.

## Key Features

- Flavor **UP/DOWN** resizing for a target VM.
- **Status** check (flavor, IP, power, task, etc.).
- **Demo loop** toggling resize every *n* seconds.
- **Auto‑skip** if the VM already matches the desired flavor.
- Scripts tailored for **DevStack** (user `stack`).

---

## Requirements

- Ubuntu 22.04 / 24.04 recommended, with DevStack.
- `stack` user with `NOPASSWD` sudo.
- **OpenStackClient** available as `openstack` in `PATH`.
- Working network + Internet access (for GitHub installation).
- A **Cirros** image in Glance (e.g., `cirros-0.6.3-x86_64-disk`).
- Test flavors: `as.small`, `as.medium` (the plugin handles/validates them).

> Suggested: VM with ≥ 8 GB RAM and ≥ 40 GB disk for smoother tests.

---

## Installation (A) – From GitHub (recommended)

1. **Prepare DevStack** (if not already present):
   ```bash
   # as root (or via sudo)
   adduser --disabled-password --gecos "" stack || true
   echo "stack ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/stack
   chmod 440 /etc/sudoers.d/stack

   apt update && apt -y install git vim curl
   mkdir -p /opt/stack && chown -R stack:stack /opt/stack
   su - stack

   # Clone DevStack
   cd /opt/stack
   git clone https://opendev.org/openstack/devstack.git
   cd devstack
   ```

2. **Create `local.conf`** with the plugin enabled (GitHub):
   ```ini
   [[local|localrc]]
   ADMIN_PASSWORD=admin
   DATABASE_PASSWORD=$ADMIN_PASSWORD
   RABBIT_PASSWORD=$ADMIN_PASSWORD
   SERVICE_PASSWORD=$ADMIN_PASSWORD
   SERVICE_TOKEN=$ADMIN_PASSWORD
   HOST_IP=YOUR_HOST_IP
   OS_IDENTITY_API_VERSION=3

   # Enable the plugin from GitHub repository
   enable_plugin autoscaler-interattivo-plugin https://github.com/pierluigi-vitiello/Autoscaler_Interattivo_Plugin_Devstack.git

   # Customizable plugin variables (override defaults)
   AUTOSCALER_SERVER_NAME=auto-vm-1
   AUTOSCALER_IMAGE_NAME=cirros-0.6.3-x86_64-disk
   AUTOSCALER_FLAVOR_SMALL=as.small
   AUTOSCALER_FLAVOR_MEDIUM=as.medium
   ```

3. **Bring DevStack up**:
   ```bash
   cd /opt/stack/devstack
   ./stack.sh
   ```

4. **Run the tool**:
   ```bash
   # credentials (admin/admin) – adapt to your env
   source /opt/stack/devstack/openrc admin admin

   # launch interactive TUI
   /opt/stack/autoscaler-interattivo-plugin/bin/run_autoscaler_interactive.sh
   ```

---

## Installation (B) – Local sources (folder or ZIP)

1. **Copy the plugin into `/opt/stack`**:
   ```bash
   sudo rm -rf /opt/stack/autoscaler-interattivo-plugin
   sudo cp -a /path/to/your/autoscaler-interattivo-plugin /opt/stack/
   sudo chown -R stack:stack /opt/stack/autoscaler-interattivo-plugin
   ```

2. **Configure `local.conf`** to use the local path:
   ```ini
   [[local|localrc]]
   ADMIN_PASSWORD=admin
   DATABASE_PASSWORD=$ADMIN_PASSWORD
   RABBIT_PASSWORD=$ADMIN_PASSWORD
   SERVICE_PASSWORD=$ADMIN_PASSWORD
   SERVICE_TOKEN=$ADMIN_PASSWORD
   HOST_IP=YOUR_HOST_IP
   OS_IDENTITY_API_VERSION=3

   # Enable the plugin from local folder
   enable_plugin autoscaler-interattivo-plugin file:///opt/stack/autoscaler-interattivo-plugin

   # Customizable variables
   AUTOSCALER_SERVER_NAME=auto-vm-1
   AUTOSCALER_IMAGE_NAME=cirros-0.6.3-x86_64-disk
   AUTOSCALER_FLAVOR_SMALL=as.small
   AUTOSCALER_FLAVOR_MEDIUM=as.medium
   ```

3. **Rebuild DevStack** (if already installed):
   ```bash
   cd /opt/stack/devstack
   ./unstack.sh || true
   ./clean.sh   || true
   ./stack.sh
   ```

4. **Launch**:
   ```bash
   source /opt/stack/devstack/openrc admin admin
   /opt/stack/autoscaler-interattivo-plugin/bin/run_autoscaler_interactive.sh
   ```

---

## Repository layout

```
autoscaler-interattivo-plugin/
├─ devstack/
│  ├─ plugin.sh
│  └─ settings
├─ bin/
│  ├─ run_autoscaler_interactive.sh
│  ├─ demo_body.sh
│  └─ check_flavor.py
├─ openrc.autoscaler   # (optional) dedicated creds
└─ README, INSTALL, etc.
```

- `devstack/plugin.sh` and `devstack/settings` wire the plugin into DevStack phases.
- `bin/run_autoscaler_interactive.sh` launches the TUI.
- `bin/demo_body.sh` toggles up/down resizes (demo).
- `bin/check_flavor.py` queries current VM flavor.

---

## Credentials & Environment (`OS_*`)

Ensure your `OS_` variables are set (typical example):
```bash
export OS_AUTH_URL=http://<HOST_IP>/identity/v3
export OS_USERNAME=admin
export OS_PASSWORD=admin
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_REGION_NAME=RegionOne
export OS_INTERFACE=public
export OS_IDENTITY_API_VERSION=3
```

If available, you can `source openrc.autoscaler` or DevStack’s `openrc`.

---

## Quick commands

- **Token**: `openstack token issue`
- **Flavors**: `openstack flavor list`
- **Images**: `openstack image list`
- **Servers**: `openstack server list`

---

## Troubleshooting

- **Keystone v3**: always use `/identity/v3`.
- **Missing Cirros**: import a valid image or update `AUTOSCALER_IMAGE_NAME`.
- **Missing flavors**: create `as.small`/`as.medium` or adjust variable names.
- **CLI not found**: ensure `openstack` is in the user’s `PATH`.
- **Rerun**: try `./unstack.sh && ./clean.sh && ./stack.sh` when in doubt.
- **Permissions**: run scripts as `stack` (not root).

---

## Uninstall

- Remove the `enable_plugin ...` line from `local.conf`.
- Run `./unstack.sh && ./clean.sh && ./stack.sh` to rebuild without the plugin.

---

## License

See LICENSE if present in this repository.
