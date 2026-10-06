[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$DependencyRoot,
    [string]$Python = 'python',
    [ValidateRange(1, 256)][int]$Jobs = 4,
    [string[]]$ConfigureArgs = @('--optimize', '--no-nls'),
    [string[]]$BuildArgs = @(),
    [string[]]$AppArgs = @(),
    [switch]$SkipBuild
)

. (Join-Path $PSScriptRoot 'common.ps1')
$DependencyRoot = (Resolve-Path -LiteralPath $DependencyRoot).Path

if (-not $SkipBuild) {
    & (Join-Path $PSScriptRoot 'build.ps1') -DependencyRoot $DependencyRoot `
        -Python $Python -Jobs $Jobs -ConfigureArgs $ConfigureArgs -BuildArgs $BuildArgs
}

$savedEnvironment = @{}
$environmentNames = @(
    'PATH', 'PKG_CONFIG_PATH', 'DEPSTACK_ROOT', 'ARDOUR_DLL_PATH',
    'ARDOUR_CONFIG_PATH', 'ARDOUR_DATA_PATH', 'ARDOUR_BACKEND_PATH',
    'ARDOUR_SURFACES_PATH', 'ARDOUR_PANNER_PATH', 'ARDOUR_MIDIMAPS_PATH',
    'ARDOUR_MIDI_PATCH_PATH', 'ARDOUR_EXPORT_FORMATS_PATH', 'ARDOUR_THEMES_PATH',
    'ARDOUR_MCP_PATH', 'VAMP_PATH', 'SUIL_MODULE_DIR'
)
foreach ($name in $environmentNames) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

Push-Location (Join-Path $PSScriptRoot '../..')
try {
    $null = Initialize-ArdourWindows -DependencyRoot $DependencyRoot
    $repo = (Get-Location).Path
    $libs = Join-Path $repo 'build/libs'
    $wrapper = Join-Path $repo 'build/gtk2_ardour/ardev_common_waf.sh'
    if (-not (Test-Path -LiteralPath $wrapper -PathType Leaf)) {
        throw 'No configured development launcher found. Run build.ps1 first.'
    }
    $match = [regex]::Match((Get-Content -LiteralPath $wrapper -Raw), '(?m)^EXECUTABLE=(.+)\r?$')
    if (-not $match.Success) {
        throw "Cannot read the configured executable from '$wrapper'."
    }
    $executable = Join-Path $repo ($match.Groups[1].Value.Trim() + '.exe')
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
        throw "Missing '$executable'. Run build.ps1 first."
    }

    $dllDirectories = Get-ChildItem -LiteralPath $libs -Filter '*.dll' -Recurse -File |
        ForEach-Object { $_.DirectoryName } | Sort-Object -Unique
    $env:PATH = @($dllDirectories; $env:PATH) | Join-ArdourPath
    $env:ARDOUR_DLL_PATH = $libs
    $env:ARDOUR_CONFIG_PATH = @($repo; "$repo/gtk2_ardour"; "$repo/build"; "$repo/build/gtk2_ardour") | Join-ArdourPath
    $env:ARDOUR_DATA_PATH = @("$repo/share"; "$repo/build"; "$repo/gtk2_ardour"; "$repo/build/gtk2_ardour") | Join-ArdourPath
    $env:ARDOUR_BACKEND_PATH = @('portaudio', 'dummy', 'jack') |
        ForEach-Object { Join-Path $libs "backends/$_" } | Join-ArdourPath
    $env:ARDOUR_SURFACES_PATH = Get-ChildItem -LiteralPath "$libs/surfaces" -Directory |
        ForEach-Object { $_.FullName } | Join-ArdourPath
    $env:ARDOUR_PANNER_PATH = Join-Path $libs 'panners'
    $env:ARDOUR_MIDIMAPS_PATH = Join-Path $repo 'share/midi_maps'
    $env:ARDOUR_MIDI_PATCH_PATH = Join-Path $repo 'share/patchfiles'
    $env:ARDOUR_EXPORT_FORMATS_PATH = Join-Path $repo 'share/export'
    $env:ARDOUR_THEMES_PATH = Join-Path $repo 'gtk2_ardour/themes'
    $env:ARDOUR_MCP_PATH = Join-Path $repo 'share/mcp'
    $env:VAMP_PATH = @("$libs/vamp-plugins"; "$libs/vamp-pyin"; $env:VAMP_PATH) |
        Where-Object { $_ } | Join-ArdourPath
    $env:SUIL_MODULE_DIR = Join-Path $libs 'tk/suil'

    $startParameters = @{
        FilePath = $executable
        NoNewWindow = $true
        PassThru = $true
        Wait = $true
    }
    if ($AppArgs.Count -gt 0) {
        $startParameters.ArgumentList = ($AppArgs |
            ForEach-Object { ConvertTo-ArdourWindowsArgument $_ }) -join ' '
    }
    $process = Start-Process @startParameters
    if ($process.ExitCode -ne 0) {
        throw "Ardour exited with code $($process.ExitCode)."
    }
}
finally {
    Pop-Location
    foreach ($name in $savedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
    }
}
