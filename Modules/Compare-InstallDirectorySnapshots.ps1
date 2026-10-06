function Compare-InstallDirectorySnapshots {

  [CmdletBinding()]

  param ([Parameter(Mandatory)]
    [object]$PreSnapshot,

    [Parameter(Mandatory)]
    [object]$PostSnapshot,

    [Parameter(Mandatory)]
    [string]$OutputFilePath,

    [string]$LogPath)

  if ($LogPath) {
    Write-Log -LogPath $LogPath -Level INFO -Component 'Compare-InstallDirectorySnapshots' -Message 'Starting install directory snapshot comparison'
  }

  try {
    $pre=@{}; foreach($root in $PreSnapshot.Roots) { foreach($e in $root.Entries) { $pre[$root.RootPath + '|' + $e.FullPath]=[pscustomobject]@{RootPath=$root.RootPath;Name=$e.Name;FullPath=$e.FullPath;ItemType=$e.ItemType;CreationTime=$e.CreationTime;LastWriteTime=$e.LastWriteTime} } }
    $post=@{}; foreach($root in $PostSnapshot.Roots) { foreach($e in $root.Entries) { $post[$root.RootPath + '|' + $e.FullPath]=[pscustomobject]@{RootPath=$root.RootPath;Name=$e.Name;FullPath=$e.FullPath;ItemType=$e.ItemType;CreationTime=$e.CreationTime;LastWriteTime=$e.LastWriteTime} } }
    $added=@($post.Keys | Where-Object { -not $pre.ContainsKey($_) } | ForEach-Object { $post[$_] })
    $removed=@($pre.Keys | Where-Object { -not $post.ContainsKey($_) } | ForEach-Object { $pre[$_] })
    $result=[pscustomobject]@{ Added=$added; Removed=$removed; Changed=@(); OutputFile=$OutputFilePath; Success=$true }
    [System.IO.File]::WriteAllText($OutputFilePath,($result|ConvertTo-Json -Depth 8),[System.Text.UTF8Encoding]::new($false))

    if ($LogPath) {
      Write-Log -LogPath $LogPath -Level INFO -Component 'Compare-InstallDirectorySnapshots' -Message "Added entries found: $($added.Count)"
      Write-Log -LogPath $LogPath -Level INFO -Component 'Compare-InstallDirectorySnapshots' -Message "Wrote comparison file to $OutputFilePath"
    }
    return $result
  }

  catch {
    if ($LogPath) { Write-Log -LogPath $LogPath -Level ERROR -Component 'Compare-InstallDirectorySnapshots' -Message 'Install directory comparison failed' -Exception $_ }; throw
  }
}
