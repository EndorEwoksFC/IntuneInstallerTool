function Compare-RegistrySnapshots {

  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [object]$PreNativeSnapshot,

    [Parameter(Mandatory)]
    [object]$PostNativeSnapshot,

    [Parameter(Mandatory)]
    [object]$PreWowSnapshot,

    [Parameter(Mandatory)]
    [object]$PostWowSnapshot,

    [Parameter(Mandatory)]
    [string]$OutputFilePath,

    [string]$LogPath
  )

  if ($LogPath) { Write-Log -LogPath $LogPath -Level INFO -Component 'Compare-RegistrySnapshots' -Message 'Starting registry snapshot comparison' }
  try {
    $preNativeMap=@{}; foreach($e in $PreNativeSnapshot.Entries) { $preNativeMap[$e.RegistryPath]=$e }
    $postNativeMap=@{}; foreach($e in $PostNativeSnapshot.Entries) { $postNativeMap[$e.RegistryPath]=$e }
    $preWowMap=@{}; foreach($e in $PreWowSnapshot.Entries) { $preWowMap[$e.RegistryPath]=$e }
    $postWowMap=@{}; foreach($e in $PostWowSnapshot.Entries) { $postWowMap[$e.RegistryPath]=$e }
    $nativeAdded=@($postNativeMap.Keys | Where-Object { -not $preNativeMap.ContainsKey($_) } | ForEach-Object { $postNativeMap[$_] })
    $nativeRemoved=@($preNativeMap.Keys | Where-Object { -not $postNativeMap.ContainsKey($_) } | ForEach-Object { $preNativeMap[$_] })
    $wowAdded=@($postWowMap.Keys | Where-Object { -not $preWowMap.ContainsKey($_) } | ForEach-Object { $postWowMap[$_] })
    $wowRemoved=@($preWowMap.Keys | Where-Object { -not $postWowMap.ContainsKey($_) } | ForEach-Object { $preWowMap[$_] })
    $result=[pscustomobject]@{ Native=[pscustomobject]@{Added=$nativeAdded;Removed=$nativeRemoved;Changed=@()}; Wow6432Node=[pscustomobject]@{Added=$wowAdded;Removed=$wowRemoved;Changed=@()}; OutputFile=$OutputFilePath; Success=$true }
    [System.IO.File]::WriteAllText($OutputFilePath,($result|ConvertTo-Json -Depth 8),[System.Text.UTF8Encoding]::new($false))
    if ($LogPath) { Write-Log -LogPath $LogPath -Level INFO -Component 'Compare-RegistrySnapshots' -Message "Native added entries: $($nativeAdded.Count)"; Write-Log -LogPath $LogPath -Level INFO -Component 'Compare-RegistrySnapshots' -Message "WOW6432Node added entries: $($wowAdded.Count)"; Write-Log -LogPath $LogPath -Level INFO -Component 'Compare-RegistrySnapshots' -Message "Wrote comparison file to $OutputFilePath" }
    return $result
  }
  catch {
    if ($LogPath) { Write-Log -LogPath $LogPath -Level ERROR -Component 'Compare-RegistrySnapshots' -Message 'Registry comparison failed' -Exception $_ }; throw
  }
}
