function Select-InstallerCandidate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object[]]$Candidates,

        [string]$LogPath
    )

    if ($Candidates.Count -eq 1) {
        Write-Host 'Installer found and selected automatically:'
        Write-Host ''
        Write-Host ('1. {0}' -f $Candidates[0].Name)

        if ($LogPath) {
            Write-Log -LogPath $LogPath -Level INFO -Component 'Select-InstallerCandidate' -Message "Installer selected automatically: $($Candidates[0].FullPath)"
        }

        return $Candidates[0]
    }

    $options = foreach ($candidate in $Candidates) {
        '{0} - "{1}"' -f $candidate.Name, $candidate.RelativePath
    }

    $menu = Show-Menu -Prompt "Select the software you'd like to test:" -Options $options -LogPath $LogPath
    $selected = $Candidates[$menu.SelectedIndex - 1]

    if ($LogPath) {
        Write-Log -LogPath $LogPath -Level INFO -Component 'Select-InstallerCandidate' -Message "Installer selected: $($selected.FullPath)"
    }

    return $selected
}
