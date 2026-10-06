Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Initialize-ArdourWindows {
    param([Parameter(Mandatory = $true)][string]$DependencyRoot)

    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw 'These scripts require native Windows, not WSL.'
    }

    $root = (Resolve-Path -LiteralPath $DependencyRoot).Path
    foreach ($directory in @('bin', 'include', 'lib', 'lib/pkgconfig')) {
        if (-not (Test-Path -LiteralPath (Join-Path $root $directory) -PathType Container)) {
            throw "Missing $directory in dependency stack '$root'. See README.md for the required MSVC stack."
        }
    }

    $env:DEPSTACK_ROOT = $root
    $env:PATH = "$(Join-Path $root 'bin');$env:PATH"
    $env:PKG_CONFIG_PATH = @(
        (Join-Path $root 'lib/pkgconfig')
        (Join-Path $root 'share/pkgconfig')
        $env:PKG_CONFIG_PATH
    ) | Where-Object { $_ } | Join-ArdourPath
    return $root
}

function Join-ArdourPath {
    begin { $paths = @() }
    process { $paths += $_ }
    end { $paths -join [IO.Path]::PathSeparator }
}

function Invoke-ArdourWaf {
    param(
        [Parameter(Mandatory = $true)][string]$Python,
        [Parameter(Mandatory = $true)][string[]]$WafArgs
    )
    & $Python waf @WafArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Waf $($WafArgs[0]) failed (exit code $LASTEXITCODE)."
    }
}

function ConvertTo-ArdourWindowsArgument {
    param([AllowEmptyString()][string]$Value)
    $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    $escaped = [regex]::Replace($escaped, '\\+$', '$0$0')
    return '"' + $escaped + '"'
}
