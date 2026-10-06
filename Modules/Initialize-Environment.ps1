function Initialize-Environment {
    [CmdletBinding()]
    param ([Parameter(Mandatory)][string]$ScriptRoot)
    $configPath=Join-Path -Path $ScriptRoot -ChildPath 'Config\ToolConfig.json'
    $modulesPath=Join-Path -Path $ScriptRoot -ChildPath 'Modules'
    $outputPath=Join-Path -Path $ScriptRoot -ChildPath 'Output'
    $logPath=Join-Path -Path $ScriptRoot -ChildPath 'Installer.log'
    $metadataPath=Join-Path -Path $ScriptRoot -ChildPath 'InstallerMetadata.txt'
    $detectionMethodPath=Join-Path -Path $ScriptRoot -ChildPath 'DetectionMethod.txt'
    if (-not (Test-Path -Path $outputPath)) { New-Item -Path $outputPath -ItemType Directory -Force | Out-Null }
    [pscustomobject]@{ ScriptRoot=[System.IO.Path]::GetFullPath($ScriptRoot); ConfigPath=[System.IO.Path]::GetFullPath($configPath); ModulesPath=[System.IO.Path]::GetFullPath($modulesPath); OutputPath=[System.IO.Path]::GetFullPath($outputPath); LogPath=[System.IO.Path]::GetFullPath($logPath); MetadataPath=[System.IO.Path]::GetFullPath($metadataPath); DetectionMethodPath=[System.IO.Path]::GetFullPath($detectionMethodPath); RunId=[guid]::NewGuid().Guid; StartedAt=Get-Date }
}
