function Get-InstallerCandidates {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$SearchRoot,

        [Parameter(Mandatory)]
        [string[]]$Extensions,

        [Parameter(Mandatory)]
        [string[]]$ExcludedFileNames,

        [Parameter(Mandatory)]
        [string[]]$ExcludedDirectories,

        [string]$LogPath
    )

    if ($LogPath) {
        Write-Log -LogPath $LogPath -Level INFO -Component 'Get-InstallerCandidates' -Message "Starting installer discovery under $SearchRoot"
    }

    if (-not (Test-Path -LiteralPath $SearchRoot)) {
        throw "Search root was not found: $SearchRoot"
    }

    $rootFull = [System.IO.Path]::GetFullPath($SearchRoot).TrimEnd('\\')
    $excludedRoots = @(
        $ExcludedDirectories |
            ForEach-Object {
                [System.IO.Path]::GetFullPath((Join-Path $SearchRoot $_)).TrimEnd('\\')
            }
    )
    $exNames = @($ExcludedFileNames | ForEach-Object { $_.ToLowerInvariant() })
    $allFiles = Get-ChildItem -LiteralPath $SearchRoot -File -Recurse -ErrorAction Stop

    $candidates = foreach ($file in $allFiles) {
        $ext = $file.Extension.ToLowerInvariant()

        if ($Extensions -notcontains $ext) {
            continue
        }

        if ($exNames -contains $file.Name.ToLowerInvariant()) {
            continue
        }

        $full = [System.IO.Path]::GetFullPath($file.FullName).TrimEnd('\\')
        $parentDir = [System.IO.Path]::GetFullPath($file.DirectoryName).TrimEnd('\\')
        $skip = $false

        foreach ($excluded in $excludedRoots) {
            if ($parentDir.Equals($excluded, [System.StringComparison]::OrdinalIgnoreCase) -or
                $parentDir.StartsWith($excluded + '\\', [System.StringComparison]::OrdinalIgnoreCase)) {
                $skip = $true
                break
            }
        }

        if ($skip) {
            continue
        }

        $rel = '.' + $full.Substring($rootFull.Length)

        [pscustomobject]@{
            Name = $file.Name
            FullPath = $full
            RelativePath = $rel
            Directory = $file.DirectoryName
            Extension = $ext
            SizeBytes = $file.Length
            LastWriteTime = $file.LastWriteTime
            TypeCategory = switch ($ext) {
                '.exe' { 'Executable' }
                '.msi' { 'WindowsInstaller' }
                '.msix' { 'MSIX' }
                '.bat' { 'Batch' }
                '.cmd' { 'Batch' }
                '.ps1' { 'PowerShell' }
                default { 'Other' }
            }
        }
    }

    $sorted = @($candidates | Sort-Object FullPath)

    if ($LogPath) {
        Write-Log -LogPath $LogPath -Level INFO -Component 'Get-InstallerCandidates' -Message "Excluded file names: $($ExcludedFileNames -join ', ')"
        Write-Log -LogPath $LogPath -Level INFO -Component 'Get-InstallerCandidates' -Message "Excluded directories: $($ExcludedDirectories -join ', ')"
        Write-Log -LogPath $LogPath -Level INFO -Component 'Get-InstallerCandidates' -Message "Found $($sorted.Count) installer candidates"

        foreach ($c in $sorted) {
            Write-Log -LogPath $LogPath -Level INFO -Component 'Get-InstallerCandidates' -Message "Candidate: $($c.FullPath)"
        }
    }

    return $sorted
}
