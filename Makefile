.DEFAULT_GOAL := help

PYTHON ?= python3
JOBS ?= 4
CONFIGURE_FLAGS ?= --optimize --no-nls
BUILD_FLAGS ?=
ARGS ?=
HOST_OS := $(shell uname -s)

ifeq ($(HOST_OS),Darwin)
BACKENDS ?= coreaudio
BUILD_ENV := sh tools/macos/build-env.sh
else
BACKENDS ?= alsa
BUILD_ENV :=
endif

.PHONY: help deps-osx prerequisites prerequisites-debian prerequisites-osx \
	check-platform check-debian check-osx configure build run \
	configure-debian build-debian run-debian configure-osx build-osx run-osx

help:
	@printf '%s\n' \
		'Ardour development commands' \
		'Usage: make <task> [VARIABLE=value ...]' \
		'' \
		'Current platform (Linux or macOS)' \
		'  help                Show this help; also the default when running make.' \
		'  configure           Check dependencies and configure Waf without compiling.' \
		'  build               Configure, then compile the app; reuse unchanged build outputs.' \
		'  run                 Configure and build, then launch the app from the build tree.' \
		'  prerequisites       Show install commands and dependency/environment setup for this OS.' \
		'' \
		'Debian / Linux (ALSA audio backend by default)' \
		'  configure-debian    Configure without compiling; requires a Linux host.' \
		'  build-debian        Configure and compile the app on Linux.' \
		'  run-debian          Configure, compile, and launch the app on Linux.' \
		'  prerequisites-debian Show Debian dependency installation commands; installs nothing.' \
		'' \
		'macOS (CoreAudio backend by default)' \
		'  deps-osx            Install dependencies from this repository via Homebrew.' \
		'  configure-osx       Configure without compiling; requires a macOS host.' \
		'  build-osx           Configure and compile the app on macOS.' \
		'  run-osx             Configure, compile, and launch the app on macOS.' \
		'  prerequisites-osx   Show macOS tools, Boost, and dependency-stack setup; installs nothing.' \
		'' \
		'Options (append to any applicable task)' \
		'  JOBS=8              Number of parallel compiler jobs; default: 4.' \
		'  PYTHON=python3      Python executable used to run Waf; default: python3.' \
		'  BACKENDS=alsa,jack  Audio backends to build; defaults depend on the host.' \
		'  CONFIGURE_FLAGS=... Replace Waf configure flags; default: --optimize --no-nls.' \
		'  BUILD_FLAGS=...     Extra Waf build flags; default: none.' \
		'  ARGS=...            Arguments passed to Ardour by a run task; default: none.' \
		'' \
		'Examples' \
		'  make build-debian JOBS=8' \
		'  make build-osx CONFIGURE_FLAGS="--no-nls"     Build with debug settings.' \
		'  make run ARGS="--help"                       Show Ardour command-line help.' \
		'' \
		'Native Windows (run in an x64 Visual Studio Developer PowerShell)' \
		'  .\tools\windows\build.ps1 -DependencyRoot C:\ardour-stack' \
		'      Configure and compile using an MSVC-compatible dependency stack.' \
		'  .\tools\windows\run.ps1 -DependencyRoot C:\ardour-stack' \
		'      Build and launch; add -SkipBuild to launch an existing build.' \
		'' \
		'Only deps-osx installs dependencies; build/run tasks do not create installers.' \
		'See README.md for dependency setup, version tags, and additional options.'

prerequisites: check-platform
	@sh tools/build-prerequisites.sh "$(HOST_OS)"

prerequisites-debian: check-debian
	@sh tools/build-prerequisites.sh Linux

prerequisites-osx: check-osx
	@sh tools/build-prerequisites.sh Darwin

deps-osx: check-osx
	@sh tools/macos/build-env.sh install

check-platform:
	@case "$(HOST_OS)" in Linux|Darwin) ;; \
		*) echo 'Use the PowerShell scripts on Windows; this Makefile supports Linux and macOS.' >&2; exit 1 ;; esac

check-debian:
	@test "$(HOST_OS)" = Linux || { echo 'The Debian targets must run on Linux.' >&2; exit 1; }

check-osx:
	@test "$(HOST_OS)" = Darwin || { echo 'The macOS targets must run on macOS.' >&2; exit 1; }

configure: check-platform
	@$(BUILD_ENV) "$(PYTHON)" waf configure --with-backends="$(BACKENDS)" $(CONFIGURE_FLAGS) || { \
		status=$$?; \
		printf '\n%s\n' 'Configuration failed. Follow the setup instructions below, then retry:' >&2; \
		sh tools/build-prerequisites.sh "$(HOST_OS)" >&2; \
		exit $$status; \
	}

build: configure
	@$(BUILD_ENV) "$(PYTHON)" waf build -j"$(JOBS)" $(BUILD_FLAGS)

run: build
	@$(BUILD_ENV) ./gtk2_ardour/ardev $(ARGS)

configure-debian build-debian run-debian: check-debian
configure-osx build-osx run-osx: check-osx

configure-debian configure-osx:
	@$(MAKE) configure

build-debian build-osx:
	@$(MAKE) build

run-debian run-osx:
	@$(MAKE) run
