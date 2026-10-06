function Read-Config {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$ConfigPath
    )

    if (-not (Test-Path -Path $ConfigPath)) {
        throw "Config file was not found: $ConfigPath"
    }

    try {
        $config = Get-Content -Path $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw "Failed to parse config file: $ConfigPath. $($_.Exception.Message)"
    }

    $requiredSections = @('logging', 'paths', 'installerDiscovery', 'registrySnapshot', 'installDirectorySnapshot')

    foreach ($section in $requiredSections) {
        if (-not $config.PSObject.Properties.Name.Contains($section)) {
            throw "Missing required config section: $section"
        }
    }

    $requiredPathKeys = @('outputRoot', 'metadataPath', 'detectionMethodPath', 'modulesRoot')

    foreach ($key in $requiredPathKeys) {
        if (-not $config.paths.PSObject.Properties.Name.Contains($key)) {
            throw "Missing required config paths key: $key"
        }
    }

    if (-not $config.logging.PSObject.Properties.Name.Contains('logPath')) {
        throw 'Missing required config logging key: logPath'
    }

    return $config
}
