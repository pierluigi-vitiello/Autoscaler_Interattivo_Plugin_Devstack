# Installazione

## 1) Copia in /opt/stack

```bash
cd /opt/stack
sudo rm -rf /opt/stack/autoscaler-interattivo-plugin
sudo cp -a /mnt/data/autoscaler-interattivo-plugin /opt/stack/
sudo chown -R stack:stack /opt/stack/autoscaler-interattivo-plugin
```

## 2) Abilita in local.conf

**Variante GitHub:**
```ini
[[local|localrc]]
enable_plugin autoscaler-interattivo-plugin https://github.com/pierluigi-vitiello/autoscaler-interattivo-plugin.git
```

**Variante locale:**
```ini
[[local|localrc]]
autoscaler-interattivo-plugin_repo=/opt/stack/autoscaler-interattivo-plugin
autoscaler-interattivo-plugin_branch=master
enable_plugin autoscaler-interattivo-plugin file:///opt/stack/autoscaler-interattivo-plugin
```

## 3) Ricostruisci DevStack
```bash
cd /opt/stack/devstack
./unstack.sh || true
./clean.sh || true
./stack.sh
```

## 4) Usa lo strumento
```bash
source /opt/stack/devstack/openrc admin admin
/opt/stack/autoscaler-interattivo-plugin/bin/run_autoscaler_interactive.sh
```
