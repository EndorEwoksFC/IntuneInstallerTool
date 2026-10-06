function New-InstallDirectorySnapshot {
    [CmdletBinding()]
    param ([Parameter(Mandatory)][string[]]$InstallPaths,[Parameter(Mandatory)][string]$SnapshotLabel,[Parameter(Mandatory)][string]$OutputFilePath,[bool]$TopLevelOnly=$true,[string]$LogPath)
    if ($LogPath) { Write-Log -LogPath $LogPath -Level INFO -Component 'New-InstallDirectorySnapshot' -Message "Starting install directory snapshot: $SnapshotLabel" }
    try {
        $roots=foreach($path in $InstallPaths){ if ($LogPath) { Write-Log -LogPath $LogPath -Level INFO -Component 'New-InstallDirectorySnapshot' -Message "Reading path: $path" }; if (-not (Test-Path -Path $path)) { throw "Install directory path was not found: $path" }; $items=@(Get-ChildItem -Path $path -Force -ErrorAction Stop); $entries=foreach($item in $items){[pscustomobject]@{Name=$item.Name;FullPath=$item.FullName;ItemType=$(if($item.PSIsContainer){'Directory'}else{'File'});CreationTime=$item.CreationTime;LastWriteTime=$item.LastWriteTime}}; [pscustomobject]@{RootPath=$path;EntryCount=@($entries).Count;Entries=@($entries);Success=$true} }
        $snapshot=[pscustomobject]@{SnapshotLabel=$SnapshotLabel;OutputFile=$OutputFilePath;RootCount=@($roots).Count;Roots=@($roots);Success=$true}
        [System.IO.File]::WriteAllText($OutputFilePath,($snapshot|ConvertTo-Json -Depth 6),[System.Text.UTF8Encoding]::new($false))
        if ($LogPath) { foreach ($root in $roots) { Write-Log -LogPath $LogPath -Level INFO -Component 'New-InstallDirectorySnapshot' -Message "Collected $($root.EntryCount) top-level entries from $($root.RootPath)" }; Write-Log -LogPath $LogPath -Level INFO -Component 'New-InstallDirectorySnapshot' -Message "Wrote install directory snapshot to $OutputFilePath" }
        return $snapshot
    } catch { if ($LogPath) { Write-Log -LogPath $LogPath -Level ERROR -Component 'New-InstallDirectorySnapshot' -Message "Install directory snapshot failed for $SnapshotLabel" -Exception $_ }; throw }
}
