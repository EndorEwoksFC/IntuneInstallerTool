function New-IssResponseFile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$ExePath,

        [Parameter(Mandatory)]
        [string]$IssFilePath,

        [Parameter(Mandatory)]
        [string]$LogFilePath,

        [Parameter(Mandatory)]
        [string]$LogPath,

        [Parameter(Mandatory)]
        [string]$Mode
    )

    try {
        $issFolder = Split-Path -Path $IssFilePath -Parent
        $workingFolder = Split-Path -Path $ExePath -Parent

        if (-not (Test-Path -Path $issFolder)) {
            New-Item -Path $issFolder -ItemType Directory -Force | Out-Null
            Write-Log -LogPath $LogPath -Level INFO -Component 'New-IssResponseFile' -Message ("Created ISS folder: {0}" -f $issFolder)
        }

        if (-not (Test-Path -Path $ExePath)) {
            throw "Executable was not found: $ExePath"
        }

        if (Test-Path -Path $IssFilePath) {
            Remove-Item -Path $IssFilePath -Force -ErrorAction SilentlyContinue
        }

        if (Test-Path -Path $LogFilePath) {
            Remove-Item -Path $LogFilePath -Force -ErrorAction SilentlyContinue
        }

        $arguments = '/r /f1"' + $IssFilePath + '" /f2"' + $LogFilePath + '"'

        Write-Log -LogPath $LogPath -Level INFO -Component 'New-IssResponseFile' -Message ("Starting ISS record executable: {0}" -f $ExePath)
        Write-Log -LogPath $LogPath -Level INFO -Component 'New-IssResponseFile' -Message ("Arguments: {0}" -f $arguments)
        Write-Log -LogPath $LogPath -Level INFO -Component 'New-IssResponseFile' -Message ("Working folder: {0}" -f $workingFolder)

        if ($Mode -eq 'Install') {
            Write-Host 'The installer will now open in record mode, please continue through installation normally.'
            Write-Host 'Setup.iss will be created upon successful installation.'
            Write-Host ''
        }
        elseif ($Mode -eq 'Uninstall') {
            cls
            Write-Host 'The uninstaller will now open in record mode, please continue through uninstallation normally.'
            Write-Host 'Uninstall.iss will be created upon successful uninstallation.'
            Write-Host ''
        }

        $proc = Start-Process `
            -FilePath $ExePath `
            -ArgumentList $arguments `
            -WorkingDirectory $workingFolder `
            -Wait `
            -PassThru `
            -WindowStyle Normal `
            -ErrorAction Stop

        $exitCode = $proc.ExitCode

        Write-Log -LogPath $LogPath -Level INFO -Component 'New-IssResponseFile' -Message ("ISS record process finished with exit code: {0}" -f $exitCode)

        $issCreated = $false
        for ($i = 0; $i -lt 30; $i++) {
            if (Test-Path -Path $IssFilePath) {
                $issCreated = $true
                break
            }

            Start-Sleep -Seconds 1
        }

        if (-not $issCreated) {
            throw "ISS file was not created: $IssFilePath"
        }

        return [pscustomobject]@{
            Success = $true
            ExePath = $ExePath
            IssFilePath = $IssFilePath
            LogFilePath = $LogFilePath
            ExitCode = $exitCode
            SilentCommand = '"' + $ExePath + '" /s /SMS /f1"' + $IssFilePath + '" /f2"' + $LogFilePath + '"'
        }
    }
    catch {
        Write-Log -LogPath $LogPath -Level ERROR -Component 'New-IssResponseFile' -Message 'Failed to create ISS response file' -Exception $_
        throw
    }
}