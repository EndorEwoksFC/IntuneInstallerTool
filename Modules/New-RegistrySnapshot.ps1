function New-RegistrySnapshot {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$RegistryPath,

        [Parameter(Mandatory)]
        [string]$SnapshotLabel,

        [Parameter(Mandatory)]
        [string]$OutputFilePath,

        [string]$LogPath
    )

    if ($LogPath) {
        Write-Log -LogPath $LogPath -Level INFO -Component 'New-RegistrySnapshot' -Message "Starting registry snapshot: $SnapshotLabel for $RegistryPath"
    }

    try {
        if (-not (Test-Path -Path $RegistryPath)) {
            throw "Registry path was not found: $RegistryPath"
        }

        $entries = foreach ($key in (Get-ChildItem -Path $RegistryPath -ErrorAction Stop)) {
            $item = Get-ItemProperty -Path $key.PSPath -ErrorAction Stop

            [pscustomobject]@{
                RegistryPath = ($key.Name -replace '^HKEY_LOCAL_MACHINE', 'HKLM')
                KeyName = $key.PSChildName
                DisplayName = [string]$item.DisplayName
                DisplayVersion = [string]$item.DisplayVersion
                Publisher = [string]$item.Publisher
                InstallLocation = [string]$item.InstallLocation
                UninstallString = [string]$item.UninstallString
                QuietUninstallString = [string]$item.QuietUninstallString
                InstallDate = [string]$item.InstallDate
                WindowsInstaller = [string]$item.WindowsInstaller
                SystemComponent = [string]$item.SystemComponent
            }
        }

        $snapshot = [pscustomobject]@{
            SnapshotLabel = $SnapshotLabel
            RegistryRoot = $RegistryPath
            OutputFile = $OutputFilePath
            EntryCount = @($entries).Count
            Entries = @($entries)
            Success = $true
        }

        [System.IO.File]::WriteAllText($OutputFilePath, ($snapshot | ConvertTo-Json -Depth 6), [System.Text.UTF8Encoding]::new($false))

        if ($LogPath) {
            Write-Log -LogPath $LogPath -Level INFO -Component 'New-RegistrySnapshot' -Message "Collected $($snapshot.EntryCount) entries from $RegistryPath"
            Write-Log -LogPath $LogPath -Level INFO -Component 'New-RegistrySnapshot' -Message "Wrote registry snapshot to $OutputFilePath"
        }

        return $snapshot
    }
    catch {
        if ($LogPath) {
            Write-Log -LogPath $LogPath -Level ERROR -Component 'New-RegistrySnapshot' -Message "Registry snapshot failed for $RegistryPath" -Exception $_
        }

        throw
    }
}
