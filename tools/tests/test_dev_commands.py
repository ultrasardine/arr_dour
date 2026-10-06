import ast
import contextlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


REPO = Path(__file__).resolve().parents[2]


class MakeCommandsTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        shutil.copyfile(REPO / "Makefile", self.root / "Makefile")
        (self.root / "tools").mkdir()
        shutil.copyfile(
            REPO / "tools/build-prerequisites.sh",
            self.root / "tools/build-prerequisites.sh",
        )
        (self.root / "gtk2_ardour").mkdir()
        fixture = """import json, os, sys
with open('calls.jsonl', 'a') as log:
    log.write(json.dumps(sys.argv) + '\\n')
if len(sys.argv) > 1 and sys.argv[1] == os.environ.get('FAIL_COMMAND'):
    sys.exit(7)
"""
        (self.root / "waf").write_text(fixture)
        launcher = self.root / "gtk2_ardour/ardev"
        launcher.write_text("#!" + sys.executable + "\n" + fixture)
        launcher.chmod(0o755)

    def run_make(self, *arguments, fail_command=None):
        environment = dict(os.environ)
        environment.pop("MAKEFLAGS", None)
        if fail_command:
            environment["FAIL_COMMAND"] = fail_command
        return subprocess.run(
            ["make", f"PYTHON={sys.executable}", "BUILD_ENV=", *arguments],
            cwd=self.root, env=environment, text=True, capture_output=True,
        )

    def calls(self):
        log = self.root / "calls.jsonl"
        return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []

    def test_help_groups_all_public_tasks_without_building(self):
        result = self.run_make("help")
        self.assertEqual(result.returncode, 0, result.stderr)
        for group in (
            "Current platform", "Debian / Linux", "macOS", "Options",
            "Examples", "Native Windows",
        ):
            self.assertIn(group, result.stdout)
        for task in (
            "help", "configure", "build", "run",
            "configure-debian", "build-debian", "run-debian",
            "configure-osx", "build-osx", "run-osx",
            "prerequisites", "prerequisites-debian", "prerequisites-osx",
            "deps-osx",
        ):
            self.assertRegex(result.stdout, rf"(?m)^  {re.escape(task)}\s+\S")
        self.assertEqual(self.calls(), [])

    def test_debian_build_and_options(self):
        result = self.run_make(
            "build-debian", "HOST_OS=Linux", "JOBS=2",
            "BACKENDS=alsa,jack", "CONFIGURE_FLAGS=--test --no-nls",
            "BUILD_FLAGS=--targets=libardour-tests",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), [
            ["waf", "configure", "--with-backends=alsa,jack", "--test", "--no-nls"],
            ["waf", "build", "-j2", "--targets=libardour-tests"],
        ])

    def test_osx_run_preserves_session_argument(self):
        result = self.run_make(
            "run-osx", "HOST_OS=Darwin", 'ARGS="My Session" --help',
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        configure, build, run = self.calls()
        self.assertIn("--with-backends=coreaudio", configure)
        self.assertEqual(build[1:], ["build", "-j4"])
        self.assertEqual(run[1:], ["My Session", "--help"])

    def test_generic_linux_defaults(self):
        result = self.run_make("build", "HOST_OS=Linux")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls()[0][1:], [
            "configure", "--with-backends=alsa", "--optimize", "--no-nls",
        ])

    def test_wrong_hosts_do_not_configure(self):
        for target, host in [
            ("build-debian", "Darwin"), ("run-osx", "Linux"),
            ("build", "Windows_NT"),
        ]:
            with self.subTest(target=target):
                result = self.run_make(target, f"HOST_OS={host}", "-j4")
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.calls(), [])

    def test_configure_failure_stops_build_and_run(self):
        result = self.run_make("run", "HOST_OS=Linux", fail_command="configure")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(self.calls()), 1)
        self.assertIn("sudo apt install", result.stderr)
        self.assertIn("build/config.log", result.stderr)

    def test_osx_configure_failure_prints_boost_and_stack_setup(self):
        result = self.run_make("configure-osx", "HOST_OS=Darwin", fail_command="configure")
        self.assertNotEqual(result.returncode, 0)
        for instruction in (
            "xcode-select --install", "make deps-osx", "tools/macos/Brewfile",
            "PKG_CONFIG_PATH", "git describe HEAD",
        ):
            self.assertIn(instruction, result.stderr)
        self.assertNotIn("ardour-build-tools", result.stderr)
        self.assertEqual(len(self.calls()), 1)

    def test_prerequisites_only_print_instructions(self):
        for target, host, command in (
            ("prerequisites-debian", "Linux", "sudo apt install"),
            ("prerequisites-osx", "Darwin", "make deps-osx"),
            ("prerequisites", "Darwin", "xcode-select --install"),
        ):
            with self.subTest(target=target):
                result = self.run_make(target, f"HOST_OS={host}")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(command, result.stdout)
        self.assertEqual(self.calls(), [])

    def test_build_failure_stops_run(self):
        result = self.run_make("run", "HOST_OS=Linux", fail_command="build")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual([call[1] for call in self.calls()], ["configure", "build"])

class MacOSBuildEnvironmentTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.prefix = self.root / "homebrew"
        formulae = re.findall(r'^brew "([^"]+)"', (REPO / "tools/macos/Brewfile").read_text(), re.M)
        for formula in formulae:
            (self.prefix / "opt" / formula).mkdir(parents=True)
        brew = self.bin / "brew"
        brew.write_text("""#!/bin/sh
if [ "$1" = --prefix ]; then
    if [ "$#" = 1 ]; then
        printf '%s\\n' "$TEST_BREW_PREFIX"
    else
        printf '%s\\n' "$TEST_BREW_PREFIX/opt/$2"
    fi
else
    printf '%s\\n' "$*" > "$TEST_BREW_LOG"
fi
""")
        brew.chmod(0o755)
        self.environment = {
            **os.environ,
            "PATH": f"{self.bin}:/usr/bin:/bin",
            "PKG_CONFIG_PATH": "/unrelated/pkgconfig",
            "TEST_BREW_PREFIX": str(self.prefix),
            "TEST_BREW_LOG": str(self.root / "brew.log"),
        }

    def invoke(self, *arguments):
        return subprocess.run(
            ["sh", "tools/macos/build-env.sh", *arguments], cwd=REPO,
            env=self.environment, text=True, capture_output=True,
        )

    def test_environment_is_configured_without_installing(self):
        result = self.invoke(sys.executable, "-c",
                             "import json, os; print(json.dumps(dict(os.environ)))")
        self.assertEqual(result.returncode, 0, result.stderr)
        environment = json.loads(result.stdout)
        self.assertIn(f"{self.prefix}/opt/boost/include", environment["CPATH"])
        self.assertIn(f"{self.prefix}/opt/gettext/lib", environment["LIBRARY_PATH"])
        self.assertIn(f"{self.prefix}/opt/jpeg-turbo/include", environment["CPATH"])
        self.assertIn(f"{self.prefix}/opt/jpeg-turbo/lib", environment["LIBRARY_PATH"])
        self.assertIn(f"{self.prefix}/opt/glibmm@2.66/lib/pkgconfig",
                      environment["PKG_CONFIG_PATH"])
        self.assertTrue(environment["PKG_CONFIG_PATH"].endswith("/unrelated/pkgconfig"))
        self.assertFalse((self.root / "brew.log").exists())

    def test_install_uses_this_repositories_manifest(self):
        result = self.invoke("install")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "brew.log").read_text().strip(),
                         "bundle install --file=tools/macos/Brewfile")

    def test_missing_package_prints_dependency_task(self):
        (self.prefix / "opt/boost").rmdir()
        result = self.invoke(sys.executable, "-c", "raise Exception('must not run')")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Missing Homebrew dependency: boost", result.stderr)
        self.assertIn("make deps-osx", result.stderr)


