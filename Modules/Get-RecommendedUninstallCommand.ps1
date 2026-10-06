function Get-RecommendedUninstallCommand {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]$RegistryEntry,

        [string]$LogPath
    )

    if (-not $RegistryEntry) {
        throw 'RegistryEntry was not provided.'
    }

    $quiet = [string]$RegistryEntry.QuietUninstallString
    $normal = [string]$RegistryEntry.UninstallString

    function Convert-UninstallCommandPath {
        param (
            [Parameter(Mandatory)]
            [string]$Command
        )

        $updated = $Command.Trim()

        if ($updated.StartsWith('"')) {
            return $updated
        }

        if ($updated -match '^(?<path>.+?\.exe)(?<arguments>\s.*)?$') {
            $exePath = $matches.path
            $arguments = $matches.arguments

            if ($exePath.Contains(' ')) {
                return '"' + $exePath + '"' + $arguments
            }
        }

        return $updated
    }

    function Convert-MsiUninstallString {
        param (
            [Parameter(Mandatory)]
            [string]$Command
        )

        $updated = Convert-UninstallCommandPath -Command $Command
        $wasModified = ($updated -ne $Command.Trim())
        $reason = if ($wasModified) { 'Quoted executable path because it contains spaces.' } else { '' }

        if ($updated -match '(?i)msiexec') {
            $original = $updated
            $updated = [regex]::Replace($updated, '(?i)\bmsiexec(\.exe)?\b', 'msiexec.exe')
            $updated = [regex]::Replace($updated, '(?i)(\s|^)/i(?=\s|\{|$)', '$1/X')

            if ($updated -notmatch '(?i)\s/q[nb]?\b') {
                $updated = $updated.TrimEnd() + ' /qn'
            }

            if ($updated -ne $original) {
                $wasModified = $true
                $reason = if ($wasModified -and $updated -ne $original) { 'Quoted executable path and converted MSI /I to /X with /qn for silent uninstall.' } else { 'Converted MSI /I to /X and appended /qn for silent uninstall.' }
            }
        }

        return [pscustomobject]@{
            RecommendedCommand = $updated
            WasModified = $wasModified
            ModificationReason = $reason
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($quiet)) {
        $converted = Convert-MsiUninstallString -Command $quiet

        if ($LogPath) {
            Write-Log -LogPath $LogPath -Level INFO -Component 'Get-RecommendedUninstallCommand' -Message ("Using QuietUninstallString from selected registry entry: {0}" -f $RegistryEntry.RegistryPath)
            Write-Log -LogPath $LogPath -Level INFO -Component 'Get-RecommendedUninstallCommand' -Message ("Recommended uninstall command: {0}" -f $converted.RecommendedCommand)
        }

        return [pscustomobject]@{
            Source = 'QuietUninstallString'
            DetectedCommand = $quiet
            RecommendedCommand = $converted.RecommendedCommand
            WasModified = $converted.WasModified
            ModificationReason = $converted.ModificationReason
            Success = $true
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($normal)) {
        $converted = Convert-MsiUninstallString -Command $normal

        if ($LogPath) {
            Write-Log -LogPath $LogPath -Level INFO -Component 'Get-RecommendedUninstallCommand' -Message ("Using UninstallString from selected registry entry: {0}" -f $RegistryEntry.RegistryPath)
            Write-Log -LogPath $LogPath -Level INFO -Component 'Get-RecommendedUninstallCommand' -Message ("Recommended uninstall command: {0}" -f $converted.RecommendedCommand)
        }

        return [pscustomobject]@{
            Source = 'UninstallString'
            DetectedCommand = $normal
            RecommendedCommand = $converted.RecommendedCommand
            WasModified = $converted.WasModified
            ModificationReason = $converted.ModificationReason
            Success = $true
        }
    }

    if ($LogPath) {
        Write-Log -LogPath $LogPath -Level WARN -Component 'Get-RecommendedUninstallCommand' -Message ("No uninstall string was found in selected registry entry: {0}" -f $RegistryEntry.RegistryPath)
    }

    return [pscustomobject]@{
        Source = ''
        DetectedCommand = ''
        RecommendedCommand = ''
        WasModified = $false
        ModificationReason = ''
        Success = $false
    }
}
