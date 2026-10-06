function Invoke-UninstallTest {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]$SelectedRegistryEntry,

        [Parameter(Mandatory)]
        [object]$RecommendedUninstallCommand,

        [Parameter(Mandatory)]
        [string]$LogPath,

        [bool]$ForceIssRecording = $false,

        [bool]$AllowIssRecording = $false
    )

    Write-Log -LogPath $LogPath -Level INFO -Component 'Invoke-UninstallTest' -Message ("Starting uninstall test for {0}" -f $SelectedRegistryEntry.RegistryPath)

    $attempt = 0

    while ($true) {
        $canUseIss = $false
        $issMenuShown = $false

        if ($RecommendedUninstallCommand.Success) {
            $recommendedCommandText = [string]$RecommendedUninstallCommand.RecommendedCommand
            $isMsiExec = $recommendedCommandText -match '(?i)(^|\s|")msiexec(\.exe)?(\s|")'
            $hasExe = $recommendedCommandText -match '(?i)\.exe'
            $canUseIss = $hasExe -and -not $isMsiExec
        }

        if ($ForceIssRecording -and $canUseIss) {
            $issMenuShown = $true
            $mode = 1
        }
        elseif ($AllowIssRecording -and $canUseIss) {
            $issMenuShown = $true

            $choice = Show-Menu -Prompt 'Choose how to continue:' -Options @(
                'Create an .ISS file',
                'Enter custom uninstall parameters'
            ) -LogPath $LogPath

            $mode = $choice.SelectedIndex
        }
        elseif ($RecommendedUninstallCommand.Success) {
            cls
            Write-Host 'Detected uninstall string:'
            Write-Host $RecommendedUninstallCommand.DetectedCommand
            Write-Host ''

            if ($RecommendedUninstallCommand.WasModified) {
                Write-Host 'Silent uninstall string (modified from detected):'
                Write-Host $RecommendedUninstallCommand.RecommendedCommand
                Write-Host ''
            }

            $choice = Show-Menu -Prompt 'Choose how to continue:' -Options @(
                'Use detected uninstall string',
                'Append to detected uninstall string',
                'Use a custom uninstall string'
            ) -LogPath $LogPath

            $mode = $choice.SelectedIndex
        }
        else {
            Write-Host 'No uninstall string was detected automatically.'
            Write-Host 'Please enter a custom uninstall string.'
            Write-Host ''
            $mode = 3
        }

        if ($canUseIss -and $mode -eq 1 -and $issMenuShown) {
            $scriptRoot = (Get-Location).Path
            $issFolder = Join-Path -Path $scriptRoot -ChildPath 'IntuneWin'
            $issPath = Join-Path -Path $issFolder -ChildPath 'Uninstall.iss'
            $issLogPath = Join-Path -Path $issFolder -ChildPath 'Uninstall.log'

            $match = [regex]::Match($RecommendedUninstallCommand.RecommendedCommand, '^"?(?<exe>[^\"]+?\.exe)"?(?<rest>.*)$', 'IgnoreCase')

            if (-not $match.Success) {
                Write-Host 'The detected uninstall command is not in a supported EXE format for ISS creation.'
                Write-Host 'Please choose another uninstall option.'
                Write-Host ''
                Write-Log -LogPath $LogPath -Level WARN -Component 'Invoke-UninstallTest' -Message 'ISS creation was requested but EXE path could not be parsed from uninstall command'
                continue
            }

            $exePath = $match.Groups['exe'].Value

            try {
                $issResult = New-IssResponseFile -ExePath $exePath -IssFilePath $issPath -LogFilePath $issLogPath -LogPath $LogPath -Mode 'Uninstall'
                $commandSource = 'Custom'
                Write-Log -LogPath $LogPath -Level INFO -Component 'Invoke-UninstallTest' -Message ("ISS file created for uninstall: {0}" -f $issPath)

                while ($true) {
                    <#
                    Write-Host 'Testing recorded uninstall string...'
                    Write-Host $issResult.SilentCommand
                    Write-Host ''
                    #>
                    try {
                        $psi = New-Object System.Diagnostics.ProcessStartInfo
                        $psi.FileName = 'cmd.exe'
                        $psi.Arguments = '/c ' + $issResult.SilentCommand
                        $psi.UseShellExecute = $false
                        $psi.CreateNoWindow = $true

                        $proc = New-Object System.Diagnostics.Process
                        $proc.StartInfo = $psi
                        $null = $proc.Start()
                        $proc.WaitForExit()
                        $playExit = $proc.ExitCode

                        Write-Log -LogPath $LogPath -Level INFO -Component 'Invoke-UninstallTest' -Message ("ISS uninstall playback exit code: {0}" -f $playExit)
                    }
                    catch {
                        $playExit = -1
                        Write-Log -LogPath $LogPath -Level ERROR -Component 'Invoke-UninstallTest' -Message 'ISS uninstall playback failed to start' -Exception $_
                    }

                    cls
                    $ok = Read-YesNo -Prompt 'Was the uninstall successful?' -LogPath $LogPath

                    if ($ok) {
                        return [pscustomobject]@{
                            Success = $true
                            ConfirmedUninstallCommand = $issResult.SilentCommand
                            UninstallStringSource = $commandSource
                            AttemptCount = 1
                            ExitCode = $playExit
                            UsedIssRecording = $true
                            IssSilentCommand = $issResult.SilentCommand
                            UninstallMethod = 'ISSPlayback'
                        }
                    }

                    cls
                    $fallback = Show-Menu -Prompt 'Choose how to continue:' -Options @(
                        'Retry ISS uninstall playback',
                        'Enter a custom uninstall string'
                    ) -LogPath $LogPath

                    if ($fallback.SelectedIndex -eq 1) {
                        continue
                    }

                    break
                }
            }
            catch {
                Write-Host 'The .ISS file could not be created.'
                Write-Host 'This uninstaller may not support InstallShield response files, or the recording process did not complete successfully.'
                Write-Host ''
                Write-Host 'Please choose another uninstall option.'
                Write-Log -LogPath $LogPath -Level WARN -Component 'Invoke-UninstallTest' -Message 'ISS creation failed for uninstaller; returning user to uninstall option selection'
                continue
            }
        }
        elseif ($mode -eq 1) {
            $command = $RecommendedUninstallCommand.RecommendedCommand
            $commandSource = if ([string]::IsNullOrWhiteSpace($RecommendedUninstallCommand.Source)) {
                'Custom'
            }
            else {
                $RecommendedUninstallCommand.Source
            }

            Write-Log -LogPath $LogPath -Level INFO -Component 'Invoke-UninstallTest' -Message 'User selected detected uninstall string'
        }
        elseif ($mode -eq 2 -and -not $issMenuShown) {
            do {
                Write-Host 'Enter only the additional uninstall parameters.'
                Write-Host ''
                Write-Host 'Do not enter the uninstaller path or file name, your custom argument will automatically be appended.'
                Write-Host ''
                Write-Host ''

                $appendText = Read-Host 'Custom argument'

                if ([string]::IsNullOrWhiteSpace($appendText)) {
                    Write-Host 'No text was entered. Please enter the additional uninstall parameters.'
                    Write-Host ''
                }
            }
            while ([string]::IsNullOrWhiteSpace($appendText))

            $command = ($RecommendedUninstallCommand.RecommendedCommand.TrimEnd() + ' ' + $appendText.Trim())
            $commandSource = if ([string]::IsNullOrWhiteSpace($RecommendedUninstallCommand.Source)) {
                'Custom'
            }
            else {
                $RecommendedUninstallCommand.Source
            }

            Write-Log -LogPath $LogPath -Level INFO -Component 'Invoke-UninstallTest' -Message ("User appended text to detected uninstall string: {0}" -f $appendText)
        }
        else {
            if ($RecommendedUninstallCommand.Success) {
                Write-Host 'Detected uninstall string:'
                Write-Host $RecommendedUninstallCommand.DetectedCommand
                Write-Host ''

                if ($RecommendedUninstallCommand.WasModified) {
                    Write-Host 'Silent uninstall string (modified from detected):'
                    Write-Host $RecommendedUninstallCommand.RecommendedCommand
                    Write-Host ''
                }
            }

            do {
                Show-Header -Title 'Enter the full uninstall command to run'
                Write-Host ''

                $command = Read-Host 'Command'

                if ([string]::IsNullOrWhiteSpace($command)) {
                    Write-Host 'No command was entered. Please enter a full uninstall command.'
                    Write-Host ''
                }
            }
            while ([string]::IsNullOrWhiteSpace($command))

            $commandSource = 'Custom'
            Write-Log -LogPath $LogPath -Level INFO -Component 'Invoke-UninstallTest' -Message ("User entered custom uninstall command: {0}" -f $command)
        }

        while ($true) {
            cls
            Write-Host 'Uninstall command to run:'
            Write-Host ''
            Write-Host $command
            Write-Host ''

            $confirm = Show-Menu -Prompt 'Choose how to continue:' -Options @(
                'Proceed with this uninstall command',
                'Go back and edit uninstall command'
            ) -LogPath $LogPath

            if ($confirm.SelectedIndex -eq 2) {
                break
            }

            $attempt += 1
            Write-Log -LogPath $LogPath -Level INFO -Component 'Invoke-UninstallTest' -Message ("Attempt {0} command: {1}" -f $attempt, $command)

            Write-Host 'Attempting uninstallation...'

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
                Write-Log -LogPath $LogPath -Level INFO -Component 'Invoke-UninstallTest' -Message ("Attempt {0} exit code: {1}" -f $attempt, $exitCode)
            }
            catch {
                Write-Host 'The command could not be started. Review the log for details.'
                Write-Log -LogPath $LogPath -Level ERROR -Component 'Invoke-UninstallTest' -Message ("Attempt {0} command could not be started" -f $attempt) -Exception $_
                break
            }

            cls
            $ok = Read-YesNo -Prompt 'Was the uninstall successful?' -LogPath $LogPath

            if ($ok) {
                <#
                Write-Host 'Uninstall confirmed.'
                #>
                Write-Log -LogPath $LogPath -Level INFO -Component 'Invoke-UninstallTest' -Message ("Attempt {0} confirmed successful by user" -f $attempt)

                return [pscustomobject]@{
                    Success = $true
                    ConfirmedUninstallCommand = $command
                    UninstallStringSource = $commandSource
                    AttemptCount = $attempt
                    ExitCode = $exitCode
                    UsedIssRecording = $false
                    IssSilentCommand = ''
                    UninstallMethod = 'Custom'
                }
            }

            <#
            Write-Host 'Uninstall not confirmed.'
            Write-Host 'Please choose another uninstall option.'
            #>

            Write-Log -LogPath $LogPath -Level WARN -Component 'Invoke-UninstallTest' -Message ("Attempt {0} was not confirmed successful by user" -f $attempt)
            break
        }
    }
}