class GitVersionTest(unittest.TestCase):
    def setUp(self):
        tree = ast.parse((REPO / "wscript").read_text())
        functions = [
            node for node in tree.body if isinstance(node, ast.FunctionDef)
            and node.name in ("set_version", "fetch_git_revision_date")
        ]
        self.namespace = {"os": os, "re": re, "sys": sys, "subprocess": subprocess}
        exec(compile(ast.Module(body=functions, type_ignores=[]), "wscript", "exec"),
             self.namespace)

    def test_git_file_worktree_uses_git_version(self):
        fetch_git = mock.Mock(return_value=("9.0-2-gabc", "2026-10-06"))
        fetch_tarball = mock.Mock()
        self.namespace.update(
            fetch_git_revision_date=fetch_git,
            fetch_tarball_revision_date=fetch_tarball,
        )
        with tempfile.TemporaryDirectory() as directory:
            (Path(directory) / ".git").write_text("gitdir: /unused")
            with mock.patch.object(os, "getcwd", return_value=directory):
                self.namespace["set_version"]()
        fetch_git.assert_called_once()
        fetch_tarball.assert_not_called()
        self.assertEqual(self.namespace["VERSION"], "9.0.2")

    def test_from_file_still_uses_packaged_version(self):
        fetch_tarball = mock.Mock(return_value=("9.0", "2026-10-06"))
        self.namespace["fetch_tarball_revision_date"] = fetch_tarball
        self.namespace["set_version"](from_file=True)
        fetch_tarball.assert_called_once()
        self.assertEqual(self.namespace["VERSION"], "9.0.0")

    def test_missing_tags_reports_actionable_error(self):
        error = subprocess.CalledProcessError(
            128, ["git", "describe", "HEAD"], output=b"fatal: No names found",
        )
        output = io.StringIO()
        with mock.patch.object(subprocess, "check_output", side_effect=error):
            with contextlib.redirect_stdout(output), self.assertRaises(SystemExit):
                self.namespace["fetch_git_revision_date"]()
        self.assertIn("release tags", output.getvalue())
        self.assertIn("fatal: No names found", output.getvalue())


