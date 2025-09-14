#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Autoscaler Interattivo (.sh) - versione commentata e rigenerata
# ----------------------------------------------------------------------------
# Scopo:
#   Interfaccia testuale per ridimensionare una VM tra due flavor (UP/DOWN).
#   UI con colori, cornici, spinner, stato compatto, tabella flavor e DEMO toggle.
#
# Requisiti:
#   - DevStack/OpenStack CLI funzionante e nel PATH (comando 'openstack').
#   - Variabili OS_* caricate (source openrc …).
#   - Un'immagine disponibile in Glance (default: cirros-0.6.3-x86_64-disk).
#   - Rete 'private' raggiungibile per la VM.
#   - Script Python 'check_flavor.py' per leggere robustamente il flavor.
#
# Principi operativi:
#   - Nova NON esegue shrink del root disk: per questo i due flavor qui usano lo
#     stesso 'disk' (=1GB). Cambiamo solo RAM e vCPU per evitare blocchi in DOWN.
#   - Durante il resize attendiamo: VERIFY_RESIZE (poi conferma) oppure ACTIVE con
#     flavor=target (alcuni environment auto-confermano).
#   - IPv4-only per gli indirizzi, filtrando eventuali IPv6 dall'output CLI.
#
# Variabili overrideabili (env):
#   AUTOSCALER_SERVER_NAME    nome VM (default: auto-vm-1)
#   AUTOSCALER_IMAGE_NAME     immagine Glance (default: cirros-0.6.3-x86_64-disk)
#   AUTOSCALER_FLAVOR_SMALL   flavor small  (default: as.small)
#   AUTOSCALER_FLAVOR_MEDIUM  flavor medium (default: as.medium)
#   AUTOSCALER_DEMO_INTERVAL  intervallo DEMO (default: 8)
#   AUTOSCALER_BOX_WIDTH      larghezza cornice (default: 74)
#   AUTOSCALER_NO_SPINNER     se =1 disabilita spinner (utile in log non TTY)
#   AUTOSCALER_VERBOSE        se =1 stampa progress status/flavor durante attese
# ============================================================================

# ======= UI: colori & stile =======
if command -v tput &>/dev/null && [[ -t 1 ]]; then
  BOLD="$(tput bold)"; DIM="$(tput dim)"; RESET="$(tput sgr0)"
  RED="$(tput setaf 1)"; GREEN="$(tput setaf 2)"; YELLOW="$(tput setaf 3)"
  BLUE="$(tput setaf 4)"; MAGENTA="$(tput setaf 5)"; CYAN="$(tput setaf 6)"
else
  BOLD="\e[1m"; DIM="\e[2m"; RESET="\e[0m"
  RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"
  BLUE="\e[34m"; MAGENTA="\e[35m"; CYAN="\e[36m"
fi

# Messaggistica di utilità (colorata)
info(){   echo -e "${CYAN}[info]${RESET} $*"; }
ok(){     echo -e "${GREEN}[ok]${RESET}   $*"; }
warn(){   echo -e "${YELLOW}[warn]${RESET} $*"; }
error(){  echo -e "${RED}[err]${RESET}  $*" >&2; }

# Grassetto e pausa "premi un tasto"
bold(){   echo -e "${BOLD}$*${RESET}"; }
pause(){  read -n1 -s -r -p "$(echo -e "${DIM}Premi un tasto per continuare…${RESET}")"; echo; }

