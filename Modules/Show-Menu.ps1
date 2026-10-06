function Show-Menu {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Prompt,

        [Parameter(Mandatory)]
        [object[]]$Options,

        [string]$LogPath
    )

    if ($LogPath) {
        Write-Log -LogPath $LogPath -Level INFO -Component 'Show-Menu' -Message "Displayed menu: $Prompt"
    }

    while ($true) {
        Show-Header -Title $Prompt
        Write-Host ''

        for ($i = 0; $i -lt $Options.Count; $i++) {
            Write-Host ("{0}. {1}" -f ($i + 1), [string]$Options[$i])
        }

        Write-Host ''
        $response = Read-Host 'Enter selection'
        $selection = 0

        if ([int]::TryParse($response, [ref]$selection) -and $selection -ge 1 -and $selection -le $Options.Count) {
            if ($LogPath) {
                Write-Log -LogPath $LogPath -Level INFO -Component 'Show-Menu' -Message "Menu selection confirmed: $selection"
            }

            cls

            return [pscustomobject]@{
                SelectedIndex = $selection
                SelectedValue = $Options[$selection - 1]
            }
        }

        if ($LogPath) {
            Write-Log -LogPath $LogPath -Level WARN -Component 'Show-Menu' -Message "Invalid menu selection entered: $response"
        }

        cls
        Show-Header -Title 'Invalid selection'
        Write-Host ''
        Write-Host 'Invalid selection. Please enter one of the listed numbers.'
        Write-Host ''
    }
}