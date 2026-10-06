[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$DependencyRoot,
    [string]$Python = 'python',
    [ValidateRange(1, 256)][int]$Jobs = 4,
    [string[]]$ConfigureArgs = @('--optimize', '--no-nls'),
    [string[]]$BuildArgs = @()
)

. (Join-Path $PSScriptRoot 'common.ps1')
$DependencyRoot = (Resolve-Path -LiteralPath $DependencyRoot).Path

$savedEnvironment = @{}
foreach ($name in @('PATH', 'PKG_CONFIG_PATH', 'DEPSTACK_ROOT')) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

Push-Location (Join-Path $PSScriptRoot '../..')
try {
    $root = Initialize-ArdourWindows -DependencyRoot $DependencyRoot
    foreach ($command in @($Python, 'git', 'pkg-config', 'cl', 'link', 'rc', 'ml64', 'llvm-nm')) {
        if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
            throw "Missing '$command'. Use an x64 Visual Studio Developer PowerShell with LLVM and the MSVC dependency stack on PATH."
        }
    }

    $wafArgs = @(
        'configure',
        '--dist-target=msvc',
        '--with-backends=portaudio',
        "--also-include=$(Join-Path $root 'include')",
        "--also-libdir=$(Join-Path $root 'lib')"
    ) + $ConfigureArgs
    Invoke-ArdourWaf -Python $Python -WafArgs $wafArgs
    Invoke-ArdourWaf -Python $Python -WafArgs (@('build', "-j$Jobs") + $BuildArgs)
}
finally {
    Pop-Location
    foreach ($name in $savedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
    }
}
