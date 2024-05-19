# Read a text file mapping for files on drive(s) and local files in Git repository

$ErrorActionPreference = "stop"

$script:SPACES = @([char]32, [char]"`t", [char]"`r", [char]"`n")

if (Test-Path (Join-Path $PSScriptRoot ".git")) {
  $script:Repository = $PSScriptRoot
} else {
  $ScriptName = (Split-Path $MyInvocation.MyCommand.Path -Leaf).Replace('.', '-')
  $script:Repository = (Join-Path $PSScriptRoot $ScriptName)
}

function GetFromQuotes ([string]$s) {
  $delim = $s[0]
  $unquoted = $s.SubString(1)
  $i = $unquoted.IndexOf($delim)
  if ($i -lt 0) {
    throw "final quote missing in string"
  }
  $unquoted, $rem = $unquoted.SubString(0, $i), $unquoted.SubString($i + 1)
  $i = $rem.IndexOfAny($script:SPACES)
  if ($i -ge 0) {
    $unquoted, $rem = ($unquoted + $rem.SubString(0, $i)), $rem.SubString($i + 1)
  } else {
    $unquoted, $rem = ($unquoted + $rem), ""
  }
  return $unquoted, $rem.TrimStart()
}

function GetString ([string]$s) {
  $s = $s.TrimStart()
  $first = $s[0]
  if (($first -eq [char]34) -or ($first -eq [char]39)) {
    $unquoted, $rem = GetFromQuotes ($s)
  } else {
    $i = $s.IndexOfAny($script:SPACES)
    if ($i -gt 0) {
      $unquoted, $rem = (
        $unquoted + $s.SubString($i),
        $s.SubString($i + 1).TrimStart()
      )
    } else {
      $unquoted, $rem = $s, ""
    }
  }
  return $unquoted, $rem.TrimStart()
}

function ReadFilesRecipes ([string]$filePath) {
  # Read file content as a single string
  $content = [IO.File]::ReadAllText($filePath, [Text.Encoding]::UTF8)

  # Initialize variables
  $currentLine = ""
  $lineNumber = 1
  $lastChar = ""
  $fields = New-Object Collections.Generic.List[SourceField]

  try {
    # Process each character
    for ($i = 0; $i -lt $content.Length; $i++) {
      $char = $content[$i]

      # Check for newline character
      if ($char -eq "`r" -or $char -eq "`n") {
        # Avoid two passed for CRLF end of line
        if ($lastChar -eq "`r" -and $char -eq "`n") { continue }

        $line = $currentLine
        if ($line -match "^\s*(?<name>[A-Za-z]\w*)\s*=\s*(?<value>.*)$") {
          $name = $Matches.Name
          $value, $rem = GetString $Matches.value
          if (-not $rem.Length -eq 0) {
            throw "line ${lineNumber}: extra chars at end of assignment"
          }
          $fields.Add([SourceAssignment]::new($name, $value))
        } elseif ($line -match "^\s*file\s+(?<args>.*)$") {
          $source, $dest = GetString $Matches.args
          $dest, $rem = GetString $dest

          if (-not $rem.Length -eq 0) {
            throw "line ${lineNumber}: extra chars at end of file copy definition"
          }
          $fields.Add([SourceFileCopy]::new($source, $dest))
        } elseif ($line -match "^\s*#(?<comment>.*)$") {
          $comment = $Matches.comment
          $fields.Add([SourceComment]::new($comment))
        } elseif ($line -match "^\s*$") {
          $fields.Add([SourceEmpty]::new())
        }

        $currentLine = ""
        $lineNumber++
      } else {
        $currentLine += $char
      }
      $lastChar = $char
    }
  } catch {
    Write-Error "Error: $($_.Exception.Message), line $($_.InvocationInfo.ScriptLineNumber), source line: $lineNumber" -ErrorAction Stop
  }

  return $fields.ToArray()
}

$filePath = Join-Path $PSScriptRoot "recipes-ps1.txt"
$templatePath = Join-Path $PSScriptRoot "recipes-to-repo.tmpl.bat"

$source = ReadFilesRecipes $filePath

class SourceVisitor {
  [void] StartVisit ([SourceField[]]$fields) {}
  [void] EndVisit ([SourceField[]]$fields) {}
  [void] VisitComment ([SourceComment]$comment) { throw [NotImplementedException]::new() }
  [void] VisitAssignment ([SourceAssignment]$assignment) { throw [NotImplementedException]::new() }
  [void] VisitFileCopy ([SourceFileCopy]$fileCopy) { throw [NotImplementedException]::new() }
  [void] VisitEmpty ([SourceEmpty]$empty) { throw [NotImplementedException]::new() }

