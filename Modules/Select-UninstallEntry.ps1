function Select-UninstallEntry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object[]]$Candidates,

        [string]$LogPath
    )

    if ($Candidates.Count -eq 1) {
        $displayName = if ([string]::IsNullOrWhiteSpace($Candidates[0].DisplayName)) {
            $Candidates[0].KeyName
        }
        else {
            $Candidates[0].DisplayName
        }

        <#
        Write-Host 'One uninstall registry entry was found and selected automatically:'
        Write-Host ''
        Write-Host ('1. {0} - "{1}"' -f $displayName, $Candidates[0].RegistryPath)
        #>

        if ($LogPath) {
            Write-Log -LogPath $LogPath -Level INFO -Component 'Select-UninstallEntry' -Message ("Uninstall entry selected automatically: {0}" -f $Candidates[0].RegistryPath)
        }

        return $Candidates[0]
    }

    $options = foreach ($candidate in $Candidates) {
        $displayName = if ([string]::IsNullOrWhiteSpace($candidate.DisplayName)) {
            $candidate.KeyName
        }
        else {
            $candidate.DisplayName
        }

        ('{0} - "{1}"' -f $displayName, $candidate.RegistryPath)
    }

    $selection = Show-Menu -Prompt 'Select a registry entry for uninstallation testing' -Options $options -LogPath $LogPath
    $selected = $Candidates[$selection.SelectedIndex - 1]

    if ($LogPath) {
        Write-Log -LogPath $LogPath -Level INFO -Component 'Select-UninstallEntry' -Message ("Uninstall entry selected: {0}" -f $selected.RegistryPath)
    }

    return $selected
}