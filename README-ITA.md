# Autoscaler Interattivo – Plugin DevStack

Plugin DevStack + strumenti interattivi per **ridimensionare una VM su OpenStack/DevStack** (es. `as.small` ⇄ `as.medium`) tramite **interfaccia a colori** con menu a tasto singolo e una **modalità demo** opzionale.

## Funzionalità principali

- Ridimensionamento **UP/DOWN** del flavor della VM target.
- **Check** stato corrente (flavor, IP, power, task, ecc.).
- **Demo loop**: alterna automaticamente i resize ogni *n* secondi.
- **Auto-skip** se la VM è già nel flavor richiesto.
- Script pensati per ambiente **DevStack** (utente `stack`).

---

## Requisiti

- Ubuntu 22.04 / 24.04 consigliata, con DevStack.
- Utente `stack` con `NOPASSWD` sudo.
- **OpenStackClient** disponibile come `openstack` nella `PATH`.
- Rete funzionante e accesso a Internet (per installazione da GitHub).
- Un’immagine **Cirros** disponibile in Glance (es. `cirros-0.6.3-x86_64-disk`).
- Flavors di test: `as.small`, `as.medium` (il plugin li gestisce/valida).

> Suggerito: VM con ≥ 8 GB RAM e ≥ 40 GB disco per test più fluidi.

---

## Installazione (A) – da GitHub (consigliata)

1. **Prepara DevStack** (solo se non già presente):
   ```bash
   # come root (o con sudo)
   adduser --disabled-password --gecos "" stack || true
   echo "stack ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/stack
   chmod 440 /etc/sudoers.d/stack

   apt update && apt -y install git vim curl
   mkdir -p /opt/stack && chown -R stack:stack /opt/stack
   su - stack

   # Clona DevStack
   cd /opt/stack
   git clone https://opendev.org/openstack/devstack.git
   cd devstack
   ```

2. **Crea `local.conf`** con il plugin abilitato (GitHub):
   ```ini
   [[local|localrc]]
   ADMIN_PASSWORD=admin
   DATABASE_PASSWORD=$ADMIN_PASSWORD
   RABBIT_PASSWORD=$ADMIN_PASSWORD
   SERVICE_PASSWORD=$ADMIN_PASSWORD
   SERVICE_TOKEN=$ADMIN_PASSWORD
   HOST_IP=YOUR_HOST_IP
   OS_IDENTITY_API_VERSION=3

   # Abilita il plugin dal repository GitHub
   enable_plugin autoscaler-interattivo-plugin https://github.com/pierluigi-vitiello/Autoscaler_Interattivo_Plugin_Devstack.git

   # Variabili personalizzabili del plugin (override dei default)
   AUTOSCALER_SERVER_NAME=auto-vm-1
   AUTOSCALER_IMAGE_NAME=cirros-0.6.3-x86_64-disk
   AUTOSCALER_FLAVOR_SMALL=as.small
   AUTOSCALER_FLAVOR_MEDIUM=as.medium
   ```

3. **Avvia DevStack**:
   ```bash
   cd /opt/stack/devstack
   ./stack.sh
   ```

4. **Usa lo strumento**:
   ```bash
   # credenziali (admin/admin) – adatta al tuo ambiente
   source /opt/stack/devstack/openrc admin admin

   # avvio interfaccia interattiva
   /opt/stack/autoscaler-interattivo-plugin/bin/run_autoscaler_interactive.sh
   ```

---

## Installazione (B) – Sorgenti locali (cartella o ZIP)

1. **Copia il plugin in `/opt/stack`**:
   ```bash
   sudo rm -rf /opt/stack/autoscaler-interattivo-plugin
   sudo cp -a /path/al/tuo/autoscaler-interattivo-plugin /opt/stack/
   sudo chown -R stack:stack /opt/stack/autoscaler-interattivo-plugin
   ```

2. **Configura `local.conf`** per usare il percorso locale:
   ```ini
   [[local|localrc]]
   ADMIN_PASSWORD=admin
   DATABASE_PASSWORD=$ADMIN_PASSWORD
   RABBIT_PASSWORD=$ADMIN_PASSWORD
   SERVICE_PASSWORD=$ADMIN_PASSWORD
   SERVICE_TOKEN=$ADMIN_PASSWORD
   HOST_IP=YOUR_HOST_IP
   OS_IDENTITY_API_VERSION=3

   # Abilita il plugin da percorso locale
   enable_plugin autoscaler-interattivo-plugin file:///opt/stack/autoscaler-interattivo-plugin

   # Variabili personalizzabili
   AUTOSCALER_SERVER_NAME=auto-vm-1
   AUTOSCALER_IMAGE_NAME=cirros-0.6.3-x86_64-disk
   AUTOSCALER_FLAVOR_SMALL=as.small
   AUTOSCALER_FLAVOR_MEDIUM=as.medium
   ```

3. **Ricostruisci DevStack** (se già installato):
   ```bash
   cd /opt/stack/devstack
   ./unstack.sh || true
   ./clean.sh   || true
   ./stack.sh
   ```

4. **Avvio**:
   ```bash
   source /opt/stack/devstack/openrc admin admin
   /opt/stack/autoscaler-interattivo-plugin/bin/run_autoscaler_interactive.sh
   ```

---

## Layout del repository

```
autoscaler-interattivo-plugin/
├─ devstack/
│  ├─ plugin.sh
│  └─ settings
├─ bin/
│  ├─ run_autoscaler_interactive.sh
│  ├─ demo_body.sh
│  └─ check_flavor.py
├─ openrc.autoscaler   # (opzionale) credenziali dedicate
└─ README, INSTALL, ecc.
```

- `devstack/plugin.sh` e `devstack/settings` definiscono l’hook del plugin per gli step di DevStack.
- `bin/run_autoscaler_interactive.sh` lancia l’interfaccia testuale.
- `bin/demo_body.sh` esegue ciclicamente resize up/down (per demo).
- `bin/check_flavor.py` interroga lo stato flavor corrente di una VM.

---

## Credenziali & ambiente (`OS_*`)

Per eseguire i comandi OpenStack, assicurati che le variabili `OS_` siano corrette (esempio tipico):
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

Se presente, puoi `source openrc.autoscaler` fornito dal progetto o usare `openrc` di DevStack.

---

## Esempi rapidi

- **Stato token**: `openstack token issue`
- **Lista flavor**: `openstack flavor list`
- **Immagini**: `openstack image list`
- **Server esistenti**: `openstack server list`

---

## Troubleshooting

- **Keystone v3**: usa sempre l’endpoint con `/identity/v3`.
- **Cirros mancante**: importa un’immagine valida o aggiorna `AUTOSCALER_IMAGE_NAME`.
- **Flavors mancanti**: crea `as.small` e `as.medium` o adatta i nomi nelle variabili.
- **CLI non trovata**: verifica che `openstack` sia nella `PATH` del tuo utente.
- **Riesecuzione**: in caso di errori, prova `./unstack.sh && ./clean.sh && ./stack.sh`.
- **Permessi**: lancia gli script come utente `stack` (non root).

---

## Disinstallazione

- Rimuovi la riga `enable_plugin ...` dal `local.conf`.
- Esegui `./unstack.sh && ./clean.sh && ./stack.sh` per ricreare l’ambiente senza il plugin.

---

## Licenza

Vedi file LICENSE se presente nel repository.
