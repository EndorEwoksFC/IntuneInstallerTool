function Invoke-InstallTest {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]$Installer,

        [Parameter(Mandatory)]
        [object]$RecommendedCommand,

        [Parameter(Mandatory)]
        [string]$LogPath
    )

    Write-Log -LogPath $LogPath -Level INFO -Component 'Invoke-InstallTest' -Message ("Starting install test for {0}" -f $Installer.Name)

    $attempt = 0

    while ($true) {
        $hasRecommendation = ($RecommendedCommand.CommandType -ne 'None' -and -not [string]::IsNullOrWhiteSpace($RecommendedCommand.FullCommand))

        if ($Installer.Extension -eq '.exe') {
            $choice = Show-Menu -Prompt 'Choose how to continue:' -Options @(
                'Create an .ISS file',
                'Enter custom install parameters'
            ) -LogPath $LogPath

            $mode = $choice.SelectedIndex
        }
        elseif ($hasRecommendation) {
            $choice = Show-Menu -Prompt 'Choose how to continue:' -Options @(
                'Use the suggested install string',
                'Enter custom install parameters'
            ) -LogPath $LogPath

            $mode = $choice.SelectedIndex
        }
        else {
            Write-Host 'No reliable silent install command was detected automatically.'
            $mode = 2
        }

        if ($Installer.Extension -eq '.exe' -and $mode -eq 1) {
            $scriptRoot = (Get-Location).Path
            $issFolder = Join-Path -Path $scriptRoot -ChildPath 'IntuneWin'
            $issPath = Join-Path -Path $issFolder -ChildPath 'Setup.iss'
            $issLogPath = Join-Path -Path $issFolder -ChildPath 'Install.log'

            try {
                $issResult = New-IssResponseFile -ExePath $Installer.FullPath -IssFilePath $issPath -LogFilePath $issLogPath -LogPath $LogPath -Mode 'Install'
                Write-Log -LogPath $LogPath -Level INFO -Component 'Invoke-InstallTest' -Message ("ISS file created for install: {0}" -f $issPath)

                while ($true) {
                    <#
                    Write-Host 'Testing recorded install string...'
                    Write-Host $issResult.SilentCommand
                    Write-Host ''
                    #>
                    try {
                        $psi=New-Object System.Diagnostics.ProcessStartInfo
                        $psi.FileName='cmd.exe';$psi.Arguments='/c ' + $issResult.SilentCommand;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
                        $proc=New-Object System.Diagnostics.Process;$proc.StartInfo=$psi;$null=$proc.Start();$proc.WaitForExit();$playExit=$proc.ExitCode
                        Write-Log -LogPath $LogPath -Level INFO -Component 'Invoke-InstallTest' -Message ("ISS install playback exit code: {0}" -f $playExit)
                    } catch { $playExit=-1;Write-Log -LogPath $LogPath -Level ERROR -Component 'Invoke-InstallTest' -Message 'ISS install playback failed to start' -Exception $_ }
                    cls
                    $ok=Read-YesNo -Prompt 'Was the install successful?' -LogPath $LogPath
                    cls
                    if($ok){return [pscustomobject]@{Success=$true;ConfirmedInstallCommand=$issResult.SilentCommand;AttemptCount=1;ExitCode=$playExit;UsedIssRecording=$true;IssSilentCommand=$issResult.SilentCommand;InstallMethod='ISSPlayback'}}
                    $fallback=Show-Menu -Prompt 'Choose how to continue:' -Options @('Retry ISS install playback','Enter custom install parameters') -LogPath $LogPath
                    if($fallback.SelectedIndex -eq 1){continue}
                    break
                }
            }
            catch {
                Write-Host 'The .ISS file could not be created.'
                Write-Host 'This installer may not support InstallShield response files, or the recording process did not complete successfully.'
                Write-Host ''
                Write-Host 'Please choose another install option.'
                Write-Log -LogPath $LogPath -Level WARN -Component 'Invoke-InstallTest' -Message 'ISS creation failed for installer; returning user to install option selection'
                continue
            }
        }
        elseif ($mode -eq 1 -and $hasRecommendation -and $Installer.Extension -ne '.exe') {
            $command = $RecommendedCommand.FullCommand
            Write-Log -LogPath $LogPath -Level INFO -Component 'Invoke-InstallTest' -Message 'User selected suggested install string'
        }
        else {
            Write-Host 'Enter only the additional install parameters.'
            Write-Host ''
            Write-Host 'Do not enter the installer path or file name, your custom argument will automatically be appended.'
            Write-Host ''
            Write-Host ''

            do {
                $custom = Read-Host 'Custom argument'

                if ([string]::IsNullOrWhiteSpace($custom)) {
                    Write-Host 'No text was entered. Please enter the additional install parameters.'
                }
            }
            while ([string]::IsNullOrWhiteSpace($custom))

            Write-Log -LogPath $LogPath -Level INFO -Component 'Invoke-InstallTest' -Message ("User entered custom install parameters: {0}" -f $custom)

            switch ($Installer.Extension) {
                '.msi' {
                    $command = 'msiexec.exe /i "' + $Installer.FullPath + '" ' + $custom
                }
                '.ps1' {
                    $command = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + $Installer.FullPath + '" ' + $custom
                }
                default {
                    $command = '"' + $Installer.FullPath + '" ' + $custom
                }
            }
        }

        while ($true) {
            Write-Host ''
            Write-Host 'Install command to run:'
            Write-Host ''
            Write-Host $command
            Write-Host ''

            $confirm = Show-Menu -Prompt 'Choose how to continue:' -Options @(
                'Proceed with this install command',
                'Go back and edit install parameters'
            ) -LogPath $LogPath

            if ($confirm.SelectedIndex -eq 2) {
                break
            }

            $attempt += 1
            Write-Log -LogPath $LogPath -Level INFO -Component 'Invoke-InstallTest' -Message ("Attempt {0} command: {1}" -f $attempt, $command)

            Write-Host 'Attempting installation...'

            try {
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = 'cmd.exe'
                $psi.Arguments = '/c ' + $command
                $psi.UseShellExecute = $false
                $psi.CreateNoWindow = $true

                $proc = New-Object System.Diagnostics.Process
                $proc.StartInfo = $psi
                $null = $proc.Start()
                $proc.WaitForExit()
                $exitCode = $proc.ExitCode

                Write-Host ('Install process finished with exit code: {0}' -f $exitCode)
                Write-Log -LogPath $LogPath -Level INFO -Component 'Invoke-InstallTest' -Message ("Attempt {0} exit code: {1}" -f $attempt, $exitCode)
            }
            catch {
                Write-Host 'The command could not be started. Review the log for details.'
                Write-Log -LogPath $LogPath -Level ERROR -Component 'Invoke-InstallTest' -Message ("Attempt {0} command could not be started" -f $attempt) -Exception $_
                break
            }

            cls
            $ok = Read-YesNo -Prompt 'Was the install successful?' -LogPath $LogPath

            if ($ok) {
                <#
                Write-Host 'Install confirmed.'
                #>
            
                Write-Log -LogPath $LogPath -Level INFO -Component 'Invoke-InstallTest' -Message ("Attempt {0} confirmed successful by user" -f $attempt)

                return [pscustomobject]@{
                    Success = $true
                    ConfirmedInstallCommand = $command
                    AttemptCount = $attempt
                    ExitCode = $exitCode
                    UsedIssRecording = $false
                    IssSilentCommand = ''
                    InstallMethod = 'Custom'
                }
            }

            <#
            Write-Host 'Install not confirmed.'
            Write-Host 'Please choose another install option.'
            #>

            Write-Log -LogPath $LogPath -Level WARN -Component 'Invoke-InstallTest' -Message ("Attempt {0} was not confirmed successful by user" -f $attempt)
            break
        }
    }
}
