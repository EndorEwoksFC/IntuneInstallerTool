function Get-RecommendedInstallCommand {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]$Installer,

        [Parameter(Mandatory)]
        [object]$Metadata,

        [string]$LogPath
    )

    if ($LogPath) {
        Write-Log -LogPath $LogPath -Level INFO -Component 'Get-RecommendedInstallCommand' -Message "Building install recommendation for $($Installer.Extension)"
    }

    $fp = $Installer.FullPath
    $args = ''
    $type = 'None'
    $confidence = 'None'
    $reason = 'No reliable silent install pattern detected'

    switch ($Installer.Extension) {
        '.msi' {
            $type = 'Recommended'
            $confidence = 'High'
            $reason = 'MSI silent install pattern'
            $args = '/i "' + $fp + '" /qn /norestart'

            if ($Metadata.PublicProperties -and $Metadata.PublicProperties.Count -gt 0) {
                $args += ' ' + ($Metadata.PublicProperties -join ' ')
            }

            $full = 'msiexec.exe ' + $args
            $result = [pscustomobject]@{
                CommandType = $type
                FilePath = $fp
                Arguments = $args
                FullCommand = $full
                Confidence = $confidence
                Reason = $reason
            }

            if ($LogPath) {
                Write-Log -LogPath $LogPath -Level INFO -Component 'Get-RecommendedInstallCommand' -Message "Recommendation generated with confidence $confidence"
            }

            return $result
        }
        '.exe' {
            if (-not [string]::IsNullOrWhiteSpace($Metadata.SuggestedArgs)) {
                $type = 'Recommended'
                $confidence = $Metadata.SuggestionConfidence
                $reason = if ($Metadata.WrapperType) {
                    "$($Metadata.WrapperType) heuristic"
                }
                else {
                    'Executable heuristic'
                }
                $args = $Metadata.SuggestedArgs
            }
        }
        default {
        }
    }

    if ($type -eq 'Recommended') {
        $full = '"' + $fp + '" ' + $args
    }
    else {
        $full = ''
    }

    $result = [pscustomobject]@{
        CommandType = $type
        FilePath = $fp
        Arguments = $args
        FullCommand = $full.Trim()
        Confidence = $confidence
        Reason = $reason
    }

    if ($LogPath) {
        Write-Log -LogPath $LogPath -Level INFO -Component 'Get-RecommendedInstallCommand' -Message "Recommendation result: $($result.CommandType) / $($result.Confidence)"
    }

    return $result
}
