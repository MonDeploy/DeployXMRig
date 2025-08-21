#!/bin/bash
set -e

# ===== CONFIGURATION =====
WALLET="48iW67pJ5pS2pmYRpMkhMm1MTTDgjrikMeAu7KdxkfknMtSLNNfWMVGHdCWNVWxkexBUJBXpAC1SVYjVP7YsgGLUCPChCoG"
USER="xmrig"
INSTALL_DIR="/opt/xmrig"
SERVICE_NAME="xmrig"

# Enable TLS? (true/false)
USE_TLS=true

# Pool definitions: [ "host" "tls_port" "non_tls_port" ]
POOL=("pool.supportxmr.com" "443" "3333")

# Mining CPU settings
# We will calculate threads dynamically: total cores - 1
CPU_CORES=$(nproc)
MINER_THREADS=$(( CPU_CORES > 1 ? CPU_CORES - 1 : 1 ))
MAX_THREADS_HINT=90  # percent of allowed threads

# ===== FUNCTIONS =====
detect_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
  else
    echo "[-] Cannot detect OS. Aborting."
    exit 1
  fi
}

install_deps_debian() {
  echo "[*] Installing dependencies for Debian/Ubuntu..."
  apt update
  apt install -y git build-essential cmake automake libtool autoconf \
                 libhwloc-dev libuv1-dev libssl-dev ca-certificates
}

install_deps_rhel() {
  echo "[*] Installing dependencies for CentOS/RHEL..."
  yum install -y epel-release
  yum groupinstall -y "Development Tools"
  yum install -y git cmake3 hwloc-devel libuv-devel openssl-devel ca-certificates
  if command -v cmake3 >/dev/null && ! command -v cmake >/dev/null; then
    alternatives --install /usr/bin/cmake cmake /usr/bin/cmake3 10
  fi
}

create_user() {
  echo "[*] Creating xmrig user..."
  if ! id "$USER" &>/dev/null; then
    useradd -m -s /bin/bash "$USER"
  fi
}

build_xmrig() {
  echo "[*] Downloading and building XMRig..."
  cd /tmp
  rm -rf xmrig
  git clone https://github.com/xmrig/xmrig.git
  cd xmrig
  mkdir build && cd build
  cmake .. -DXMRIG_DEPS=ON -DWITHOUT_DEVMINER=ON -DCMAKE_BUILD_TYPE=Release
  make -j$(nproc)

  echo "[*] Installing into $INSTALL_DIR"
  rm -rf "$INSTALL_DIR"
  mkdir -p "$INSTALL_DIR"
  cp xmrig "$INSTALL_DIR/"
  chown -R "$USER":"$USER" "$INSTALL_DIR"
}

configure_xmrig() {
  echo "[*] Creating config.json..."

  if [ "$USE_TLS" = true ]; then
    POOL_URL="${POOL[0]}:${POOL[1]}"
    TLS_SETTING=true
  else
    POOL_URL="${POOL[0]}:${POOL[2]}"
    TLS_SETTING=false
  fi

  cat > "$INSTALL_DIR/config.json" <<EOF
{
    "autosave": true,
    "donate-level": 0,
    "cpu": {
        "enabled": true,
        "threads": $MINER_THREADS,
        "max-threads-hint": $MAX_THREADS_HINT
    },
    "opencl": false,
    "cuda": false,
    "pools": [
        {
            "url": "$POOL_URL",
            "user": "$WALLET",
            "pass": "x",
            "keepalive": true,
            "tls": $TLS_SETTING
        }
    ]
}
EOF

  chown "$USER":"$USER" "$INSTALL_DIR/config.json"
}

setup_systemd() {
  echo "[*] Creating systemd service..."
  cat > "/etc/systemd/system/$SERVICE_NAME.service" <<EOF
[Unit]
Description=XMRig Monero Miner
After=network.target

[Service]
User=$USER
ExecStart=$INSTALL_DIR/xmrig -c $INSTALL_DIR/config.json
Restart=always
Nice=10
CPUWeight=1

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME"
  systemctl start "$SERVICE_NAME"
}

# ===== MAIN =====
detect_os

case "$OS" in
  ubuntu|debian)
    install_deps_debian
    ;;
  centos|rhel|rocky|almalinux|fedora)
    install_deps_rhel
    ;;
  *)
    echo "[-] Unsupported OS: $OS"
    exit 1
    ;;
esac

create_user
build_xmrig
configure_xmrig
setup_systemd

echo "[*] XMRig installation complete on $OS $VERSION."
echo "    CPU cores detected: $CPU_CORES"
echo "    Miner threads: $MINER_THREADS"
echo "    Service name: $SERVICE_NAME"
echo "    To check status: systemctl status $SERVICE_NAME"
echo "    To view logs: journalctl -u $SERVICE_NAME -f"
