#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

log() { printf '[install] %s\n' "$*"; }
warn() { printf '[install] WARN: %s\n' "$*" >&2; }
die() { printf '[install] ERROR: %s\n' "$*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

usage() {
  cat <<'EOF'
Usage: ./install.sh [--system-deps]

Options:
  --system-deps   Attempt to install host dependencies (Arch/Debian/Ubuntu best effort)
EOF
}

INSTALL_SYSTEM_DEPS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --system-deps) INSTALL_SYSTEM_DEPS=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

install_system_deps() {
  if command -v pacman >/dev/null 2>&1; then
    log "Detected Arch Linux (pacman). Installing host dependencies..."
    sudo pacman -Syu --needed \
      git base-devel python python-pip python-virtualenv \
      qemu-full libvirt dnsmasq vagrant virt-install virt-manager \
      edk2-ovmf ebtables iptables-nft bridge-utils || \
      warn "Some Arch packages could not be installed; review package names for your system."
  elif command -v apt-get >/dev/null 2>&1; then
    log "Detected Debian/Ubuntu (apt). Installing host dependencies..."
    sudo apt-get update
    sudo apt-get install -y \
      git python3 python3-venv python3-pip \
      openjdk-17-jdk-headless \
      qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils \
      vagrant podman || \
      warn "Some apt packages could not be installed; review package names for your distro."
  else
    warn "Unsupported package manager for --system-deps. Install dependencies manually."
  fi
}

if [ "$INSTALL_SYSTEM_DEPS" -eq 1 ]; then
  install_system_deps
fi

log "Checking required tools..."
need_cmd python3
need_cmd git

if ! python3 -m venv --help >/dev/null 2>&1; then
  die "python3 venv module is unavailable (install python3-venv / python-virtualenv support)."
fi

if ! command -v podman >/dev/null 2>&1; then
  warn "podman not found. It may be useful depending on your F-Droid setup."
fi
if ! command -v virsh >/dev/null 2>&1; then
  warn "libvirt/virsh not found. Needed for F-Droid build server VM setup (see ./setup-buildserver.sh)."
fi
if ! command -v vagrant >/dev/null 2>&1; then
  warn "vagrant not found. Needed for F-Droid build server VM setup (see ./setup-buildserver.sh)."
fi

log "Creating directories..."
mkdir -p config templates apps/AgainstYesterday/patches fdroiddata output scripts logs .work

log "Creating Python virtual environment..."
if [ ! -d .venv ]; then
  python3 -m venv .venv
fi
# shellcheck disable=SC1091
source .venv/bin/activate

python -m pip install --upgrade pip setuptools wheel >/dev/null

FDROIDSERVER_REF="${FDROIDSERVER_REF:-}"
if [ -n "$FDROIDSERVER_REF" ]; then
  log "Installing fdroidserver from git ref: $FDROIDSERVER_REF"
  python -m pip install --upgrade "git+https://gitlab.com/fdroid/fdroidserver.git@${FDROIDSERVER_REF}"
else
  log "Installing fdroidserver (latest from PyPI if available, else git)..."
  if ! python -m pip install --upgrade fdroidserver; then
    warn "PyPI install failed, falling back to git master"
    python -m pip install --upgrade "git+https://gitlab.com/fdroid/fdroidserver.git"
  fi
fi

log "Ensuring fdroiddata checkout..."
if [ -d fdroiddata/.git ]; then
  log "Updating existing fdroiddata (best effort)..."
  git -C fdroiddata fetch --all --tags >/dev/null 2>&1 || true
  git -C fdroiddata pull --ff-only >/dev/null 2>&1 || warn "Could not fast-forward fdroiddata; leaving as-is"
else
  if [ "$(ls -A fdroiddata 2>/dev/null | wc -l)" -gt 0 ]; then
    die "fdroiddata exists but is not a git repo. Move it aside or make it a git checkout."
  fi
  git clone https://gitlab.com/fdroid/fdroiddata.git fdroiddata
fi

# Prepare a local fdroiddata config if missing (best effort; may require manual adjustment)
if [ ! -f fdroiddata/config.yml ] && [ -f fdroiddata/config.yml.example ]; then
  cp fdroiddata/config.yml.example fdroiddata/config.yml
  log "Created fdroiddata/config.yml from example (review and adjust paths/SDK settings as needed)."
fi

# Optionally clone fdroidserver source for makebuildserver workflows
if [ ! -d fdroidserver/.git ]; then
  log "Cloning fdroidserver source (for build-server tooling)..."
  git clone https://gitlab.com/fdroid/fdroidserver.git fdroidserver || warn "Could not clone fdroidserver source repo"
fi

log "Verifying F-Droid tooling..."
if command -v fdroid >/dev/null 2>&1; then
  fdroid --version || warn "fdroid --version failed"
else
  die "fdroid command not found after installation"
fi

log "Installation complete."
log "Next: review fdroiddata/config.yml, optionally run ./setup-buildserver.sh, then ./build.sh <github-url>"
