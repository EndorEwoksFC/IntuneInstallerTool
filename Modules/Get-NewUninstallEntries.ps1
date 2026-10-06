function Get-NewUninstallEntries {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]$RegistryComparison,

        [string]$LogPath
    )

    try {
        $list = @()

        foreach ($e in $RegistryComparison.Native.Added) {
            $list += [pscustomobject]@{
                RegistryHiveGroup = 'Native'
                RegistryPath = $e.RegistryPath
                KeyName = $e.KeyName
                DisplayName = $e.DisplayName
                DisplayVersion = $e.DisplayVersion
                Publisher = $e.Publisher
                InstallLocation = $e.InstallLocation
                UninstallString = $e.UninstallString
                QuietUninstallString = $e.QuietUninstallString
            }
        }

        foreach ($e in $RegistryComparison.Wow6432Node.Added) {
            $list += [pscustomobject]@{
                RegistryHiveGroup = 'Wow6432Node'
                RegistryPath = $e.RegistryPath
                KeyName = $e.KeyName
                DisplayName = $e.DisplayName
                DisplayVersion = $e.DisplayVersion
                Publisher = $e.Publisher
                InstallLocation = $e.InstallLocation
                UninstallString = $e.UninstallString
                QuietUninstallString = $e.QuietUninstallString
            }
        }

        if ($LogPath) {
            Write-Log -LogPath $LogPath -Level INFO -Component 'Get-NewUninstallEntries' -Message "Native added entries: $($RegistryComparison.Native.Added.Count)"
            Write-Log -LogPath $LogPath -Level INFO -Component 'Get-NewUninstallEntries' -Message "WOW6432Node added entries: $($RegistryComparison.Wow6432Node.Added.Count)"
            Write-Log -LogPath $LogPath -Level INFO -Component 'Get-NewUninstallEntries' -Message "Total uninstall candidates returned: $($list.Count)"
        }

        return @($list)
    }
    catch {
        if ($LogPath) {
            Write-Log -LogPath $LogPath -Level ERROR -Component 'Get-NewUninstallEntries' -Message 'Failed to build uninstall candidate list' -Exception $_
        }

        throw
    }
}
