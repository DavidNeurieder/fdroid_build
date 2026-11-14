SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

ROOT := $(CURDIR)
VENV_FDROID := $(ROOT)/.venv/bin/fdroid

URL ?=
REF ?=
COMMIT ?=
APP ?=
SRC ?=
ARGS ?=

.DEFAULT_GOAL := help

.PHONY: help install install-system-deps setup-buildserver check \
	build build-ref build-commit build-existing build-againstyesterday build-librecrate \
	status logs detect clean-work clean

help: ## Show available targets and usage examples
	@echo "Available targets:"
	@echo "  help                  Show this help"
	@echo "  install               Install fdroidserver, clone fdroiddata/fdroidserver source"
	@echo "  install-system-deps   Best-effort host dependency install (may use sudo)"
	@echo "  setup-buildserver     Configure/provision F-Droid build VM (long-running)"
	@echo "  check                 Show environment/tooling status"
	@echo "  build                 Build from GitHub URL (URL=... [ARGS=...])"
	@echo "  build-ref             Build specific ref (URL=... REF=...)"
	@echo "  build-commit          Build specific commit (URL=... COMMIT=...)"
	@echo "  build-existing        Build using apps/<RepoName>/metadata.yml (URL=...)"
	@echo "  build-againstyesterday  Build AgainstYesterday with existing recipe"
	@echo "  build-librecrate      Build LibreCrate with existing recipe"
	@echo "  status                Show repo/build environment status"
	@echo "  logs                  List or tail build logs (APP=<name> optional)"
	@echo "  detect                Run detection scripts on local source (SRC=<path>)"
	@echo "  clean-work            Remove .work/* cloned source directories"
	@echo "  clean                 Alias for clean-work (non-destructive)"
	@echo ""
	@echo "Examples:"
	@echo "  make install"
	@echo "  make build URL=https://github.com/user/app"
	@echo "  make build URL=https://github.com/user/app ARGS=\"--ref v1.0.0\""
	@echo "  make build-ref URL=https://github.com/user/app REF=v1.0.0"
	@echo "  make build-existing URL=https://github.com/DavidNeurieder/AgainstYesterday"
	@echo "  make logs APP=AgainstYesterday"

install: ## Install F-Droid tooling and local checkouts
	./install.sh

install-system-deps: ## Install host dependencies (best effort)
	./install.sh --system-deps

setup-buildserver: ## Set up F-Droid build server VM
	./setup-buildserver.sh

check: ## Check environment and required tools
	@echo "== Tools =="
	@command -v python3 >/dev/null 2>&1 && echo "python3: $$(python3 --version 2>&1 | head -n1)" || echo "python3: missing"
	@command -v git >/dev/null 2>&1 && echo "git: $$(git --version)" || echo "git: missing"
	@command -v bash >/dev/null 2>&1 && echo "bash: $$(bash --version | head -n1)" || echo "bash: missing"
	@command -v podman >/dev/null 2>&1 && echo "podman: present" || echo "podman: not found"
	@command -v virsh >/dev/null 2>&1 && echo "virsh: present" || echo "virsh: not found"
	@command -v vagrant >/dev/null 2>&1 && echo "vagrant: present" || echo "vagrant: not found"
	@echo "== Repo state =="
	@[ -d .venv ] && echo ".venv: present" || echo ".venv: missing"
	@[ -x "$(VENV_FDROID)" ] && echo "fdroid: $$($(VENV_FDROID) --version 2>&1 | head -n1)" || (command -v fdroid >/dev/null 2>&1 && echo "fdroid: $$(fdroid --version 2>&1 | head -n1)" || echo "fdroid: missing")
	@[ -d fdroiddata/.git ] && echo "fdroiddata: git checkout" || echo "fdroiddata: missing/incomplete"
	@[ -d fdroidserver/.git ] && echo "fdroidserver source: git checkout" || echo "fdroidserver source: missing/incomplete"
	@[ -f fdroiddata/config.yml ] && echo "fdroiddata/config.yml: present" || echo "fdroiddata/config.yml: missing"
	@echo "== Outputs =="
	@[ -d output ] && find output -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed 's#^#output: #' || echo "output: missing"

build: ## Build app from GitHub URL (URL=... [ARGS=...])
ifndef URL
	$(error URL is required, e.g. make build URL=https://github.com/owner/repo)
endif
	./build.sh "$(URL)" $(ARGS)

build-ref: ## Build app at ref (URL=... REF=...)
ifndef URL
	$(error URL is required)
endif
ifndef REF
	$(error REF is required, e.g. make build-ref URL=... REF=v1.0.0)
endif
	./build.sh "$(URL)" --ref "$(REF)"

build-commit: ## Build app at commit (URL=... COMMIT=...)
ifndef URL
	$(error URL is required)
endif
ifndef COMMIT
	$(error COMMIT is required)
endif
	./build.sh "$(URL)" --commit "$(COMMIT)"

build-existing: ## Build app using existing recipe (URL=...)
ifndef URL
	$(error URL is required)
endif
	./build.sh "$(URL)" --existing

build-againstyesterday: ## Build AgainstYesterday using existing recipe
	./build.sh https://github.com/DavidNeurieder/AgainstYesterday --existing

build-librecrate: ## Build LibreCrate using existing recipe
	./build.sh https://github.com/DavidNeurieder/LibreCrate --existing

status: ## Show repository and build status
	@$(MAKE) --no-print-directory check
	@echo "== Apps with local recipes =="
	@find apps -mindepth 1 -maxdepth 2 -name metadata.yml 2>/dev/null | sed 's#^#recipe: #' || true
	@echo "== Work directories =="
	@find .work -mindepth 1 -maxdepth 1 2>/dev/null | sed 's#^#work: #' || echo "work: (none)"

logs: ## List or show build logs (APP=<name> to tail latest for app)
	@if [ -n "$(APP)" ]; then \
		if [ -f "output/$(APP)/build.log" ]; then \
			echo "== output/$(APP)/build.log (last 200 lines) =="; \
			tail -n 200 "output/$(APP)/build.log"; \
		else \
			echo "No build log found at output/$(APP)/build.log"; \
			exit 1; \
		fi; \
	else \
		echo "== Build logs =="; \
		find output -type f -name build.log 2>/dev/null | sort || echo "(none)"; \
	fi

detect: ## Detect app id/build system for a local source tree (SRC=<path>)
ifndef SRC
	$(error SRC is required, e.g. make detect SRC=/path/to/source)
endif
	@echo "== App ID =="; ./scripts/detect-app-id.sh "$(SRC)" || true
	@echo "== Build system =="; ./scripts/detect-build-system.sh "$(SRC)"

clean-work: ## Remove cloned source work directories (.work/*)
	rm -rf .work/*

clean: clean-work ## Conservative clean (removes .work/* only)
