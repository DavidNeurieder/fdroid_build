#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

log() { printf '[setup-buildserver] %s\n' "$*"; }
warn() { printf '[setup-buildserver] WARN: %s\n' "$*" >&2; }
die() { printf '[setup-buildserver] ERROR: %s\n' "$*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

log "Checking virtualization prerequisites..."
need_cmd qemu-system-x86_64 || true
need_cmd virsh
need_cmd vagrant

if [ ! -e /dev/kvm ]; then
  warn "/dev/kvm not found. Enable virtualization in BIOS/UEFI and load kvm modules."
fi

log "Ensuring libvirt service is running (best effort)..."
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl enable --now libvirtd || warn "Could not enable/start libvirtd automatically"
fi

if ! vagrant plugin list 2>/dev/null | grep -q 'vagrant-libvirt'; then
  log "Installing vagrant-libvirt plugin..."
  vagrant plugin install vagrant-libvirt
else
  log "vagrant-libvirt plugin already installed."
fi

# Ensure fdroidserver source checkout exists for makebuildserver
if [ ! -d "$ROOT/fdroidserver/.git" ]; then
  log "Cloning fdroidserver source (required for makebuildserver)..."
  git clone https://gitlab.com/fdroid/fdroidserver.git "$ROOT/fdroidserver"
else
  log "fdroidserver source checkout already present."
fi

# Configure buildserver provider
BS_DIR="$ROOT/fdroidserver/buildserver"
mkdir -p "$BS_DIR"
cat > "$BS_DIR/Vagrantfile.yaml" <<'YAML'
vm_provider: libvirt
YAML
log "Wrote $BS_DIR/Vagrantfile.yaml (vm_provider: libvirt)"

# Ensure fdroiddata config enables server builds when desired
if [ -d "$ROOT/fdroiddata" ] && [ -f "$ROOT/fdroiddata/config.yml" ]; then
  if ! grep -q '^build_server_always:' "$ROOT/fdroiddata/config.yml"; then
    printf '\n# Enabled by setup-buildserver.sh\nbuild_server_always: true\n' >> "$ROOT/fdroiddata/config.yml"
    log "Enabled build_server_always in fdroiddata/config.yml"
  else
    log "fdroiddata/config.yml already contains build_server_always setting."
  fi
else
  warn "fdroiddata/config.yml not found; run ./install.sh and review fdroiddata config."
fi

log "Generating F-Droid build VM via makebuildserver (this can take a long time)..."
cd "$ROOT/fdroidserver"
./makebuildserver --verbose

log "Build server setup complete."
log "Test with: (cd fdroiddata && ../fdroidserver/fdroid readmeta && ../fdroidserver/fdroid build org.fdroid.fdroid --latest --server --verbose) if fdroidserver checkout is used directly."
