function Show-RunSummary {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [object]$Installer,

    [Parameter(Mandatory)]
    [object]$SelectedRegistryEntry,

    [Parameter(Mandatory)]
    [object]$InstallResult,

    [Parameter(Mandatory)]
    [object]$UninstallResults,

    [Parameter(Mandatory)]
    [string]$LogPath
  )

    <#
    Write-Host 'Test Summary'
    Write-Host ''
    Write-Host ('Installer name: {0}' -f $Installer.Name)
    Write-Host ('Reg key: {0}' -f $SelectedRegistryEntry.RegistryPath)
    Write-Host ('DisplayVersion: {0}' -f ([string]$SelectedRegistryEntry.DisplayVersion))
    Write-Host ('Confirmed install string: {0}' -f $InstallResult.ConfirmedInstallCommand)
    Write-Host ('Confirmed uninstall string: {0}' -f $UninstallResults.ConfirmedUninstallCommand)
    Write-Host ''
    #>

  cls
  Show-Header -Title 'Complete'

    <#
    Write-Host ''
    Write-Host 'The above information has been saved to DetectionMethod.txt at the script''s root location'
    #>

  Write-Host ''
  Write-Host 'Press any key to start IntuneWin creation process...'
  Write-Host ''

  if ($LogPath) {
    Write-Log -LogPath $LogPath -Level INFO -Component 'Show-RunSummary' -Message 'Final summary displayed to user'
  }
}
