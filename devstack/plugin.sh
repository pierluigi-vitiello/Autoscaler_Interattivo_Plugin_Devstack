post_config_autoscaler-interattivo-plugin() {
  _asi_info "post-config"

  # Se non c'è il CLI, non bloccare lo stack
  if ! command -v openstack >/dev/null 2>&1; then
    _asi_warn "openstack CLI non nel PATH durante post-config; salto creazione flavors"
    return 0
  fi

  # Attendi che nova-api sia raggiungibile (porta 8774) e che il catalogo risponda
  HOST="${HOST_IP:-127.0.0.1}"
  _asi_info "attendo nova-api su ${HOST}:8774 ..."
  for i in {1..60}; do
    if curl -sf "http://${HOST}:8774/" >/dev/null 2>&1; then
      # Verifica anche che Keystone + Nova siano operativi
      if openstack compute service list >/dev/null 2>&1; then
        _asi_info "nova-api pronto"
        break
      fi
    fi
    sleep 2
  done

  # Se ancora non pronto, non mandare in errore lo stack: esci con warn
  if ! openstack compute service list >/dev/null 2>&1; then
    _asi_warn "nova-api non ancora pronto; salto la creazione dei flavors (non-bloccante)"
    return 0
  fi

  small="${AUTOSCALER_FLAVOR_SMALL:-as.small}"
  medium="${AUTOSCALER_FLAVOR_MEDIUM:-as.medium}"

  # Retry con backoff: evita i 503 transitori
  _asi_info "creazione/validazione flavors: $small, $medium"
  for d in 2 3 5 8 13; do
    # small
    openstack flavor show "$small" >/dev/null 2>&1 || \
      openstack flavor create --ram 512 --vcpus 1 --disk 1 "$small" >/dev/null 2>&1 || true
    # medium
    openstack flavor show "$medium" >/dev/null 2>&1 || \
      openstack flavor create --ram 1024 --vcpus 1 --disk 2 "$medium" >/dev/null 2>&1 || true

    # uscita se ok
    if openstack flavor show "$small" >/dev/null 2>&1 && openstack flavor show "$medium" >/devnull 2>&1; then
      _asi_info "flavors pronti"
      break
    fi
    _asi_warn "flavors non ancora disponibili (probabile 503); ritento tra ${d}s..."
    sleep "$d"
  done

  _asi_info "post-config done"
}
