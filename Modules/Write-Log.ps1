function Write-Log {
    [CmdletBinding()]
    param ([Parameter(Mandatory)][string]$LogPath,[Parameter(Mandatory)][ValidateSet('INFO','WARN','ERROR')][string]$Level,[Parameter(Mandatory)][string]$Message,[string]$Component,[System.Management.Automation.ErrorRecord]$Exception)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = if ([string]::IsNullOrWhiteSpace($Component)) { "$timestamp [$Level] $Message" } else { "$timestamp [$Level] [$Component] $Message" }
    if ($Exception) { $errorText = $Exception.Exception.Message; if (-not [string]::IsNullOrWhiteSpace($errorText)) { $line = "$line - $errorText" } }
    $dir = Split-Path -Path $LogPath -Parent
    if (-not (Test-Path -Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    $fs=[System.IO.File]::Open($LogPath,[System.IO.FileMode]::Append,[System.IO.FileAccess]::Write,[System.IO.FileShare]::ReadWrite)
    try { $sw=New-Object System.IO.StreamWriter($fs,[System.Text.UTF8Encoding]::new($false)); try { $sw.WriteLine($line); $sw.Flush() } finally { $sw.Dispose() } } finally { $fs.Dispose() }
}