  [void] Visit ([SourceField[]]$fields) {
    $this.StartVisit($fields)
    $fields | ForEach-Object { $_.Accept($this) }
    $this.EndVisit($fields)
  }

  [int] fileCount([SourceField[]]$fields) {
    return ($fields | Where-Object { $_ -is [SourceFileCopy] }).Count
  }
}

class SourceField {
  [void] Accept ([SourceVisitor]$visitor) { throw [NotImplementedException]::new() }
}

class SourceComment : SourceField {
  [string]$Comment

  SourceComment ([string]$comment) {
    $this.comment = $comment
  }

  [void] Accept ([SourceVisitor]$visitor) {
    $visitor.VisitComment($this)
  }
}

class SourceAssignment : SourceField {
  [string]$Name
  [string]$Value

  SourceAssignment ([string]$name, [string]$value) {
    $this.Name = $name
    $this.value = $value
  }

  [void] Accept ([SourceVisitor]$visitor) {
    $visitor.VisitAssignment($this)
  }
}

class SourceFileCopy : SourceField {
  [string]$Pathname
  [string]$DestFolder

  SourceFileCopy ([string]$pathname, [string]$destFolder) {
    $this.pathname = $pathname
    $this.destFolder = $destFolder
  }

  [void] Accept ([SourceVisitor]$visitor) {
    $visitor.VisitFileCopy($this)
  }
}

class SourceEmpty : SourceField {
  [void] Accept ([SourceVisitor]$visitor) {
    $visitor.VisitEmpty($this)
  }
}

class TextVisitor : SourceVisitor {
  [void] VisitComment ([SourceComment]$comment) { Write-Host "#", $comment.comment }
  [void] VisitAssignment ([SourceAssignment]$assignment) { Write-Host ('{0}="{1}"' -f $assignment.Name, $assignment.value) }
  [void] VisitFileCopy ([SourceFileCopy]$fileCopy) { Write-Host ("FILE '{0}', '{1}'" -f $filecopy.pathname, $filecopy.destFolder) }
  [void] VisitEmpty ([SourceEmpty]$empty) { Write-Host "<empty>" }
}

# [TextVisitor]::new().Visit($source)

class DosBatchVisitor : SourceVisitor {
  [boolean]$errorLevel = $false
  [string[]]$lines

  [void] write ([string]$s) {
    $this.lines += $s
  }

  [string] substitute ([string]$s) {
    return ($s -replace '\$(\w+)', '%${1}%')
  }

  [void] _set ([string]$name, [string]$value) {
    if ($value.IndexOfAny($script:SPACES) -ge 0) {
      $this.write(('@SET "{0}={1}"' -f $name, $value))
    } else {
      $this.write(('@SET {0}={1}' -f $name, $value))
    }
  }

  [void] _cp ([string]$pathname, [string]$destFolder) {
    $pathname, $destFolder = $this.substitute($pathname), $this.substitute($destFolder)
    $this.write(("@CALL :do :copy `"{0}`"`t`"{1}`"" -f $pathname, $destFolder))
    $this.errorLevel = $true
  }

  [void] StartVisit ([SourceField[]]$fields) {
    $this.errorLevel = $false
    $this.write("@:: start of generated section")
    $this.write("")
    $fileCount = $this.fileCount($fields)
    $this.write("@:: " + $fileCount + " files to check")
    $this._set("NFILES", $fileCount)
    $this._set("REPO", $script:Repository)
    $this.write("")
  }

  [void] VisitComment ([SourceComment]$comment) {
    $this.write("@::" + $comment.comment)
  }

  [void] VisitAssignment ([SourceAssignment]$assignment) {
    $this._set($assignment.Name, $this.substitute($assignment.value))
  }

  [void] VisitFileCopy ([SourceFileCopy]$fileCopy) {
    $this._cp($filecopy.pathname, $filecopy.destFolder)
  }

  [void] VisitEmpty ([SourceEmpty]$empty) {
    if ($this.errorLevel) {
      $this.write("@IF ERRORLEVEL 1 @GOTO :exit")
      $this.errorLevel = $false
    }
    $this.write("")
  }

  [void] EndVisit ([SourceField[]]$fields) {
    if ($this.errorLevel) {
      $this.write("@IF ERRORLEVEL 1 @GOTO :exit")
      $this.errorLevel = $false
    }
    $this.write("@:: end of generated section")
  }

