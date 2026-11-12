# fdroid-github-builder

A small repository to build Android apps from GitHub using the official F-Droid build chain (`fdroidserver` + `fdroiddata`).

This repo implements the plans in `ideas/`:
- `repo_plan.txt`: GitHub URL wrapper (`build.sh <github-url>`) with metadata generation/detection
- `repo_plan_ext.txt`: local F-Droid environment setup and wrapper basics
- `repo_plan3.txt`: Arch Linux host setup and Debian-based F-Droid build VM (QEMU/KVM/libvirt/Vagrant)

## Repository layout

```text
.
├── README.md
├── install.sh
├── setup-buildserver.sh
├── build.sh
├── config/
│   └── defaults.yml
├── templates/
│   └── app.yml
├── apps/
│   └── AgainstYesterday/
│       ├── metadata.yml        # optional/editable local recipe
│       └── patches/
├── fdroiddata/                 # local checkout of official fdroiddata
├── fdroidserver/               # source checkout (for build-server tooling)
├── output/
└── scripts/
    ├── detect-app-id.sh
    ├── detect-build-system.sh
    └── prepare-build.sh
```

## 1) Install (host + F-Droid tooling)

### Prerequisites
- Linux host (Debian/Ubuntu or Arch Linux)
- Python 3 + venv, Git
- For isolated F-Droid build VM: QEMU/KVM, libvirt, Vagrant (+ `vagrant-libvirt`)

### Install
```bash
./install.sh
# Optional (best-effort host dependency install):
# ./install.sh --system-deps
```

`install.sh` will:
- check required tools
- create `.venv/` and install `fdroidserver` (pin with `FDROIDSERVER_REF=<git-ref>` if desired)
- clone/update `fdroiddata/`
- clone `fdroidserver/` source (used by `setup-buildserver.sh`)
- create required directories

Review and adjust `fdroiddata/config.yml` (SDK paths, signing/build settings, etc.) for your environment.

## 2) (Optional but recommended) Set up isolated F-Droid build VM

F-Droid's build server approach uses a Debian VM provisioned via `fdroidserver/buildserver` tooling.

```bash
./setup-buildserver.sh
```

This script:
- checks libvirt/vagrant prerequisites
- installs `vagrant-libvirt` plugin if missing
- configures `fdroidserver/buildserver/Vagrantfile.yaml` with `vm_provider: libvirt`
- enables `build_server_always: true` in `fdroiddata/config.yml` (if present)
- runs `./fdroidserver/makebuildserver --verbose`

Notes:
- On Arch Linux, host tooling may have compatibility issues; the build VM itself is Debian. If provisioning fails, run the F-Droid host tooling from a Debian environment/VM.
- This step can take significant time and disk space.

## 3) Build an app from GitHub (wrapper)

```bash
# Build latest default branch
./build.sh https://github.com/user/app

# Build a specific branch or tag
./build.sh https://github.com/user/app --ref v1.0.0

# Build a specific commit
./build.sh https://github.com/user/app --commit abc123

# Rebuild using an existing recipe in apps/<AppName>/metadata.yml
./build.sh https://github.com/user/app --existing
```

What `build.sh` does:
1. Clones the source repo into `.work/` (upstream repo is never modified).
2. Detects application ID and build system.
3. Uses `apps/<RepoName>/metadata.yml` if present (or generates a template from `templates/app.yml`).
4. Copies the recipe into `fdroiddata/metadata/<ApplicationID>.yml` (and patches if present).
5. Runs `fdroid readmeta` and `fdroid build <ApplicationID> --verbose` in `fdroiddata/`.
6. Copies APKs/logs/metadata into `output/<RepoName>/`.

## Supported build detection (v1)

- Native Android (Gradle): `build.gradle` / `build.gradle.kts`
- Flutter: `pubspec.yaml`
- Flutter + Rust: `pubspec.yaml` + `Cargo.toml`

Generated recipes are editable starting points. For Flutter/Rust (e.g. AgainstYesterday), ensure required scripts/toolchains run inside the F-Droid build environment and adjust the metadata accordingly.

## Output

```text
output/<AppName>/
  ├── *.apk (if found/copied)
  ├── build.log
  └── metadata.yml
```

## Design rules

- F-Droid is the build engine (no parallel custom build system).
- Metadata is editable and versioned in this repo (`apps/`).
- Upstream repositories are never modified.
- Prefer isolated build environments for untrusted code.
