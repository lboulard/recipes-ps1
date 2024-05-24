$ErrorActionPreference = "Stop"

$versionRegex = "^zig-windows-x86_64-(?<version>(?<branch>\d+\.\d+)(?:\.\d+){0,2})(?<dev>-dev.+\+[0-9a-f]+)?.*\.zip$"

$folderRegex = "^(?<version>\d+\.\d+(?:\.\d+){0,2})(?<dev>-dev)?$"
$lbPrograms = $Env:LBPROGRAMS
$prefix = $lbPrograms
$root = $PSScriptRoot

if (-not $prefix) {
  throw "prefix not defined. Is LBPROGRAMS environment variable defined?"
}
if (-not (Test-Path $prefix -PathType Container)) {
  throw "${prefix}: directory not found"
}

# ordered by version string
$folders = Get-ChildItem $root -Directory | Select-Object -ExpandProperty Name | Where-Object {
  $_ -match $folderRegex
} | Sort-Object -Unique -Descending -Property {
  if ($_ -match $folderRegex) {
    $version = $Matches.version
    $version += if ($Matches.dev) { "" } else { ".0" }
    $version = $version -as [version]
  }
  $version
}

if (-not $folders) {
  [Console]::Error.WriteLine($json)
  throw "no folder versions found"
}

# if we have branches '0.3-dev', '0.2', '0.2-dev', '0.1', '0.1-dev'
# we want to keep '0.3-dev', '0.2', '0.1' for installation candicates
# last development branch shall be installed, once released, shall be ignored

# For testing next statement
if ($false) {
  $files = @(
    [pscustomobject]@{
      Name      = 'zig-windows-x86_64-0.13.0-dev.100+facbncbn.zip'
      FullName  = '.\0.13-dev\zig-windows-x86_64-0.13.0-dev.100+facbncbn.zip'
      Directory = [pscustomobject]@{
        Name = '0.13-dev'
      }
    }
    [pscustomobject]@{
      Name      = 'zig-windows-x86_64-0.12.0.zip'
      FullName  = '.\0.12\zig-windows-x86_64-0.12.0.zip'
      Directory = [pscustomobject]@{
        Name = '0.12'
      }
    }
    [pscustomobject]@{
      Name      = 'zig-windows-x86_64-0.12.0-dev.100+facbncbn.zip'
      FullName  = '.\0.12-dev\zig-windows-x86_64-0.12.0-dev.100+facbncbn.zip'
      Directory = [pscustomobject]@{
        Name = '0.12-dev'
      }
    }
    [pscustomobject]@{
      Name      = 'zig-windows-x86_64-0.11.0.zip'
      FullName  = '.\0.11\zig-windows-x86_64-0.11.0.zip'
      Directory = [pscustomobject]@{
        Name = '0.11'
      }
    }
    [pscustomobject]@{
      Name      = 'zig-windows-x86_64-0.11.0-dev.100+facbncbn.zip'
      FullName  = '.\0.11-dev\zig-windows-x86_64-0.11.0-dev.100+facbncbn.zip'
      Directory = [pscustomobject]@{
        Name = '0.11-dev'
      }
    }
  )
}

# sort again, but from filename pattern
$files = $folders | Get-ChildItem -File | Where-Object {
  $_.Name -match $versionRegex
}
$selected = $files | Sort-Object -Unique -Descending -Property {
  if ($_.Name -match $versionRegex) {
    $version = $Matches.version
    $version += if ($Matches.dev) { "" } else { ".0" }
    $version -as [version]
  }
}, { $_ } | ForEach-Object -Begin { $seen = @{} } {
  # for filter to work, "0.x" is before "0.x-dev", see Sort-Object just before
  $version = $_.Directory.Name
  if ($version -match '-dev') {
    $version = $version -replace '-dev', ''
    if ($seen.ContainsKey($version)) {
      return $null
    }
  }
  if (-not $seen.ContainsKey($version)) {
    $seen.Add($version, $true)
  }
  $_
}

