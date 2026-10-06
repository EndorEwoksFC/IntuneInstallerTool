function Read-YesNo {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Prompt,

        [string]$LogPath
    )

    if ($LogPath) {
        Write-Log -LogPath $LogPath -Level INFO -Component 'Read-YesNo' -Message "Prompted user: $Prompt"
    }

    while ($true) {
        Show-Header -Title $Prompt
        Write-Host ''
        Write-Host '1. Yes'
        Write-Host '2. No'
        Write-Host ''

        $response = Read-Host 'Enter selection'
        $selection = 0

        if ([int]::TryParse($response, [ref]$selection)) {
            switch ($selection) {
                1 {
                    if ($LogPath) {
                        Write-Log -LogPath $LogPath -Level INFO -Component 'Read-YesNo' -Message 'Yes/No response confirmed: Yes'
                    }

                    return $true
                }

                2 {
                    if ($LogPath) {
                        Write-Log -LogPath $LogPath -Level INFO -Component 'Read-YesNo' -Message 'Yes/No response confirmed: No'
                    }

                    return $false
                }
            }
        }

        cls
        Write-Host 'Invalid selection. Please enter 1 or 2.'
        if ($LogPath) {
            Write-Log -LogPath $LogPath -Level WARN -Component 'Read-YesNo' -Message "Invalid yes/no response entered: $response"
        }
    }
}