  [string] ToString () {
    return $this.lines -join "`r`n"
  }
}

function NameFromTemplate ([string]$pathname) {
  Join-Path (Split-Path -Parent $pathname) ((Split-Path -Leaf $pathname) -replace "\.tmpl", "")
}

function SaveDosBatch ([string]$templatePath, [string]$destPath, [DosBatchVisitor]$visitor) {
  if ($templatePath -eq $destPath) {
    Write-Host $templatePath, $destPath
    throw ("Source and destination paths identical, path {0} shall contains`".tmpl`"" -f $templatePath)
  }

  $Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False
  $dosbatch = $visitor.ToString()

  Write-Output " * Generating ${dosbatchPath}"

  # output is array of string
  $content = (
    Get-Content $templatePath -Encoding UTF8 | ForEach-Object {
      if ($_ -match "^\s*::\s*{{\s*template\s*}}\s*$") {
        $dosbatch
      } else {
        $_
      }
    })
  [IO.File]::WriteAllLines($destPath, $content, $Utf8NoBomEncoding)
}

## Create file copy dosbatch

$v = [DosBatchVisitor]::new()
$v.Visit($source)
$dosbatchPath = NameFromTemplate $templatePath
SaveDosBatch $templatePath $dosbatchPath $v

## Create file comparison dosbatch

$script:EXTS = @(
  'bat'
  'ps1'
  'ps.1'
  'py'
  'rb'
  'c'
  'conf'
  'json'
  'url'
  'txt'
  'md'
  'xml'
  'yml'
  'yaml'
  'inf'
  'ini'
  'reg'
  'asc'
  'sig'
  'sha1'
  'sha256'
  'sha512'
) -join '|'

$script:EXCLUDE = @(
  'wfetch-.*\.bat'
) -join '|'

$registryPath = "HKCU:\SOFTWARE\Scooter Software\Beyond Compare"
$valueName = "ExePath"

Write-Output ""

try {
  $exePath = Get-ItemPropertyValue -Path $registryPath -Name $valueName -ErrorAction Stop
  $script:bc4InstallPath = Split-Path $exePath
  Write-Output " * Beyond Compare installation found: ${script:bc4InstallPath}"
} catch {
  Write-Warning "Failed to read the registry value: $_"
  Write-Warning "Beyond Compare installation not found"
  $script:bc4InstallPath = ""
}

class FileCompareVisitor : DosBatchVisitor {

  [string] keepFile( [SourceFileCopy]$FileCopy, [switch]$Verbose) {
    $pathname = $FileCopy.Pathname
    $accepted = $pathname -match "\.($($script:EXTS))$"
    $rejected = $pathname -match "($($script:EXCLUDE))"
    if ($Verbose) {
      Write-Verbose "compare ${pathname}: accepted=${accepted} rejected=${rejected}"
    }
    if ($accepted -and (-not $rejected)) {
      return $pathname
    } else {
      return $null
    }
  }

  [int] fileCount([SourceField[]]$fields) {
    return ($fields | Where-Object {
      ($_ -is [SourceFileCopy]) -and $this.keepFile($_, $true)
      }).Count
  }

  [void] StartVisit ([SourceField[]]$fields) {
    ([DosBatchVisitor]$this).StartVisit($fields)
    $this.write("")
    if ($script:bc4InstallPath) {
      $this.write("@:: Add Beyond Compare path to BComp.exe")
      $this.write("@PATH ${script:bc4InstallPath};%PATH%")
    } else {
      $this.write("@ECHO.** WARNING : Beyond Compare installation not found")
    }
    $this.write("")
  }

  [void] VisitFileCopy ([SourceFileCopy]$fileCopy) {
    $pathname = $this.keepFile($fileCopy, $false)
    if ($pathname) {
      $pathname, $destFolder = $this.substitute($fileCopy.pathname), $this.substitute($fileCopy.destFolder)
      $this.write(("@CALL :do :bcomp `"{0}`"`t`"{1}`"" -f $pathname, $destFolder))
      $this.errorLevel = $true
    } else {
      $pathname = Join-Path $fileCopy.DestFolder (Split-Path $fileCopy.Pathname -Leaf)
      Write-Host "   Ignoring ${pathname}"
    }
  }
}

$v = [FileCompareVisitor]::new()
$v.Visit($source)
$dosbatchPath = (NameFromTemplate $templatePath) -replace '-repo', '-bcomp'
SaveDosBatch $templatePath $dosbatchPath $v