if (-not $selected) {
  [Console]::Error.WriteLine(($files | Select-Object -ExpandProperty FullName) -join "`n")
  throw "no files to install"
}


$count = if ($selected[0].Name -match '-dev') { 3 } else { 2 }
$toDeploy = $selected | Select-Object -First $count

# $toDeploy | Select-Object FullName

$apps = Join-Path $prefix "Apps"
$bin = Join-Path $prefix "bin"
$workDir = Join-Path $apps "zip-tmp"

function relative([string]$s) {
  ($s -replace [Regex]::Escape($prefix), '').Trim('\\')
}

Write-Host ":::: " -NoNewline
Write-Host "Will install:" (
  ($toDeploy | ForEach-Object {
    $_.Name -match $versionRegex | Out-Null
    "$($Matches.version)$($Matches.dev)"
  }) -join ", "
) -ForegroundColor Yellow
Write-Host

try {
  $toDeploy | ForEach-Object {
    $_.Name -match $versionRegex | Out-Null
    $branch = $Matches.Branch

    $archive = $_.FullName
    $name = $_.Name
    $basename = $_.Name -replace '\.zip', ''
    $isDev = ($name -match '-dev')

    $dest = Join-Path $apps $basename

    # expand and after verification of top folder name, install in final destination
    if (-not (Test-Path $dest)) {
      if (-not (Test-Path $workDir)) {
        New-Item $workDir -ItemType directory -Force | Out-Null
      }

      Write-Host ":: " -NoNewline
      Write-Host "Expand $(relative $name) to $(relative $apps)\" -ForegroundColor Yellow
      $installPath = Join-Path $workDir $basename
      if (Test-Path $installPath) {
        Remove-Item $installPath -Recurse -Force | Out-Null
      }
      Expand-Archive -DestinationPath $workDir -LiteralPath $archive -Force
      if (Test-Path $installPath) {
        Move-Item -Path $installPath -Destination $apps -Force
      } else {
        Write-Error "Expected $installPath not found after extraction"
        throw "$installPath not found"
      }
    } else {
      Write-Host ":: " -NoNewline
      Write-Host "${branch}: $name already found in $(relative $apps)\" -ForegroundColor Green
    }

    # always create symbolic links

    $symlink = Join-Path $bin "zig-$branch.exe"
    if (Test-Path $symlink) {
      Remove-Item $symlink -Force
    }
    if ($isDev) {
      $symlink = Join-Path $bin "zig-dev.exe"
      if (Test-Path $symlink) {
        Remove-Item $symlink -Force
      }
    } elseif (-not $mainSymlink) {
      # only first non-dev versoin is main zig.exe in symlink
      $mainSymlink = Join-Path $bin "zig.exe"
      if (Test-Path $mainSymlink) {
        Remove-Item $mainSymlink -Force
      }
    }

    $zigExe = Join-Path $dest 'zig.exe'

    $symlink = Join-Path $bin "zig-$branch.exe"
    Write-Host ":: " -NoNewline
    Write-Host "symLink $(relative $symlink) -> $(relative $zigExe)" -ForegroundColor Yellow
    New-Item -Path $symlink -ItemType symboliclink -Value $zigExe | Out-Null

    if ($name -match '-dev') {
      $symlink = Join-Path $bin "zig-dev.exe"
      Write-Host ":: " -NoNewline
      Write-Host "symLink $(relative $symlink) -> $(relative $zigExe)" -ForegroundColor Yellow
      New-Item -Path $symlink -ItemType symboliclink -Value $zigExe | Out-Null
    }

    if ($mainSymlink -and -not (Test-Path $mainSymlink)) {
      Write-Host ":: " -NoNewline
      Write-Host "symLink $(relative $mainSymlink)' -> $(relative $zigExe)" -ForegroundColor Yellow
      New-Item -Path $mainSymlink -ItemType symboliclink -Value $zigExe | Out-Null
    }
  }
} finally {
  if (Test-Path $workDir) {
    Remove-Item $workDir
  }
}