@unittest.skipUnless(shutil.which("pwsh"), "PowerShell is not installed")
class PowerShellCommandsTest(unittest.TestCase):
    def invoke_powershell(self, command, **environment):
        return subprocess.run(
            ["pwsh", "-NoProfile", "-Command", command],
            env={**os.environ, **environment}, text=True, capture_output=True,
        )

    def test_scripts_parse(self):
        for script in (REPO / "tools/windows").glob("*.ps1"):
            with self.subTest(script=script.name):
                command = """
$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    $env:ARDOUR_SCRIPT_TO_PARSE, [ref]$tokens, [ref]$errors)
if ($errors.Count) { $errors | Write-Error; exit 1 }
"""
                result = subprocess.run(
                    ["pwsh", "-NoProfile", "-Command", command],
                    env={**os.environ, "ARDOUR_SCRIPT_TO_PARSE": str(script)},
                    text=True, capture_output=True,
                )
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_windows_argument_quoting(self):
        result = self.invoke_powershell("""
. $env:ARDOUR_COMMON
@(
    (ConvertTo-ArdourWindowsArgument ''),
    (ConvertTo-ArdourWindowsArgument 'My Session'),
    (ConvertTo-ArdourWindowsArgument 'a"b'),
    (ConvertTo-ArdourWindowsArgument 'C:\\Sessions\\')
) | ConvertTo-Json -Compress
""", ARDOUR_COMMON=str(REPO / "tools/windows/common.ps1"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), [
            '""', '"My Session"', '"a\\"b"', '"C:\\Sessions\\\\"',
        ])

    def windows_fixture(self, root):
        scripts = root / "tools/windows"
        scripts.mkdir(parents=True)
        for name in ("build.ps1", "run.ps1"):
            shutil.copyfile(REPO / "tools/windows" / name, scripts / name)
        common = (REPO / "tools/windows/common.ps1").read_text()
        common += """
function Initialize-ArdourWindows {
    param([string]$DependencyRoot)
    $env:PATH = 'fixture;' + $env:PATH
    $env:DEPSTACK_ROOT = $DependencyRoot
    return $DependencyRoot
}
function global:test-python {
    $arguments = @($args)
    ConvertTo-Json -InputObject $arguments -Compress | Add-Content $env:ARDOUR_LOG
    $global:LASTEXITCODE = if ($arguments[1] -eq $env:ARDOUR_FAIL_COMMAND) { 7 } else { 0 }
}
function global:Start-Process {
    param($FilePath, [switch]$NoNewWindow, [switch]$PassThru,
          [switch]$Wait, $ArgumentList)
    ConvertTo-Json -InputObject @('launch', $FilePath, $ArgumentList) -Compress |
        Add-Content $env:ARDOUR_LOG
    return [pscustomobject]@{ ExitCode = 0 }
}
"""
        for name in ("git", "pkg-config", "cl", "link", "rc", "ml64", "llvm-nm"):
            common += f"\nfunction global:{name} {{}}\n"
        (scripts / "common.ps1").write_text(common)
        (root / "stack").mkdir()
        (root / "build/gtk2_ardour").mkdir(parents=True)
        (root / "build/gtk2_ardour/ardev_common_waf.sh").write_text(
            "EXECUTABLE=build/gtk2_ardour/ardour-9.0.0\n",
        )
        (root / "build/gtk2_ardour/ardour-9.0.0.exe").touch()
        (root / "build/libs/surfaces/test").mkdir(parents=True)
        (root / "build/libs/test.dll").touch()
        return scripts

    def test_build_run_and_environment_restoration(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            scripts = self.windows_fixture(root)
            log = root / "calls.jsonl"
            result = self.invoke_powershell("""
$beforePath = $env:PATH
$beforeLocation = (Get-Location).Path
& $env:ARDOUR_RUN -DependencyRoot $env:ARDOUR_STACK -Python test-python -Jobs 2 `
    -AppArgs @('C:\\Sessions\\My Session', '--help')
if ($env:PATH -ne $beforePath -or (Get-Location).Path -ne $beforeLocation) {
    throw 'Caller state was not restored'
}
""", ARDOUR_RUN=str(scripts / "run.ps1"), ARDOUR_STACK=str(root / "stack"),
                ARDOUR_LOG=str(log), ARDOUR_FAIL_COMMAND="")
            self.assertEqual(result.returncode, 0, result.stderr)
            configure, build, launch = [
                json.loads(line) for line in log.read_text().splitlines()
            ]
            self.assertIn("--dist-target=msvc", configure)
            self.assertIn("--with-backends=portaudio", configure)
            self.assertEqual(build, ["waf", "build", "-j2"])
            self.assertEqual(launch[2], '"C:\\Sessions\\My Session" "--help"')

    def test_failed_windows_configure_does_not_build_or_launch(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            scripts = self.windows_fixture(root)
            log = root / "calls.jsonl"
            result = self.invoke_powershell("""
$beforePath = $env:PATH
$beforeLocation = (Get-Location).Path
try {
    & $env:ARDOUR_RUN -DependencyRoot $env:ARDOUR_STACK -Python test-python
    throw 'Expected configure failure'
} catch {
    if ($env:PATH -ne $beforePath -or (Get-Location).Path -ne $beforeLocation) {
        throw 'Caller state was not restored after failure'
    }
    Write-Error $_
    exit 1
}
""", ARDOUR_RUN=str(scripts / "run.ps1"), ARDOUR_STACK=str(root / "stack"),
                ARDOUR_LOG=str(log), ARDOUR_FAIL_COMMAND="configure")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("failed (exit code 7)", result.stderr)
            self.assertEqual(len(log.read_text().splitlines()), 1)


if __name__ == "__main__":
    unittest.main()
