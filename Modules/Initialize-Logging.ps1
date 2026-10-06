function Initialize-Logging {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$LogPath
    )

    $parentPath = Split-Path -Path $LogPath -Parent

    if (-not (Test-Path -Path $parentPath)) {
        New-Item -Path $parentPath -ItemType Directory -Force | Out-Null
    }

    if (-not (Test-Path -Path $LogPath)) {
        $fs = [System.IO.File]::Open($LogPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
        $fs.Dispose()
    }

    $banner = "==== Installer Test Tool Session Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===="
    $fs = [System.IO.File]::Open($LogPath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)

    try {
        $sw = New-Object System.IO.StreamWriter($fs, [System.Text.UTF8Encoding]::new($false))

        try {
            $sw.WriteLine('')
            $sw.WriteLine($banner)
            $sw.Flush()
        }
        finally {
            $sw.Dispose()
        }
    }
    finally {
        $fs.Dispose()
    }

    return $true
}
