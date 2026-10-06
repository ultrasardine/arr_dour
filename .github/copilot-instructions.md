# Copilot instructions

## Build and test

- This fork's `Makefile` wraps Waf for Debian/macOS (`make build`, `make run`,
  or the `-debian`/`-osx` aliases). Native Windows uses
  `tools/windows/build.ps1` and `run.ps1` with an MSVC dependency stack.
  macOS dependencies are declared in `tools/macos/Brewfile` and installed with
  `make deps-osx`; `build-env.sh` supplies their paths to all macOS tasks.
  `README.md` describes platform prerequisites and overrides.
  CI (`.github/workflows/build.yml`) builds Debian and macOS with these
  tasks; keep its Debian package list in sync with `README.md` and
  `tools/build-prerequisites.sh`. Wrapper tests:
  `python3 -m unittest discover -s tools/tests -p 'test_dev_commands.py'`.
- Ardour uses the repository's Waf wrapper (`./waf`) and requires a full Git
  clone for version information (`git describe`). Configure for the local
  platform and available dependencies with `./waf configure`; see
  `./waf configure --help` for backend and build options. Build with
  `./waf build -j<N>`.
- Unit tests are opt-in. Configure with `./waf configure --test`, then build
  the libardour test target with
  `./waf build --targets=libardour-tests`. Run it from the repository root
  with `./libs/ardour/run-tests.sh`.
- To build individual libardour test executables, configure with
  `./waf configure --test --single-tests`, build with `./waf build` (or select
  a `unit-test-*` target from `libs/ardour/wscript`), then run one
  matching executable with
  `./libs/ardour/run-tests.sh --single <test-name-substring>`.
  `doc/unit_tests.txt` describes the combined-suite workflow.

## Architecture

- `gtk2_ardour/` is the main GTK2 user interface. It is separate from the
  processing engine; session and audio behavior belongs in `libs/ardour/`
  (`Session`, `Route`, `Processor`), not in GUI code.
- `libs/ardour/` hosts sessions, routing, plugins, and real-time audio
  processing. Audio backends in `libs/backends/` implement operating-system
  audio/MIDI APIs and are selected at configure time. Dynamically loaded
  control-surface protocols live in `libs/surfaces/`.
- The engine relies on supporting Ardour libraries: `libs/pbd/` provides
  foundational utilities and OS abstractions; `libs/evoral/` handles events,
  automation, and MIDI event abstractions; `libs/temporal/` owns time types
  and `TempoMap`; `libs/midi++2/` handles MIDI I/O and MIDNAM; and
  `libs/audiographer/` supplies the source/sink graphs used for export.
- Other entry points include `headless/`, `session_utils/`, and `luasession/`.
  Resources and bundled presets, scripts, MIDI maps, and control-surface
  definitions are under `share/`.

## Repository-specific conventions

- The top-level `wscript` orchestrates configuration and recursively includes
  component `wscript` files. Keep build and dependency changes in the
  appropriate component rather than bypassing the Waf build.
- Ardour's audio processing is real-time sensitive. When changing engine or
  backend code, preserve the existing separation between real-time processing
  and work done on other threads.
- C++ editor settings in `.dir-locals.el` use tabs for indentation and a
  79-column fill width. Follow the surrounding file's conventions.
- Unit tests are enabled by the top-level Waf `--test` option; test sources
  and library-specific runner scripts are colocated with their libraries.
