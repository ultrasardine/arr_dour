#!/bin/sh
set -eu

case "${1:-}" in
    Darwin)
        cat <<'EOF'

macOS build prerequisites
------------------------
1. Install Apple's compiler and SDK:
     xcode-select --install
2. Install Homebrew if it is not already available:
     https://brew.sh
3. Install this fork's declared dependencies:
     make deps-osx
   This uses tools/macos/Brewfile, including the compatible glibmm@2.66,
   cairomm@1.14, pangomm@2.46, and libsigc++@2 bindings.
4. Configure, build, and run:
     make configure-osx
     make build-osx
     make run-osx

The Make tasks configure PATH, PKG_CONFIG_PATH, Boost headers, and gettext paths
automatically. No external Ardour checkout or manual dependency-stack setup is
required by this workflow. Homebrew downloads/installations occur only when you
explicitly run make deps-osx.
EOF
        ;;
    Linux)
        cat <<'EOF'

Debian build prerequisites
--------------------------
Install the compiler, tools, and development libraries:
  sudo apt update
  sudo apt install build-essential git python3 pkg-config gettext \
    libboost-dev libglib2.0-dev libglibmm-2.4-dev libsigc++-2.0-dev \
    libcairomm-1.0-dev libpangomm-1.4-dev libpango1.0-dev \
    libpng-dev libjpeg-dev libxml2-dev libsndfile1-dev \
    libcurl4-openssl-dev libarchive-dev liblo-dev libtag1-dev \
    vamp-plugin-sdk librubberband-dev libsamplerate0-dev libfftw3-dev \
    libflac-dev libogg-dev libaubio-dev liblrdf0-dev \
    lv2-dev libserd-dev libsord-dev libsratom-dev liblilv-dev \
    libasound2-dev libx11-dev libxext-dev libusb-1.0-0-dev
Then retry:
  make configure-debian
For JACK, also install libjack-jackd2-dev and set BACKENDS=alsa,jack.
These package names target Debian 12/13; other Linux distributions differ.
EOF
        ;;
    *)
        echo 'Prerequisite help supports Linux and macOS only.' >&2
        exit 1
        ;;
esac

cat <<'EOF'

Source version and troubleshooting
---------------------------------
Use a full Git clone with Ardour release tags. If "git describe HEAD" fails:
  git fetch https://github.com/Ardour/ardour.git --tags
  git describe HEAD
For a shallow clone, first run: git fetch --unshallow origin

Read the last failed "Checking for ..." line above, then inspect build/config.log
for the compiler or pkg-config error. Missing headers/libraries must be installed
or added to the dependency stack; PKG_CONFIG_PATH must point to its .pc files.
For all platform instructions, see README.md.
EOF
