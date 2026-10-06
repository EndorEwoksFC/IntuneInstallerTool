function New-IntuneWinPackage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]$Installer,

        [Parameter(Mandatory)]
        [string]$ToolPath,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter(Mandatory)]
        [string]$LogPath
    )

    if (-not (Test-Path -Path $ToolPath)) {
        throw "IntuneWin tool was not found: $ToolPath"
    }

    $setupFolder = $Installer.Directory
    $setupFile = $Installer.Name

    Write-Log -LogPath $LogPath -Level INFO -Component 'New-IntuneWinPackage' -Message ("Starting IntuneWin creation using setup folder '{0}' and setup file '{1}'" -f $setupFolder, $setupFile)

    try {
        $proc = Start-Process -FilePath $ToolPath `
            -ArgumentList @(
                '-c', $setupFolder,
                '-s', $setupFile,
                '-o', $OutputPath,
                '-q'
            ) `
            -Wait `
            -PassThru `
            -WindowStyle Normal `
            -ErrorAction Stop

        $exitCode = $proc.ExitCode

        Write-Log -LogPath $LogPath -Level INFO -Component 'New-IntuneWinPackage' -Message ("IntuneWin creation process finished with exit code: {0}" -f $exitCode)

        return [pscustomobject]@{
            Success = ($exitCode -eq 0)
            ToolPath = $ToolPath
            SetupFolder = $setupFolder
            SetupFile = $setupFile
            OutputFolder = $OutputPath
            ExitCode = $exitCode
        }
    }
    catch {
        Write-Log -LogPath $LogPath -Level ERROR -Component 'New-IntuneWinPackage' -Message 'IntuneWin creation failed' -Exception $_
        throw
    }
}