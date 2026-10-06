#!/bin/sh
set -eu

if ! command -v brew >/dev/null 2>&1; then
    echo 'Homebrew is required. Install it from https://brew.sh, then run make deps-osx.' >&2
    exit 1
fi

if [ "${1:-}" = install ]; then
    exec brew bundle install --file=tools/macos/Brewfile
fi

if [ "$#" -eq 0 ]; then
    echo 'Usage: build-env.sh install | command [arguments ...]' >&2
    exit 1
fi

# Keg-only legacy C++ bindings must take precedence over newer incompatible APIs.
brew_prefix=$(brew --prefix)
package_paths=
header_paths=
library_paths=
for formula in $(sed -n 's/^brew "\([^"]*\)"$/\1/p' tools/macos/Brewfile); do
    prefix=$(brew --prefix "$formula")
    if [ ! -d "$prefix" ]; then
        echo "Missing Homebrew dependency: $formula. Run make deps-osx, then retry." >&2
        exit 1
    fi
    PATH="$prefix/bin:$PATH"
    package_paths="${package_paths:+$package_paths:}$prefix/lib/pkgconfig:$prefix/share/pkgconfig"
    case "$formula" in
        boost|gettext|jpeg-turbo)
            header_paths="${header_paths:+$header_paths:}$prefix/include"
            library_paths="${library_paths:+$library_paths:}$prefix/lib"
            ;;
    esac
done
PKG_CONFIG_PATH="$package_paths${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export PATH PKG_CONFIG_PATH

# These dependencies also have direct compiler checks that bypass pkg-config.
CPATH="$header_paths${CPATH:+:$CPATH}"
LIBRARY_PATH="$library_paths${LIBRARY_PATH:+:$LIBRARY_PATH}"
export CPATH LIBRARY_PATH

exec "$@"
