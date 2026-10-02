#!/usr/bin/env bash
# ==============================================================================
# winvm-launcher.sh - Smart launcher wrapper for Omarchy Windows VM
# Part of nixarchy.winvm plugin
# ==============================================================================
set -euo pipefail

MODE="${1:-rdp-keepalive}"
LOG_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/winvm-freerdp.log"
mkdir -p "$(dirname "$LOG_FILE")"

# Prevent dockur/windows samba from executing chmod 2777 on an empty shared directory
if [[ -d "$HOME/Windows" && -z "$(ls -A "$HOME/Windows" 2>/dev/null)" ]]; then
  touch "$HOME/Windows/.keep" 2>/dev/null || true
fi

# Helper: check if endpoint 127.0.0.1:3389 is the legitimate root-owned VM service
is_rdp_endpoint_valid() {
  # 1. Specifically verify port 3389 has a listener owned by root (UID 0, e.g. docker-proxy).
  # An unprivileged local user cannot bind a socket with UID 0.
  local has_root_listener=false
  if ss -Htlne 'sport = :3389' 2>/dev/null | grep -E ":3389\b" | grep -qvE "uid:[1-9]" && ss -Htlne 'sport = :3389' 2>/dev/null | grep -E ":3389\b" | grep -qE "uid:0|docker\.service"; then
    has_root_listener=true
  elif awk '$4=="0A" && $2 ~ /:0D3D$/ && $8=="0" { found=1; exit } END { exit !found }' /proc/net/tcp /proc/net/tcp6 2>/dev/null; then
    has_root_listener=true
  fi

  [[ "$has_root_listener" == "true" ]] || return 1

  # 2. Confirm docker-proxy is active under root specifically for port 3389
  if pgrep -u 0 -f "docker-proxy.*3389" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# Helper: check if legitimate Windows VM container is running and listening
is_container_running() {
  # For RDP connections, port 3389 must specifically be the authenticated root-owned endpoint.
  # Port 8006 alone cannot satisfy RDP readiness.
  is_rdp_endpoint_valid
}

# Helper: probe RDP server certificate from 127.0.0.1:3389 without sending credentials
get_rdp_server_fingerprint() {
  python3 -c '
import socket, ssl, hashlib, sys

host = "127.0.0.1"
port = 3389
timeout = 3

try:
    s = socket.create_connection((host, port), timeout=timeout)
    # X.224 Connection Request PDU requesting SSL/TLS (MS-RDPBCGR section 2.2.1.1)
    neg_req = bytes([
        0x03, 0x00, 0x00, 0x13,
        0x0e, 0xe0, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x01, 0x00, 0x08, 0x00, 0x03, 0x00, 0x00, 0x00
    ])
    s.sendall(neg_req)
    resp = s.recv(1024)
    if len(resp) < 11 or resp[0] != 0x03 or resp[1] != 0x00 or resp[5] != 0xd0:
        sys.exit(1)
    # Perform TLS handshake to obtain server certificate WITHOUT sending any credentials
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    with ctx.wrap_socket(s) as ss:
        cert_der = ss.getpeercert(binary_form=True)
        if not cert_der:
            sys.exit(1)
        print(hashlib.sha256(cert_der).hexdigest())
except Exception:
    sys.exit(1)
' 2>/dev/null
}

# Helper: verify 3389 endpoint and validate its RDP certificate/fingerprint before sending credentials
verify_and_get_rdp_fingerprint() {
  # 1. Require 3389 endpoint to be root-owned docker-proxy
  if ! is_rdp_endpoint_valid; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Endpoint 127.0.0.1:3389 is not the expected root-owned VM service." >> "$LOG_FILE"
    return 1
  fi

  # 2. Probe server certificate fingerprint without credentials
  local probed_fp
  probed_fp=$(get_rdp_server_fingerprint) || return 1
  if [[ -z "$probed_fp" || ${#probed_fp} -ne 64 ]]; then
    return 1
  fi

  local cert_dir="${XDG_CONFIG_HOME:-$HOME/.config}/freerdp/server"
  local cert_file="$cert_dir/127.0.0.1_3389.pem"
  local fp_file="${XDG_CONFIG_HOME:-$HOME/.config}/windows/rdp-cert.sha256"

  mkdir -p "$(dirname "$fp_file")"

  local expected_fp=""
  if [[ -f "$fp_file" ]]; then
    expected_fp=$(tr -d '[:space:]' < "$fp_file" | tr '[:upper:]' '[:lower:]')
  elif [[ -f "$cert_file" ]]; then
    expected_fp=$(openssl x509 -in "$cert_file" -outform der 2>/dev/null | sha256sum | cut -d' ' -f1 | tr -d '[:space:]')
    if [[ -n "$expected_fp" ]]; then
      (umask 077; printf '%s\n' "$expected_fp" > "$fp_file")
    fi
  fi

  # If a pinned fingerprint exists, verify exact match
  if [[ -n "$expected_fp" ]]; then
    if [[ "$probed_fp" != "$expected_fp" ]]; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] SECURITY ERROR: RDP server certificate fingerprint mismatch!" >> "$LOG_FILE"
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] Expected: $expected_fp, Probed: $probed_fp" >> "$LOG_FILE"
      notify-send -u critical "Windows VM Security Alert" "RDP server certificate on port 3389 does not match the expected VM! Aborting to protect credentials."
      return 1
    fi
  else
    # First-use pin: only pin if 3389 endpoint is verified root docker-proxy
    (umask 077; printf '%s\n' "$probed_fp" > "$fp_file")
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Pinned initial RDP server certificate fingerprint: $probed_fp" >> "$LOG_FILE"
  fi

  printf '%s\n' "$probed_fp"
  return 0
}

# Helper: run FreeRDP client directly with full Omarchy parameters
run_freerdp() {
  local win_user="docker"
  local win_pass="admin"
  local creds_file="${XDG_CONFIG_HOME:-$HOME/.config}/windows/credentials"

  if [[ -f "$creds_file" ]]; then
    local u p
    u=$(grep -E '^USERNAME=' "$creds_file" | head -n1 | cut -d= -f2- | tr -d '\r\n')
    p=$(grep -E '^PASSWORD=' "$creds_file" | head -n1 | cut -d= -f2- | tr -d '\r\n')
    [[ -n "$u" ]] && win_user="$u"
    [[ -n "$p" ]] && win_pass="$p"
  fi

  # Authenticate the 3389 endpoint and verify its certificate before sending credentials
  local verified_fp
  verified_fp=$(verify_and_get_rdp_fingerprint) || {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Pre-connection verification failed for 127.0.0.1:3389. Credentials will NOT be sent." >> "$LOG_FILE"
    return 1
  }

  local krb5_conf="${XDG_CONFIG_HOME:-$HOME/.config}/windows/krb5.conf"
  if [[ ! -f "$krb5_conf" ]]; then
    mkdir -p "$(dirname "$krb5_conf")"
    printf '[libdefaults]\n  dns_lookup_kdc = false\n  dns_lookup_realm = false\n' >"$krb5_conf"
  fi
  export KRB5_CONFIG="$krb5_conf"

  local rdp_scale=""
  local hypr_scale
  hypr_scale=$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select (.focused == true) | .scale' 2>/dev/null || echo "1")
  local scale_percent
  scale_percent=$(echo "$hypr_scale" | awk '{print int($1 * 100)}')
  if ((scale_percent >= 170)); then
    rdp_scale="/scale:180"
  elif ((scale_percent >= 130)); then
    rdp_scale="/scale:140"
  fi

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Executing xfreerdp3 securely (user: $win_user, fingerprint: ${verified_fp:0:16}...)..." >> "$LOG_FILE"

  local -a rdp_args=(
    "/u:$win_user"
    "/p:$win_pass"
    "/v:127.0.0.1:3389"
    "-grab-keyboard"
    "/sound"
    "/microphone"
    "/clipboard"
    "/cert:deny,fingerprint:sha256:$verified_fp"
    "/title:Windows VM - Omarchy"
    "/dynamic-resolution"
    "/gfx:AVC444"
    "/floatbar:sticky:off,default:visible,show:fullscreen"
  )
  if [[ -n "$rdp_scale" ]]; then
    rdp_args+=("$rdp_scale")
  fi

  # Pass arguments securely via stdin (/args-from:stdin) so credentials are never
  # exposed in the process command line (e.g. ps aux, /proc/<pid>/cmdline)
  printf '%s\n' "${rdp_args[@]}" | xfreerdp3 /args-from:stdin >> "$LOG_FILE" 2>&1
  local rdp_status=$?
  unset win_pass rdp_args
  return $rdp_status
}

# Helper: read and validate DOMAIN/URI from libvirt.conf into DOMAIN, URI, CONF_NOTE.
# Invalid values are ignored; CONF_NOTE gets a fixed string naming the key.
read_libvirt_conf() {
  DOMAIN=""
  URI="qemu:///system"
  CONF_NOTE=""
  local conf="${XDG_CONFIG_HOME:-$HOME/.config}/windows/libvirt.conf"
  [[ -f "$conf" ]] || return 0

  local d u
  d=$(grep -E '^DOMAIN=' "$conf" | head -n1 | cut -d= -f2- | tr -d '\r\n' || true)
  u=$(grep -E '^URI=' "$conf" | head -n1 | cut -d= -f2- | tr -d '\r\n' || true)

  if [[ -n "$d" ]]; then
    if [[ "$d" =~ ^[A-Za-z0-9._-]{1,64}$ ]]; then
      DOMAIN="$d"
    else
      CONF_NOTE="invalid DOMAIN in libvirt.conf ignored; "
    fi
  fi
  if [[ -n "$u" ]]; then
    if [[ "$u" == "qemu:///system" || "$u" == "qemu:///session" ]]; then
      URI="$u"
    else
      CONF_NOTE="${CONF_NOTE}invalid URI in libvirt.conf ignored; "
    fi
  fi
}

# Helper: choose the backend. Sets BACKEND (dockur|libvirt|none), DOMAIN, URI, REASON.
resolve_backend() {
  BACKEND="none"
  REASON=""
  read_libvirt_conf

  # Same "configured" test omarchy-windows-vm makes first. Its `status` runs a
  # privileged query and a compose migration, so it must not be used as a probe.
  if command -v omarchy-windows-vm >/dev/null 2>&1 && {
    [[ -f "${OMARCHY_WINDOWS_DIR:-/var/lib/omarchy/windows}/docker-compose.yml" ]] ||
      [[ -f "$HOME/.config/windows/docker-compose.yml" ]]
  }; then
    BACKEND="dockur"
    DOMAIN=""
    return 0
  fi

  if ! command -v virsh >/dev/null 2>&1; then
    DOMAIN=""
    REASON="${CONF_NOTE}No Windows VM configured and virsh not found"
    return 0
  fi

  # Configured domain, if it exists
  if [[ -n "$DOMAIN" ]]; then
    if virsh -c "$URI" dominfo "$DOMAIN" >/dev/null 2>&1; then
      BACKEND="libvirt"
      return 0
    fi
    CONF_NOTE="${CONF_NOTE}configured domain not found; "
    DOMAIN=""
  fi

  # Auto-detect: exactly one domain tagged as a Windows guest in libosinfo
  local names name xml
  local -a found=()
  names=$(virsh -c "$URI" list --all --name 2>/dev/null || true)
  while IFS= read -r name; do
    [[ "$name" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || continue
    xml=$(virsh -c "$URI" dumpxml "$name" 2>/dev/null || true)
    if [[ "$xml" == *'libosinfo:os id="http://microsoft.com/win/'* ]]; then
      found+=("$name")
    fi
  done <<< "$names"

  if ((${#found[@]} == 1)); then
    BACKEND="libvirt"
    DOMAIN="${found[0]}"
  elif ((${#found[@]} == 0)); then
    REASON="${CONF_NOTE}No Windows VM found in libvirt"
  else
    REASON="${CONF_NOTE}Several Windows VMs found; set DOMAIN in libvirt.conf"
  fi
}

# Helper: print the resolved backend as one JSON line (values are validated, no escaping needed)
print_backend() {
  case "$BACKEND" in
    libvirt) printf '{"backend":"libvirt","domain":"%s","uri":"%s"}\n' "$DOMAIN" "$URI" ;;
    dockur) printf '{"backend":"dockur"}\n' ;;
    *) printf '{"backend":"none","reason":"%s"}\n' "$REASON" ;;
  esac
}

# Helper: open the libvirt domain in virt-viewer; $1=1 shuts it down afterwards
libvirt_open() {
  local autostop="${1:-0}"
  if ! command -v virt-viewer >/dev/null 2>&1; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: virt-viewer not found." >> "$LOG_FILE"
    notify-send -u critical "Windows VM" "virt-viewer is not installed; cannot open $DOMAIN."
    return 1
  fi

  local state
  state=$(virsh -c "$URI" domstate "$DOMAIN" 2>/dev/null || true)
  if [[ "$state" == "shut off" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting libvirt domain $DOMAIN..." >> "$LOG_FILE"
    virsh -c "$URI" start "$DOMAIN" >> "$LOG_FILE" 2>&1 || true
  fi

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Opening virt-viewer for $DOMAIN..." >> "$LOG_FILE"
  virt-viewer --connect "$URI" --attach --wait "$DOMAIN" >> "$LOG_FILE" 2>&1 || true

  if [[ "$autostop" == "1" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] virt-viewer closed in auto-stop mode, shutting down $DOMAIN..." >> "$LOG_FILE"
    virsh -c "$URI" shutdown "$DOMAIN" >> "$LOG_FILE" 2>&1 || true
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  resolve_backend

  if [[ "$MODE" == "backend" ]]; then
    print_backend
    exit 0
  fi

  if [[ "$BACKEND" == "libvirt" ]]; then
    case "$MODE" in
      attach|rdp-keepalive) libvirt_open 0 ;;
      rdp-autostop) libvirt_open 1 ;;
      stop) virsh -c "$URI" shutdown "$DOMAIN" >> "$LOG_FILE" 2>&1 || true ;;
    esac
    exit 0
  fi

  case "$MODE" in
    stop)
      omarchy-windows-vm stop >> "$LOG_FILE" 2>&1 || true
      exit 0
      ;;

    web)
      xdg-open "http://127.0.0.1:8006" &
      exit 0
      ;;

    attach)
      if ! is_rdp_endpoint_valid; then
        notify-send -u normal "Windows VM" "Starting Windows VM..."
        exec "$0" rdp-keepalive
      fi

      echo "[$(date '+%Y-%m-%d %H:%M:%S')] Attaching FreeRDP to running VM..." >> "$LOG_FILE"
      run_freerdp
      exit 0
      ;;

    rdp-autostop)
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Windows VM (auto-stop mode)..." >> "$LOG_FILE"
      if ! is_rdp_endpoint_valid; then
        omarchy-windows-vm launch -k >> "$LOG_FILE" 2>&1 || true
        sleep 1
      fi

      if ! (pgrep -x "xfreerdp3" >/dev/null 2>&1 || pgrep -x "xfreerdp" >/dev/null 2>&1); then
        for attempt in {1..12}; do
          if ! is_rdp_endpoint_valid; then break; fi
          if run_freerdp; then break; fi
          sleep 3
        done
      fi

      echo "[$(date '+%Y-%m-%d %H:%M:%S')] FreeRDP finished in auto-stop mode, stopping VM..." >> "$LOG_FILE"
      omarchy-windows-vm stop >> "$LOG_FILE" 2>&1 || true
      exit 0
      ;;

    rdp-keepalive|*)
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Windows VM (keep-alive mode)..." >> "$LOG_FILE"
      
      # 1. Bring up container if not already running
      if ! is_rdp_endpoint_valid; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Bringing up container via omarchy-windows-vm launch -k..." >> "$LOG_FILE"
        omarchy-windows-vm launch -k >> "$LOG_FILE" 2>&1 || true
        sleep 1
      fi

      # 2. Check if FreeRDP was launched and is already running
      if pgrep -x "xfreerdp3" >/dev/null 2>&1 || pgrep -x "xfreerdp" >/dev/null 2>&1; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] FreeRDP client is currently active." >> "$LOG_FILE"
        exit 0
      fi

      # 3. Verify endpoint, certificate, and connect FreeRDP securely
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting connection loop..." >> "$LOG_FILE"
      for attempt in {1..12}; do
        if ! is_rdp_endpoint_valid; then
          echo "[$(date '+%Y-%m-%d %H:%M:%S')] Port 3389 endpoint is not ready or container stopped, waiting..." >> "$LOG_FILE"
          sleep 3
          continue
        fi

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Connection attempt $attempt of 12..." >> "$LOG_FILE"
        if run_freerdp; then
          echo "[$(date '+%Y-%m-%d %H:%M:%S')] FreeRDP session ended normally." >> "$LOG_FILE"
          break
        fi

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Attempt $attempt failed, waiting 3s before retry..." >> "$LOG_FILE"
        sleep 3
      done
      ;;
  esac
fi