# ======= UI: cornici (box) =======
# Cornici UTF-8 con fallback ASCII. 'boxify' disegna un riquadro intorno al testo.
is_utf8(){ locale | egrep -qi 'utf-8|utf8'; }
repeat(){ local ch="$1" n="$2"; local s=""; for ((i=0;i<n;i++)); do s+="$ch"; done; printf "%s" "$s"; }
strip_ansi(){ sed -r 's/\x1B\[[0-9;]*[mK]//g' <<<"$*"; }
init_box(){
  if is_utf8; then
    TL='┏'; TR='┓'; BL='┗'; BR='┛'; H='━'; V='┃'
  else
    TL='+'; TR='+'; BL='+'; BR='+'; H='-'; V='|'
  fi
  BOX_W="${AUTOSCALER_BOX_WIDTH:-74}"
  INNER_W=$((BOX_W-2))
}
boxify(){  # echo -e "riga1\nriga2" | boxify "Titolo"
  local title="${1:-}"
  init_box
  local top; top="$(repeat "$H" "$INNER_W")"
  echo -e "${BOLD}${TL}${top}${TR}${RESET}"
  if [[ -n "$title" ]]; then
    local clean="$(strip_ansi "$title")"; local tlen=${#clean}
    local pad=$((INNER_W - tlen - 1)); (( pad<0 )) && pad=0
    printf "${V} ${BOLD}%s${RESET}%*s${V}\n" "$title" "$pad" ""
  fi
  while IFS= read -r line; do
    local clean="$(strip_ansi "$line")"; local clen=${#clean}
    local pad=$((INNER_W - clen - 1)); (( pad<0 )) && pad=0
    printf "${V} %s%*s${V}\n" "$line" "$pad" ""
  done
  echo -e "${BOLD}${BL}${top}${BR}${RESET}"
}

# ======= Config base =======
VM_NAME="${AUTOSCALER_SERVER_NAME:-auto-vm-1}"
IMAGE_NAME="${AUTOSCALER_IMAGE_NAME:-cirros-0.6.3-x86_64-disk}"
FLAVOR_SMALL="${AUTOSCALER_FLAVOR_SMALL:-as.small}"
FLAVOR_MEDIUM="${AUTOSCALER_FLAVOR_MEDIUM:-as.medium}"
DEMO_INTERVAL="${AUTOSCALER_DEMO_INTERVAL:-8}"
NETWORK_NAME="${AUTOSCALER_NETWORK_NAME:-private}"

# Percorso agli helper Python (flavor corrente via JSON robusto)
CHECK_FLAVOR_PY="/opt/stack/autoscaler-interattivo-plugin/autoscaler/check_flavor.py"

# ======= Errori e prerequisiti =======
die(){ error "$*"; exit 1; }
have(){ command -v "$1" &>/dev/null; }

# ======= UI: spinner migliorato =======
# Spinner compatto che non "sfarfalla": stampa una sola riga e muove un carattere.
_SPIN_PID=""
start_spinner(){
  local msg="$*"
  # Disabilita se richiesto o non TTY
  if [[ "${AUTOSCALER_NO_SPINNER:-0}" == "1" || ! -t 1 ]]; then
    echo -e "${DIM}${msg}${RESET}"
    _SPIN_PID=""
    return
  fi
  local cols=80 max
  if command -v tput &>/dev/null; then cols="$(tput cols 2>/dev/null || echo 80)"; fi
  max=$(( cols - 4 ))
  (( ${#msg} > max )) && msg="${msg:0:max}"
  echo -ne "${DIM}${msg}${RESET} "
  (
    while true; do
      for c in '|' '/' '-' '\'; do
        printf "\b%s" "$c"
        sleep 0.1
      done
    done
  ) & _SPIN_PID=$!; disown
}
stop_spinner(){
  if [[ -n "${_SPIN_PID}" ]]; then
    kill "${_SPIN_PID}" &>/dev/null || true
    wait "${_SPIN_PID}" 2>/dev/null || true
  fi
  _SPIN_PID=""
  # pulizia e newline
  [[ "${AUTOSCALER_NO_SPINNER:-0}" == "1" ]] || printf "\b \n"
}

with_spinner(){ # with_spinner "msg" cmd args...
  local msg="$1"; shift
  start_spinner "$msg"
  if "$@"; then
    stop_spinner; ok "$msg"
    return 0
  else
    stop_spinner; error "$msg"
    return 1
  fi
}

# ======= Verifica prerequisiti =======
# - openstack CLI disponibile
# - script Python eseguibile
# - variabili OS_* definite (openrc)
ensure_prereq(){
  have openstack || die "openstack CLI non trovato nel PATH."
  [[ -x "$CHECK_FLAVOR_PY" ]] || die "check_flavor.py non eseguibile: $CHECK_FLAVOR_PY"
  : "${OS_AUTH_URL:?Missing OS_AUTH_URL}"
  : "${OS_USERNAME:?Missing OS_USERNAME}"
  : "${OS_PASSWORD:?Missing OS_PASSWORD}"
  : "${OS_PROJECT_NAME:?Missing OS_PROJECT_NAME}"
}

# ======= Flavor helpers =======
flavor_exists(){ openstack flavor show "$1" &>/dev/null; }

# Crea i flavors standard se mancanti (RAM/vCPU diversi, DISK uguale=1GB).
ensure_flavors(){
  flavor_exists "$FLAVOR_SMALL"  || openstack flavor create "$FLAVOR_SMALL"  --ram 512  --vcpus 1 --disk 1 --ephemeral 0 --swap 0 --public || true
  flavor_exists "$FLAVOR_MEDIUM" || openstack flavor create "$FLAVOR_MEDIUM" --ram 1024 --vcpus 2 --disk 1 --ephemeral 0 --swap 0 --public || true
}

# ======= Server helpers =======
server_exists(){ openstack server show "$1" -f value -c id &>/dev/null; }
server_status(){ openstack server show "$1" -f value -c status 2>/dev/null || echo "UNKNOWN"; }

# Solo IPv4 dal campo 'addresses'
server_ip(){
  local name="$1"
  local addr
  addr="$(openstack server show "$name" -f value -c addresses 2>/dev/null || true)"
  echo "$addr" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | paste -sd ' ' - 2>/dev/null || true
}

# Flavor corrente robusto (prima via Python JSON, poi fallback CLI)
current_flavor(){
  if out="$("$CHECK_FLAVOR_PY" "$1" 2>/dev/null)"; then
    [[ -n "$out" ]] && { echo "$out"; return; }
  fi
  openstack server show "$1" -f value -c flavor 2>/dev/null | sed 's/ (ID.*)//'
}

# Attesa generica di uno 'status' target con messaggio breve
wait_for_status(){
  local n="$1" expect="$2" timeout="${3:-60}"
  local t=0 st=""
  start_spinner "Attendo ${expect} (${timeout}s)"
  while (( t < timeout )); do
    st="$(server_status "$n")"
    if [[ "$st" == "$expect" ]]; then
      stop_spinner; ok "Stato raggiunto: ${expect}"
      return 0
    fi
    sleep 1; t=$((t+1))
  done
  stop_spinner; error "Timeout: atteso ${expect}, ultimo stato: ${st}"
  return 1
}

# Crea la VM se manca e attende ACTIVE
ensure_server(){
  if server_exists "$VM_NAME"; then return; fi
  info "VM '${VM_NAME}' non trovata: la creo…"
  with_spinner "Creazione server" openstack server create --image "$IMAGE_NAME" --flavor "$FLAVOR_SMALL" --network "$NETWORK_NAME" "$VM_NAME"
  wait_for_status "$VM_NAME" "ACTIVE" 180 || die "VM non è diventata ACTIVE in tempo."
}

# ======= Tabella flavor (name, id, vcpus, ram, disk) =======
print_flavor_table_header(){
  printf "%-16s | %-36s | %-4s | %-7s | %-7s\n" "NAME" "ID" "vCPU" "RAM(MB)" "DISK(GB)"
  printf "%-16s-+-%-36s-+-%-4s-+-%-7s-+-%-7s\n" "----------------" "------------------------------------" "----" "-------" "-------"
}
print_flavor_line(){
  local f="$1"
  local name id vcpus ram disk
  name="$(openstack flavor show "$f" -f value -c name 2>/dev/null)"
  id="$(openstack flavor show "$f" -f value -c id 2>/dev/null)"
  vcpus="$(openstack flavor show "$f" -f value -c vcpus 2>/dev/null)"
  ram="$(openstack flavor show "$f" -f value -c ram 2>/dev/null)"
  disk="$(openstack flavor show "$f" -f value -c disk 2>/dev/null)"
  printf "%-16s | %-36s | %-4s | %-7s | %-7s\n" "${name:-N/A}" "${id:-N/A}" "${vcpus:-N/A}" "${ram:-N/A}" "${disk:-N/A}"
}

# ======= Stato sintetico (solo VM corrente + flavor corrente) =======
status_brief(){
  set +e
  local st flv
  st="$(openstack server show "$VM_NAME" -f value -c status 2>/dev/null)"
  flv="$("$CHECK_FLAVOR_PY" "$VM_NAME" 2>/dev/null)"
  [[ -z "$flv" ]] && flv="$(openstack server show "$VM_NAME" -f value -c flavor 2>/dev/null | sed 's/ (ID.*)//')"
  set -e
  {
    echo -e "VM: ${BOLD}${VM_NAME}${RESET}"
    echo -e "Stato: ${BOLD}${st:-N/A}${RESET}"
    echo -e "Flavor attuale: ${BOLD}${flv:-N/A}${RESET}"
    echo
    print_flavor_table_header
    if [[ -n "$flv" ]]; then
      print_flavor_line "$flv"
    else
      printf "%-16s | %-36s | %-4s | %-7s | %-7s\n" "N/A" "N/A" "N/A" "N/A" "N/A"
    fi
  } | boxify "Stato VM"
  echo
}

# ======= Resize simmetrico (UP/DOWN) con guardia su DISK uguale =======
do_resize(){
  local target="$1"
  local cur="$(current_flavor "$VM_NAME")"
  [[ -z "$cur" ]] && die "impossibile determinare il flavor corrente."

  # Skip se già sul target
  if [[ "$cur" == "$target" ]]; then
    warn "La VM è già del flavor richiesto: ${BOLD}${target}${RESET} → nessuna azione."
    pause
    return 0
  fi

  # Guardia: dischi uguali (Nova non shrinka il root disk)
  local cur_disk tgt_disk
  cur_disk="$(openstack flavor show "$cur"    -f value -c disk 2>/dev/null || echo 0)"
  tgt_disk="$(openstack flavor show "$target" -f value -c disk 2>/dev/null || echo 0)"
  if [[ -n "$cur_disk" && -n "$tgt_disk" ]] && (( tgt_disk < cur_disk )); then
    error "DOWN non possibile: target disk ${tgt_disk}GB < current ${cur_disk}GB. Usa flavors con stesso 'disk'."
    pause
    return 1
  fi

  bold "Resize: ${cur} ${DIM}→${RESET} ${BOLD}${target}${RESET}"

  # 1) Richiesta resize
  with_spinner "Invio richiesta resize a Nova" openstack server resize --flavor "$target" "$VM_NAME" \
    || die "richiesta resize fallita."

  # 2) Attesa fino a VERIFY_RESIZE o ACTIVE con flavor target
  local t=0 st="" flv="" timeout=300
  start_spinner "Attendo resize → ${target} (${timeout}s)"
  while (( t < timeout )); do
    st="$(server_status "$VM_NAME")"
    flv="$(current_flavor "$VM_NAME")"
    # Verbose progress ogni 3s
    if [[ "${AUTOSCALER_VERBOSE:-0}" == "1" && $((t%3)) -eq 0 ]]; then
      printf "\r${DIM}Attesa: status=%s, flavor=%s (%ss)${RESET} " "$st" "$flv" "$t"
    fi
    if [[ "$st" == "VERIFY_RESIZE" ]]; then
      stop_spinner
      with_spinner "Conferma resize" openstack server resize confirm "$VM_NAME" \
        || die "resize confirm fallito."
      wait_for_status "$VM_NAME" "ACTIVE" 180 || die "post-confirm non ACTIVE."
      ok "Resize completato → flavor attuale: $(bold "$(current_flavor "$VM_NAME")")"
      pause
      return 0
    fi
    if [[ "$st" == "ACTIVE" && "$flv" == "$target" ]]; then
      stop_spinner
      ok "VM ACTIVE con flavor '${target}'"
      pause
      return 0
    fi
    sleep 2; t=$((t+2))
  done
  stop_spinner
  error "Timeout attesa resize. Stato=${st:-?}, flavor=${flv:-?}"
  pause
  return 1
}

# ======= Panoramica principale con cornice =======
show_status(){
  set +e
  local st ip flv task pstate
  st="$(server_status "$VM_NAME")"
  ip="$(server_ip "$VM_NAME")"
  flv="$(current_flavor "$VM_NAME")"
  task="$(openstack server show "$VM_NAME" -f value -c OS-EXT-STS:task_state 2>/dev/null || true)"
  pstate="$(openstack server show "$VM_NAME" -f value -c OS-EXT-STS:power_state 2>/dev/null || true)"
  set -e
  case "$pstate" in
    1) pstate="Running";; 3) pstate="Paused";; 4) pstate="Shut Down";;
    6) pstate="Crashed";; 7) pstate="Suspended";; ""|*) pstate="N/A";;
  esac
  command -v clear &>/dev/null && clear || true
  {
    echo -e "${BOLD}Utente:${RESET} ${OS_USERNAME:-?}   ${BOLD}Progetto:${RESET} ${OS_PROJECT_NAME:-?}"
    echo -e "${BOLD}Endpoint:${RESET} ${OS_AUTH_URL:-?}"
    echo -e "${BOLD}Regione:${RESET} ${OS_REGION_NAME:-RegionOne}  ${BOLD}Interfaccia:${RESET} ${OS_INTERFACE:-public}"
    echo
    echo -e "${BOLD}VM       :${RESET} ${VM_NAME}"
    echo -e "${BOLD}Image    :${RESET} ${IMAGE_NAME}"
    echo -e "${BOLD}Flavors  :${RESET} ${FLAVOR_SMALL} / ${FLAVOR_MEDIUM}"
    echo -e "${BOLD}Stato    :${RESET} ${st:-N/A}"
    echo -e "${BOLD}Flavor   :${RESET} ${flv:-N/A}"
    [[ -n "$ip"   ]] && echo -e "${BOLD}IP (IPv4):${RESET} ${ip}"
    [[ -n "$task" ]] && echo -e "${BOLD}Task     :${RESET} ${task}"
    echo -e "${BOLD}Power    :${RESET} ${pstate}"
  } | boxify "${CYAN}*** AUTOSCALER INTERATTIVO ***${RESET}"

}

