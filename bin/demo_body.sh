#!/usr/bin/env bash
set -Eeuo pipefail
[[ -z "${OS_AUTH_URL:-}" ]] && { [[ -f "$HOME/devstack/openrc.autoscaler" ]] && source "$HOME/devstack/openrc.autoscaler" || { echo "[err] OS_* mancanti"; exit 1; }; }
SERVER_NAME="${AUTOSCALER_SERVER_NAME:-auto-vm-1}"
FLV_SMALL="${AUTOSCALER_FLAVOR_SMALL:-as.small}"
FLV_MED="${AUTOSCALER_FLAVOR_MEDIUM:-as.medium}"
DEMO_SLEEP="${AUTOSCALER_DEMO_SLEEP:-8}"
CHK_PY="/opt/stack/autoscaler-interattivo-plugin/bin/check_flavor.py"
curr(){ python3 "$CHK_PY" "$SERVER_NAME" 2>/dev/null || true; }
resize_to(){ local t="$1" c; c="$(curr)"; [[ "$c" == "$t" ]] && { echo "[demo] già su $t"; return 0; }
  openstack server resize --flavor "$t" "$SERVER_NAME" --wait || true
  openstack server resize confirm "$SERVER_NAME" || true; }
trap 'echo "[demo] stop"; exit 0' INT TERM
while true; do resize_to "$FLV_MED"; sleep "$DEMO_SLEEP"; resize_to "$FLV_SMALL"; sleep "$DEMO_SLEEP"; done
