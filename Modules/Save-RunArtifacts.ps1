function Save-RunArtifacts {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]$Installer,

        [Parameter(Mandatory)]
        [object]$SelectedRegistryEntry,

        [Parameter(Mandatory)]
        [object]$InstallResult,

        [Parameter(Mandatory)]
        [object[]]$UninstallResults,

        [Parameter(Mandatory)]
        [string]$DetectionMethodPath,

        [string]$LogPath
    )

    if ($LogPath) {
        Write-Log -LogPath $LogPath -Level INFO -Component 'Save-RunArtifacts' -Message ("Writing DetectionMethod.txt to {0}" -f $DetectionMethodPath)
    }

    $displayVersion = [string]$SelectedRegistryEntry.DisplayVersion

    $lines = @(
        'Detection Method Summary',
        '------------------------',
        ('Installer name: {0}' -f $Installer.Name),
        ('Reg key: {0}' -f $SelectedRegistryEntry.RegistryPath),
        ('DisplayVersion: {0}' -f $displayVersion),
        ('Confirmed install string: {0}' -f $InstallResult.ConfirmedInstallCommand),
        ('Uninstall string key: {0}' -f ([string]$UninstallResults.UninstallStringSource)),
        'Confirmed uninstall string(s):'
     )

    foreach ($result in $UninstallResults) {
        $lines += ('- [{0}] {1}' -f ([string]$result.UninstallStringSource), $result.ConfirmedUninstallCommand)
    }

    try {
        [System.IO.File]::WriteAllLines($DetectionMethodPath, $lines, [System.Text.UTF8Encoding]::new($false))

        if ($LogPath) {
            Write-Log -LogPath $LogPath -Level INFO -Component 'Save-RunArtifacts' -Message 'DetectionMethod.txt written successfully'
        }

        return [pscustomobject]@{
            Success = $true
            DetectionFilePath = $DetectionMethodPath
        }
    }
    catch {
        if ($LogPath) {
            Write-Log -LogPath $LogPath -Level ERROR -Component 'Save-RunArtifacts' -Message 'Failed to write DetectionMethod.txt' -Exception $_
        }
        throw
    }
}