# ======= DEMO toggle (UP <-> DOWN a intervalli) =======
demo_toggle(){
  warn "DEMO attiva: toggling ${FLAVOR_SMALL} ↔ ${FLAVOR_MEDIUM}. Ctrl+C per interrompere."
  while true; do
    do_resize "$FLAVOR_MEDIUM" || true
    sleep "$DEMO_INTERVAL"
    do_resize "$FLAVOR_SMALL"  || true
    sleep "$DEMO_INTERVAL"
  done
}

# ======= Cleanup =======
cleanup_and_exit(){
  if server_exists "$VM_NAME"; then
    info "Elimino VM '${VM_NAME}'…"
    openstack server delete "$VM_NAME" || true
  fi
  ok "Cleanup completato."
  exit 0
}

# ======= Menu principale =======
menu(){
  while true; do
    show_status
    {
      echo -e "${BOLD}[1]${RESET} Scala ${GREEN}UP${RESET}   (-> ${BOLD}$FLAVOR_MEDIUM${RESET})"
      echo -e "${BOLD}[2]${RESET} Scala ${YELLOW}DOWN${RESET} (-> ${BOLD}$FLAVOR_SMALL${RESET})"
      echo -e "${BOLD}[3]${RESET} Stato VM   (Attuale)"
      echo -e "${BOLD}[4]${RESET} DEMO auto  (Toggle Ogni ${BOLD}${DEMO_INTERVAL}s${RESET})"
      echo -e "${BOLD}[5]${RESET} Cleanup    (Elimina VM) e esci"
      echo -e "${BOLD}[6]${RESET} ${RED}EXIT${RESET}       (Esci senza modifiche)"
    } | boxify "Azioni"
    echo -ne "Seleziona [1-6]: "
    read -r CH
    case "${CH:-}" in
      1) do_resize "$FLAVOR_MEDIUM" ;;   # include pause
      2) do_resize "$FLAVOR_SMALL"  ;;   # include pause
      3) status_brief; pause ;;
      4) echo; demo_toggle ;;            # loop fino a Ctrl+C
      5) cleanup_and_exit ;;
      6) echo "[bye] nessuna modifica."; exit 0 ;;
      *) warn "Scelta non valida."; pause ;;
    esac
  done
}

# ======= Main =======
main(){
  ensure_prereq
  ensure_flavors
  ensure_server
  menu
}

main "$@"
