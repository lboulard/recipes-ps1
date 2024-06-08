$ErrorActionPreference = "Stop"

$versionPattern = "/(?<tag>(?<version>\d+\.\d+(\.\d+){0,2}))$"
$project = "zigtools/zls"

$lastReleaseURL = "https://github.com/$project/releases/latest"
try {
  $response = Invoke-WebRequest -Method Head -Uri $lastReleaseURL -ErrorAction Ignore
  $statusCode = $response.StatusCode
  Write-Verbose ("`$statusCode={0}" -f $statusCode)
} catch {
  Write-Verbose $_.Exception
  $statusCode = $_.Exception.Response.StatusCode.value__
}
if ($statusCode -eq 302) {
  $lastVersionURL = $response.Headers.Location
} elseif ($statusCode -eq 200) {
  if ($response.BaseResponse.ResponseUri -ne $null) {
    # PS5.1
    $lastVersionURL = $response.BaseResponse.ResponseUri.AbsoluteUri
    Write-Verbose ("`$lastVersionURL={0}" -f $lastVersionURL)
  } elseif ($response.BaseResponse.RequestMessage.RequestUri -ne $null) {
    # PS7
    $lastVersionURL = $response.BaseResponse.RequestMessage.RequestUri.AbsoluteUri
    Write-Verbose ("`$lastVersionURL={0}" -f $lastVersionURL)
  }
} else {
  Write-Error ("HTTP Response {0}: {1}" -f $statusCode, $response.StatusDescription)
  throw ("unexpected response {0} for {1}" -f $statusCode, $lastReleaseURL)
}

if ($lastVersionURL) {
  Write-Host "# last Version" $lastVersionURL -Separator "`n"
} else {
  throw "no release found at ${lastReleaseURL}"
}

($lastVersionURL -match $versionPattern) | Out-Null
$tag = $Matches.tag
$version = $Matches.version

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class CredentialManager {
    [DllImport("advapi32", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool CredRead(string target, int type, int reservedFlag, out IntPtr credentialPtr);

    [DllImport("advapi32", SetLastError = true)]
    public static extern void CredFree(IntPtr cred);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct CREDENTIAL {
        public int Flags;
        public int Type;
        public IntPtr TargetName;
        public IntPtr Comment;
        public long LastWritten;
        public int CredentialBlobSize;
        public IntPtr CredentialBlob;
        public int Persist;
        public int AttributeCount;
        public IntPtr Attributes;
        public IntPtr TargetAlias;
        public IntPtr UserName;
    }

    public static string GetCredential(string targetName) {
        IntPtr credPtr;
        if (CredRead(targetName, 1, 0, out credPtr)) {
            var credential = (CREDENTIAL)Marshal.PtrToStructure(credPtr, typeof(CREDENTIAL));
            string password = Marshal.PtrToStringUni(credential.CredentialBlob, credential.CredentialBlobSize / 2);
            CredFree(credPtr);
            return password;
        } else {
            throw new Exception("Failed to retrieve credential from Windows Credential Manager.");
        }
    }
}
"@

# check API key exists with 'cmdkey.exe /list:git:https://github.com'

function Get-GitHubToken {
  param (
    [string]$targetName = "git:https://github.com"
  )

  try {
    $token = [CredentialManager]::GetCredential($targetName)
    return $token
  } catch {
    Write-Error $_.Exception.Message
    return $null
  }
}

# filenames are not enough to find release files
# use GitHub API

$headers = @{
  'Accept'               = 'application/vnd.github+json'
  "X-GitHub-Api-Version" = "2022-11-28"
}

$githubToken = $env:GITHUB_TOKEN
if (-not $githubToken) {
  # Get the GitHub API token from Windows Credential for git
  $githubToken = Get-GitHubToken
  if ($githubToken) {
    $headers['Authorization'] = 'Bearer ' + $githubToken
  }
} else {
  $headers['Authorization'] = 'token ' + $githubToken
}

$wanted = "zls-(x86_64|aarch64)-(windows\.zip|linux\.tar\.gz|linux\.tar\.xz)"

try {
  $json = Invoke-WebRequest -Uri "https://api.github.com/repos/$project/releases/tags/$tag" -Headers $headers -UseBasicParsing
  $release = $json.Content | ConvertFrom-Json
  $files = $release.assets | ForEach-Object {
    $asset = $_
    $name = $asset.name
    if ($name -match $wanted) {
      $name = $name -replace "\.(exe|zip|tar\.(gz|xz))", "-${version}`$0"
      "$($asset.browser_download_url)#zls-${version}/${name}"
    }
  }
} catch {
  Write-Error "Error: $($_.Exception.Message), line $($_.InvocationInfo.ScriptLineNumber)"
  break
}

$headers['Accept'] = 'application/octet-stream'

$folders = @{}  # remember created folder to create only once

$files | ForEach-Object {
  $url = [System.Uri]($_)
  $src = $url.AbsoluteUri
  if ($url.Fragment -and ($url.Fragment.Length -gt 1)) {
    $dest = [Uri]::UnescapeDataString($url.Fragment.Substring(1))
  } else {
    $dest = [Uri]::UnescapeDataString($url.Segments[-1])
  }

  Write-Host "# $dest"
  if (-not (Test-Path $dest)) {
    try {
      Write-Host "  -> $src"
      $parent = Split-Path -Parent -Path $dest
      if ($parent -and -not $folders.Contains($parent)) {
        if (-not (Test-Path $parent -PathType Container)) {
          New-Item -Path $parent -ItemType Container | Out-Null
        }
        $folders.Add($parent, $True)
      }
      $tmpFile = "$dest.tmp"
      $result = Invoke-WebRequest -Uri "$src" -OutFile $tmpFile -UseBasicParsing -PassThru
      $lastModified = $result.Headers['Last-Modified']
      # PS7 returns array, PS5 returns string
      if ($lastModified -is [array]) { $lastModified = $lastModified[0] }
      if ($lastModified) {
        try {
          $lastModifiedDate = Get-Date $lastModified
          (Get-Item $tmpFile).LastWriteTimeUtc = $lastModifiedDate
        } catch {
          Write-Error "Error: $($_.Exception.Message)"
          Write-Error "Date: $lastModified"
        }
      }
      Move-Item -Path $tmpFile -Destination "$dest"
    } catch {
      Write-Error "Error: $($_.Exception.Message), line $($_.InvocationInfo.ScriptLineNumber)" -TargetObject $_
      break
    }
  }
}
