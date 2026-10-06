$ErrorActionPreference = 'Stop'

Write-Host 'Installer Test Tool'
Write-Host ''
Write-Host 'Initializing...'

# ========================================================
# Initialization
# ========================================================

$packageRoot = 'C:\PackageTest'

if (-not (Test-Path -LiteralPath $packageRoot -PathType Container)) {
  Write-Warning "Package path was not found; skipping file unblocking: $packageRoot"
}
else {
  Get-ChildItem `
    -LiteralPath $packageRoot `
    -File `
    -Recurse `
    -Force `
    -ErrorAction SilentlyContinue |
    Unblock-File `
    -ErrorAction SilentlyContinue
}

$scriptRoot = Split-Path -Path $MyInvocation.MyCommand.Path -Parent

$bootstrapModules = @(
  'Write-Log.ps1',
  'Initialize-Environment.ps1',
  'Read-Config.ps1',
  'Initialize-Logging.ps1',
  'Show-Header.ps1'
)

foreach ($moduleName in $bootstrapModules) {
  $modulePath = Join-Path -Path $scriptRoot -ChildPath (Join-Path 'Modules' $moduleName)

  if (-not (Test-Path -Path $modulePath)) {
    Write-Host "Failed to load module: $moduleName"
    Write-Host 'Review the log for details.'
    exit 1
  }

  . $modulePath
}

try {
  $runtime = Initialize-Environment -ScriptRoot $scriptRoot
  $config = Read-Config -ConfigPath $runtime.ConfigPath

  $runtime.ModulesPath = [System.IO.Path]::GetFullPath(
    (Join-Path $scriptRoot $config.paths.modulesRoot)
  )

  $runtime.OutputPath = [System.IO.Path]::GetFullPath(
    (Join-Path $scriptRoot $config.paths.outputRoot)
  )

  $runtime.LogPath = [System.IO.Path]::GetFullPath(
    (Join-Path $scriptRoot $config.logging.logPath)
  )

  $runtime.MetadataPath = [System.IO.Path]::GetFullPath(
    (Join-Path $scriptRoot $config.paths.metadataPath)
  )

  $runtime.DetectionMethodPath = [System.IO.Path]::GetFullPath(
    (Join-Path $scriptRoot $config.paths.detectionMethodPath)
  )

  Initialize-Logging -LogPath $runtime.LogPath

  Write-Log -LogPath $runtime.LogPath -Level INFO -Component 'Launch' -Message 'Startup initiated'
  Write-Log -LogPath $runtime.LogPath -Level INFO -Component 'Launch' -Message "Script root resolved: $scriptRoot"
  Write-Log -LogPath $runtime.LogPath -Level INFO -Component 'Launch' -Message 'Runtime initialized'
  Write-Log -LogPath $runtime.LogPath -Level INFO -Component 'Launch' -Message 'Configuration loaded successfully'

  cls
  Show-Header -Title 'Loading modules'

  foreach ($moduleName in $bootstrapModules) {
    Write-Host "Loaded: $moduleName (bootstrap)"
    Write-Log -LogPath $runtime.LogPath -Level INFO -Component 'Launch' -Message "Bootstrap module loaded: $moduleName"
  }

  $moduleFiles = Get-ChildItem `
    -Path $runtime.ModulesPath `
    -Filter '*.ps1' `
    -File |
    Sort-Object Name |
    Where-Object {
    $bootstrapModules -notcontains $_.Name
  }

  foreach ($moduleFile in $moduleFiles) {
    try {
      . $moduleFile.FullName

      Write-Host "Loaded: $($moduleFile.Name)"

      Write-Log `
        -LogPath $runtime.LogPath `
        -Level INFO `
        -Component 'Launch' `
        -Message "Loaded module: $($moduleFile.Name)"

      $expectedFunction = [System.IO.Path]::GetFileNameWithoutExtension(
        $moduleFile.Name
      )

      $loadedFunction = Get-Command `
        -Name $expectedFunction `
        -CommandType Function `
        -ErrorAction SilentlyContinue

      if (-not $loadedFunction) {
        Write-Host "Warning: $($moduleFile.Name) did not define function $expectedFunction"

        Write-Log `
          -LogPath $runtime.LogPath `
          -Level WARN `
          -Component 'Launch' `
          -Message "Module file '$($moduleFile.Name)' was loaded but no matching function '$expectedFunction' was found."
      }
    }
    catch {
      Write-Host "Failed to load module: $($moduleFile.Name)"
      Write-Host 'Review the log for details.'

      Write-Log `
        -LogPath $runtime.LogPath `
        -Level ERROR `
        -Component 'Launch' `
        -Message "Failed to load module: $($moduleFile.Name)" `
        -Exception $_

      exit 1
    }
  }

  # ========================================================
  # Installer Discovery
  # ========================================================

  cls
  Show-Header -Title 'Installer discovery'

  $preNativePath = Join-Path `
    -Path $runtime.OutputPath `
    -ChildPath $config.registrySnapshot.preNativeFile

  $preWowPath = Join-Path `
    -Path $runtime.OutputPath `
    -ChildPath $config.registrySnapshot.preWowFile

  $preDirPath = Join-Path `
    -Path $runtime.OutputPath `
    -ChildPath $config.installDirectorySnapshot.preFile

  $preNative = New-RegistrySnapshot `
    -RegistryPath $config.registrySnapshot.nativePath `
    -SnapshotLabel 'PreInstall' `
    -OutputFilePath $preNativePath `
    -LogPath $runtime.LogPath

  $preWow = New-RegistrySnapshot `
    -RegistryPath $config.registrySnapshot.wow6432Path `
    -SnapshotLabel 'PreInstall' `
    -OutputFilePath $preWowPath `
    -LogPath $runtime.LogPath

  $preDir = New-InstallDirectorySnapshot `
    -InstallPaths $config.installDirectorySnapshot.paths `
    -SnapshotLabel 'PreInstall' `
    -OutputFilePath $preDirPath `
    -TopLevelOnly ([bool]$config.installDirectorySnapshot.topLevelOnly) `
    -LogPath $runtime.LogPath

  $candidates = Get-InstallerCandidates `
    -SearchRoot $runtime.ScriptRoot `
    -Extensions $config.installerDiscovery.extensions `
    -ExcludedFileNames $config.installerDiscovery.excludedFileNames `
    -ExcludedDirectories $config.installerDiscovery.excludedDirectories `
    -LogPath $runtime.LogPath

  if (-not $candidates -or $candidates.Count -eq 0) {
    Write-Host 'No installer files were found, please ensure they are placed at the script''s root location'
    Write-Host 'Supported file types: .exe, .msi, .msix, .bat, .cmd, .ps1'

    Write-Log `
      -LogPath $runtime.LogPath `
      -Level WARN `
      -Component 'Launch' `
      -Message 'No installer candidates were found'

    exit 1
  }

  $selectedInstaller = Select-InstallerCandidate `
    -Candidates $candidates `
    -LogPath $runtime.LogPath

  cls
  Show-Header -Title 'Installer metadata'

  $metadata = Get-InstallerMetadata `
    -Installer $selectedInstaller `
    -MetadataPath $runtime.MetadataPath `
    -LogPath $runtime.LogPath

  $recommended = Get-RecommendedInstallCommand `
    -Installer $selectedInstaller `
    -Metadata $metadata `
    -LogPath $runtime.LogPath

  cls
  Show-Header -Title 'Suggested install command'
  Write-Host ''

  if (
    $recommended.CommandType -eq 'None' -or
    [string]::IsNullOrWhiteSpace($recommended.FullCommand)
  ) {
    Write-Host 'No reliable silent install command was detected automatically.'
    Write-Host 'Please enter your own custom install parameters.'
    Write-Host ''
  }
  else {
    Write-Host $recommended.FullCommand
    Write-Host ''
  }

  $installResult = Invoke-InstallTest `
    -Installer $selectedInstaller `
    -RecommendedCommand $recommended `
    -LogPath $runtime.LogPath

  $postNativePath = Join-Path `
    -Path $runtime.OutputPath `
    -ChildPath $config.registrySnapshot.postNativeFile

  $postWowPath = Join-Path `
    -Path $runtime.OutputPath `
    -ChildPath $config.registrySnapshot.postWowFile

  $postDirPath = Join-Path `
    -Path $runtime.OutputPath `
    -ChildPath $config.installDirectorySnapshot.postFile

  $postNative = New-RegistrySnapshot `
    -RegistryPath $config.registrySnapshot.nativePath `
    -SnapshotLabel 'PostInstall' `
    -OutputFilePath $postNativePath `
    -LogPath $runtime.LogPath

  $postWow = New-RegistrySnapshot `
    -RegistryPath $config.registrySnapshot.wow6432Path `
    -SnapshotLabel 'PostInstall' `
    -OutputFilePath $postWowPath `
    -LogPath $runtime.LogPath

  $postDir = New-InstallDirectorySnapshot `
    -InstallPaths $config.installDirectorySnapshot.paths `
    -SnapshotLabel 'PostInstall' `
    -OutputFilePath $postDirPath `
    -TopLevelOnly ([bool]$config.installDirectorySnapshot.topLevelOnly) `
    -LogPath $runtime.LogPath

  $regComparisonPath = Join-Path `
    -Path $runtime.OutputPath `
    -ChildPath $config.registrySnapshot.comparisonFile

  $dirComparisonPath = Join-Path `
    -Path $runtime.OutputPath `
    -ChildPath $config.installDirectorySnapshot.comparisonFile

  $regComparison = Compare-RegistrySnapshots `
    -PreNativeSnapshot $preNative `
    -PostNativeSnapshot $postNative `
    -PreWowSnapshot $preWow `
    -PostWowSnapshot $postWow `
    -OutputFilePath $regComparisonPath `
    -LogPath $runtime.LogPath

  $dirComparison = Compare-InstallDirectorySnapshots `
    -PreSnapshot $preDir `
    -PostSnapshot $postDir `
    -OutputFilePath $dirComparisonPath `
    -LogPath $runtime.LogPath

  # ============================================================
  # Export application icons
  # ============================================================

  $iconOutputPath = Join-Path `
    -Path $runtime.OutputPath `
    -ChildPath 'Icons'

  try {
    Write-Log `
      -LogPath $runtime.LogPath `
      -Level INFO `
      -Component 'Launch' `
      -Message "Starting application icon extraction from directory comparison: $dirComparisonPath"

    $iconResult = Export-InstalledApplicationIcons `
      -JsonPath $dirComparisonPath `
      -OutputPath $iconOutputPath

    if ($iconResult.Success) {
      Write-Log `
        -LogPath $runtime.LogPath `
        -Level INFO `
        -Component 'Launch' `
        -Message "Application icon extraction completed. EXE/DLL files scanned: $($iconResult.FilesScanned); icon groups exported: $($iconResult.IconsExported); existing ICO files copied: $($iconResult.ExistingIcosCopied)"
    }
    else {
      Write-Log `
        -LogPath $runtime.LogPath `
        -Level WARN `
        -Component 'Launch' `
        -Message 'Application icon extraction completed but no Added directory entries were available.'
    }
  }
  catch {
    Write-Log `
      -LogPath $runtime.LogPath `
      -Level ERROR `
      -Component 'Launch' `
      -Message 'Application icon extraction failed' `
      -Exception $_

    Write-Host ''
    Write-Host 'Warning: Application icon extraction failed.' -ForegroundColor Yellow
    Write-Host 'The uninstall workflow will continue.'
    Write-Host ''
  }

  # ============================================================
  # Determine application name
  # ============================================================

  $applicationName = $metadata.ProductName

  if ([string]::IsNullOrWhiteSpace($applicationName)) {
    $applicationName = [System.IO.Path]::GetFileNameWithoutExtension(
      $selectedInstaller.Name
    )
  }

  Write-Log `
    -LogPath $runtime.LogPath `
    -Level INFO `
    -Component 'Launch' `
    -Message "Application name selected for Intune detection and requirement scripts: $applicationName"

  # ============================================================
  # Create Intune detection script
  # ============================================================

  $detectionOutputPath = Join-Path `
    -Path $runtime.OutputPath `
    -ChildPath 'Detection\Detection.ps1'

  try {
    Write-Log `
      -LogPath $runtime.LogPath `
      -Level INFO `
      -Component 'Launch' `
      -Message "Creating Intune detection script: $detectionOutputPath"

    $detectionResult = Create-IntuneDetectionScript `
      -JsonPath $regComparisonPath `
      -ApplicationName $applicationName `
      -OutputPath $detectionOutputPath

    Write-Log `
      -LogPath $runtime.LogPath `
      -Level INFO `
      -Component 'Launch' `
      -Message "Intune detection script created successfully. Registry candidates: $($detectionResult.CandidateCount)"
  }
  catch {
    Write-Log `
      -LogPath $runtime.LogPath `
      -Level ERROR `
      -Component 'Launch' `
      -Message 'Intune detection script creation failed' `
      -Exception $_

    Write-Host ''
    Write-Host 'Error: Unable to create the Intune detection script.' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ''

    exit 1
  }

  # ============================================================
  # Create Intune requirement script
  # ============================================================

  $requirementOutputPath = Join-Path `
    -Path $runtime.OutputPath `
    -ChildPath 'Requirements\Requirement.ps1'

  try {
    Write-Log `
      -LogPath $runtime.LogPath `
      -Level INFO `
      -Component 'Launch' `
      -Message "Creating Intune requirement script: $requirementOutputPath"

    $requirementResult = Create-IntuneRequirementScript `
      -JsonPath $regComparisonPath `
      -ApplicationName $applicationName `
      -OutputPath $requirementOutputPath

    Write-Log `
      -LogPath $runtime.LogPath `
      -Level INFO `
      -Component 'Launch' `
      -Message "Intune requirement script created successfully. Registry candidates: $($requirementResult.CandidateCount)"
  }
  catch {
    Write-Log `
      -LogPath $runtime.LogPath `
      -Level ERROR `
      -Component 'Launch' `
      -Message 'Intune requirement script creation failed' `
      -Exception $_

    Write-Host ''
    Write-Host 'Error: Unable to create the Intune requirement script.' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ''

    exit 1
  }

  $allUninstallResults = @()

  $currentNativeBaseline = $postNative
  $currentWowBaseline = $postWow

  $remainingCandidates = @(
    Get-NewUninstallEntries `
      -RegistryComparison $regComparison `
      -LogPath $runtime.LogPath
  )

  while ($remainingCandidates.Count -gt 0) {
    $selectedUninstallEntry = Select-UninstallEntry `
      -Candidates $remainingCandidates `
      -LogPath $runtime.LogPath

    $recommendedUninstall = Get-RecommendedUninstallCommand `
      -RegistryEntry $selectedUninstallEntry `
      -LogPath $runtime.LogPath

    $forceIssRecording = $false

    if ($installResult.UsedIssRecording) {
      $forceIssRecording = $true
    }

    $uninstallResult = Invoke-UninstallTest `
      -SelectedRegistryEntry $selectedUninstallEntry `
      -RecommendedUninstallCommand $recommendedUninstall `
      -LogPath $runtime.LogPath `
      -ForceIssRecording $forceIssRecording `
      -AllowIssRecording $installResult.UsedIssRecording

    $allUninstallResults += $uninstallResult

    if (
      $installResult.UsedIssRecording -and
      $uninstallResult.UsedIssRecording
    ) {
      Write-Log `
        -LogPath $runtime.LogPath `
        -Level INFO `
        -Component 'Launch' `
        -Message 'Both ISS recordings completed; starting ISS playback validation'

      while ($true) {
        cls
        Show-Header -Title 'Testing recorded install string'
        Write-Host ''

        $installCommand = $installResult.IssSilentCommand
        $installLogFolder = Join-Path `
          -Path $runtime.ScriptRoot `
          -ChildPath 'IntuneWin'

        $installLogPath = Join-Path `
          -Path $installLogFolder `
          -ChildPath 'Install.log'

        $installIssPath = Join-Path `
          -Path $installLogFolder `
          -ChildPath 'Setup.iss'

                <#
                Write-Host 'Playback command:'
                #>
        Write-Host $installCommand
        Write-Host ''
                <#
                Write-Host "ISS file: $installIssPath"
                Write-Host "Install log: $installLogPath"
                Write-Host ''
                #>

        if (Test-Path -Path $installLogPath) {
          Remove-Item `
            -Path $installLogPath `
            -Force `
            -ErrorAction SilentlyContinue
        }

        try {
          $installCommand = $installResult.IssSilentCommand

          if ($installCommand -match '^\s*"(?<file>[^"]+)"\s*(?<args>.*)$') {
            $playbackFilePath = $matches.file
            $playbackArguments = $matches.args
          }
          elseif ($installCommand -match '^\s*(?<file>\S+)\s*(?<args>.*)$') {
            $playbackFilePath = $matches.file
            $playbackArguments = $matches.args
          }
          else {
            throw "Unable to parse ISS install playback command: $installCommand"
          }

                    <#
                    Write-Host "Executable: $playbackFilePath"
                    Write-Host "Arguments: $playbackArguments"
                    Write-Host ''
                    #>

          if (-not (Test-Path -Path $playbackFilePath)) {
            throw "ISS install executable was not found: $playbackFilePath"
          }

          $psi = New-Object System.Diagnostics.ProcessStartInfo
          $psi.FileName = $playbackFilePath
          $psi.Arguments = $playbackArguments
          $psi.WorkingDirectory = Split-Path -Path $playbackFilePath -Parent
          $psi.UseShellExecute = $false
          $psi.CreateNoWindow = $true

          $proc = New-Object System.Diagnostics.Process
          $proc.StartInfo = $psi
          $null = $proc.Start()

          Write-Host "Playback process started."
          Write-Host "Process ID: $($proc.Id)"

          if (-not $proc.HasExited) {
            $proc.WaitForExit()
          }

          $installPlaybackExitCode = $proc.ExitCode

          Write-Host "ISS install playback exit code: $installPlaybackExitCode"

          Write-Log `
            -LogPath $runtime.LogPath `
            -Level INFO `
            -Component 'Launch' `
            -Message ("ISS install playback exit code: {0}" -f $installPlaybackExitCode)
        }
        catch {
          Write-Host 'ISS install playback command could not be started.'
          Write-Host $_.Exception.Message

          Write-Log `
            -LogPath $runtime.LogPath `
            -Level ERROR `
            -Component 'Launch' `
            -Message 'ISS install playback command could not be started' `
            -Exception $_
        }

        cls
        $installPlaybackOk = Read-YesNo `
          -Prompt 'Was the install successful?' `
          -LogPath $runtime.LogPath

        if ($installPlaybackOk) {
          break
        }

        Write-Host 'Install playback was not confirmed.'
        Write-Host ''

        cls
        $playbackChoice = Show-Menu `
          -Prompt 'Choose how to continue:' `
          -Options @(
          'Retry ISS install playback',
          'Enter custom install parameters'
        ) `
          -LogPath $runtime.LogPath

        if ($playbackChoice.SelectedIndex -eq 1) {
          Write-Log `
            -LogPath $runtime.LogPath `
            -Level WARN `
            -Component 'Launch' `
            -Message 'ISS install playback was not confirmed; retrying ISS playback'

          continue
        }

        do {
          Write-Host 'Enter only the additional install parameters.'
          Write-Host 'Do not enter the installer path or file name, your custom argument will automatically be appended.'
          Write-Host ''

          $customInstallParameters = Read-Host 'Parameters'

          if ([string]::IsNullOrWhiteSpace($customInstallParameters)) {
            Write-Host 'No parameters were entered. Please enter the additional install parameters.'
          }
        }
        while ([string]::IsNullOrWhiteSpace($customInstallParameters))

        $customInstallCommand = switch ($selectedInstaller.Extension) {
          '.msi' {
            'msiexec.exe /i "' + $selectedInstaller.FullPath + '" ' + $customInstallParameters
          }

          '.ps1' {
            'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + $selectedInstaller.FullPath + '" ' + $customInstallParameters
          }

          default {
            '"' + $selectedInstaller.FullPath + '" ' + $customInstallParameters
          }
        }

        Write-Log `
          -LogPath $runtime.LogPath `
          -Level INFO `
          -Component 'Launch' `
          -Message ("User selected custom install fallback: {0}" -f $customInstallCommand)

        try {
          $customPsi = New-Object System.Diagnostics.ProcessStartInfo
          $customPsi.FileName = 'cmd.exe'
          $customPsi.Arguments = '/c ' + $customInstallCommand
          $customPsi.UseShellExecute = $false
          $customPsi.CreateNoWindow = $true

          $customProc = New-Object System.Diagnostics.Process
          $customProc.StartInfo = $customPsi
          $null = $customProc.Start()
          $customProc.WaitForExit()
          $customExitCode = $customProc.ExitCode

          Write-Log `
            -LogPath $runtime.LogPath `
            -Level INFO `
            -Component 'Launch' `
            -Message ("Custom install fallback exit code: {0}" -f $customExitCode)
        }
        catch {
          Write-Host 'The custom install command could not be started. Review the log for details.'

          Write-Log `
            -LogPath $runtime.LogPath `
            -Level ERROR `
            -Component 'Launch' `
            -Message 'Custom install fallback could not be started' `
            -Exception $_

          continue
        }

        cls
        $customInstallConfirmed = Read-YesNo `
          -Prompt 'Was the install successful?' `
          -LogPath $runtime.LogPath

        if ($customInstallConfirmed) {
          $installResult.ConfirmedInstallCommand = $customInstallCommand
          $installResult.InstallMethod = 'Custom'
          $installResult.UsedIssRecording = $false
          $installResult.IssSilentCommand = ''

          Write-Log `
            -LogPath $runtime.LogPath `
            -Level INFO `
            -Component 'Launch' `
            -Message 'Custom install fallback was confirmed successful by user'

          break
        }

        Write-Host 'Custom install fallback was not confirmed.'
        Write-Log `
          -LogPath $runtime.LogPath `
          -Level WARN `
          -Component 'Launch' `
          -Message 'Custom install fallback was not confirmed; returning to ISS playback retry menu'
      }

      while ($true) {
        cls
        Show-Header -Title 'Testing recorded uninstall string'
        Write-Host ''

        $uninstallCommand = $uninstallResult.IssSilentCommand
        $uninstallLogFolder = Join-Path `
          -Path $runtime.ScriptRoot `
          -ChildPath 'IntuneWin'

        $uninstallLogPath = Join-Path `
          -Path $uninstallLogFolder `
          -ChildPath 'Uninstall.log'

        $uninstallIssPath = Join-Path `
          -Path $uninstallLogFolder `
          -ChildPath 'Uninstall.iss'

                <#
                Write-Host 'Playback command:'
                #>
        Write-Host $uninstallCommand
        Write-Host ''
                <#
                Write-Host "ISS file: $uninstallIssPath"
                Write-Host "Uninstall log: $uninstallLogPath"
                Write-Host ''
                #>

        if (Test-Path -Path $uninstallLogPath) {
          Remove-Item `
            -Path $uninstallLogPath `
            -Force `
            -ErrorAction SilentlyContinue
        }

        try {
          $uninstallCommand = $uninstallResult.IssSilentCommand

          if ($uninstallCommand -match '^\s*"(?<file>[^"]+)"\s*(?<args>.*)$') {
            $playbackFilePath = $matches.file
            $playbackArguments = $matches.args
          }
          elseif ($uninstallCommand -match '^\s*(?<file>\S+)\s*(?<args>.*)$') {
            $playbackFilePath = $matches.file
            $playbackArguments = $matches.args
          }
          else {
            throw "Unable to parse ISS uninstall playback command: $uninstallCommand"
          }

                    <#
                    Write-Host "Executable: $playbackFilePath"
                    Write-Host "Arguments: $playbackArguments"
                    Write-Host ''
                    #>

          if (-not (Test-Path -Path $playbackFilePath)) {
            throw "ISS uninstall executable was not found: $playbackFilePath"
          }

          $psi = New-Object System.Diagnostics.ProcessStartInfo
          $psi.FileName = $playbackFilePath
          $psi.Arguments = $playbackArguments
          $psi.WorkingDirectory = Split-Path -Path $playbackFilePath -Parent
          $psi.UseShellExecute = $false
          $psi.CreateNoWindow = $true

          $proc = New-Object System.Diagnostics.Process
          $proc.StartInfo = $psi
          $null = $proc.Start()

          Write-Host "Playback process started."
          Write-Host "Process ID: $($proc.Id)"

          if (-not $proc.HasExited) {
            $proc.WaitForExit()
          }

          $uninstallPlaybackExitCode = $proc.ExitCode

          Write-Host "ISS uninstall playback exit code: $uninstallPlaybackExitCode"

          Write-Log `
            -LogPath $runtime.LogPath `
            -Level INFO `
            -Component 'Launch' `
            -Message ("ISS uninstall playback exit code: {0}" -f $uninstallPlaybackExitCode)
        }
        catch {
          Write-Host 'ISS uninstall playback command could not be started.'
          Write-Host $_.Exception.Message

          Write-Log `
            -LogPath $runtime.LogPath `
            -Level ERROR `
            -Component 'Launch' `
            -Message 'ISS uninstall playback command could not be started' `
            -Exception $_
        }

        cls
        $uninstallPlaybackOk = Read-YesNo `
          -Prompt 'Was the uninstall successful?' `
          -LogPath $runtime.LogPath

        if ($uninstallPlaybackOk) {
          break
        }

        Write-Host 'Uninstall playback was not confirmed.'
        Write-Host ''

        cls
        $playbackChoice = Show-Menu `
          -Prompt 'Choose how to continue:' `
          -Options @(
          'Retry ISS uninstall playback',
          'Enter a custom uninstall string'
        ) `
          -LogPath $runtime.LogPath

        if ($playbackChoice.SelectedIndex -eq 1) {
          Write-Log `
            -LogPath $runtime.LogPath `
            -Level WARN `
            -Component 'Launch' `
            -Message 'ISS uninstall playback was not confirmed; retrying ISS playback'

          continue
        }

        do {
          Show-Header -Title 'Enter the full uninstall command to run'
          Write-Host ''

          $customUninstallCommand = Read-Host 'Command'

          if ([string]::IsNullOrWhiteSpace($customUninstallCommand)) {
            Write-Host 'No command was entered. Please enter a full uninstall command.'
            Write-Host ''
          }
        }
        while ([string]::IsNullOrWhiteSpace($customUninstallCommand))

        Write-Log `
          -LogPath $runtime.LogPath `
          -Level INFO `
          -Component 'Launch' `
          -Message ("User selected custom uninstall fallback: {0}" -f $customUninstallCommand)

        try {
          $customPsi = New-Object System.Diagnostics.ProcessStartInfo
          $customPsi.FileName = 'cmd.exe'
          $customPsi.Arguments = '/c ' + $customUninstallCommand
          $customPsi.UseShellExecute = $false
          $customPsi.CreateNoWindow = $true

          $customProc = New-Object System.Diagnostics.Process
          $customProc.StartInfo = $customPsi
          $null = $customProc.Start()
          $customProc.WaitForExit()
          $customExitCode = $customProc.ExitCode

          Write-Log `
            -LogPath $runtime.LogPath `
            -Level INFO `
            -Component 'Launch' `
            -Message ("Custom uninstall fallback exit code: {0}" -f $customExitCode)
        }
        catch {
          Write-Host 'The custom uninstall command could not be started. Review the log for details.'

          Write-Log `
            -LogPath $runtime.LogPath `
            -Level ERROR `
            -Component 'Launch' `
            -Message 'Custom uninstall fallback could not be started' `
            -Exception $_

          continue
        }

        cls
        $customUninstallConfirmed = Read-YesNo `
          -Prompt 'Was the uninstall successful?' `
          -LogPath $runtime.LogPath

        if ($customUninstallConfirmed) {
          $uninstallResult.ConfirmedUninstallCommand = $customUninstallCommand
          $uninstallResult.UninstallStringSource = 'Custom'
          $uninstallResult.UninstallMethod = 'Custom'
          $uninstallResult.UsedIssRecording = $false
          $uninstallResult.IssSilentCommand = ''

          Write-Log `
            -LogPath $runtime.LogPath `
            -Level INFO `
            -Component 'Launch' `
            -Message 'Custom uninstall fallback was confirmed successful by user'

          break
        }

        Write-Host 'Custom uninstall fallback was not confirmed.'
        Write-Log `
          -LogPath $runtime.LogPath `
          -Level WARN `
          -Component 'Launch' `
          -Message 'Custom uninstall fallback was not confirmed; returning to ISS playback retry menu'
      }

      $installResult.ConfirmedInstallCommand = $installResult.IssSilentCommand
      $uninstallResult.ConfirmedUninstallCommand = $uninstallResult.IssSilentCommand
      $uninstallResult.UsedIssRecording = $false
    }

    $allUninstallResults += $uninstallResult

    $loopNativePath = Join-Path `
      -Path $runtime.OutputPath `
      -ChildPath 'Reg_UninstallLoop_Native.json'

    $loopWowPath = Join-Path `
      -Path $runtime.OutputPath `
      -ChildPath 'Reg_UninstallLoop_WOW6432NODE.json'

    $nextNative = New-RegistrySnapshot `
      -RegistryPath $config.registrySnapshot.nativePath `
      -SnapshotLabel 'UninstallLoop' `
      -OutputFilePath $loopNativePath `
      -LogPath $runtime.LogPath

    $nextWow = New-RegistrySnapshot `
      -RegistryPath $config.registrySnapshot.wow6432Path `
      -SnapshotLabel 'UninstallLoop' `
      -OutputFilePath $loopWowPath `
      -LogPath $runtime.LogPath

    $loopComparisonPath = Join-Path `
      -Path $runtime.OutputPath `
      -ChildPath 'RegistryComparison_UninstallLoop.json'

    $loopComparison = Compare-RegistrySnapshots `
      -PreNativeSnapshot $currentNativeBaseline `
      -PostNativeSnapshot $nextNative `
      -PreWowSnapshot $currentWowBaseline `
      -PostWowSnapshot $nextWow `
      -OutputFilePath $loopComparisonPath `
      -LogPath $runtime.LogPath

    $remainingCandidates = @(
      Get-NewUninstallEntries `
        -RegistryComparison $loopComparison `
        -LogPath $runtime.LogPath
    )

    $currentNativeBaseline = $nextNative
    $currentWowBaseline = $nextWow

    if ($remainingCandidates.Count -gt 0) {
      $continueChoice = Show-Menu `
        -Prompt 'Additional uninstall registry entries were detected.' `
        -Options @(
        'Continue to select another registry entry for uninstall',
        'Skip remaining entries and continue'
      ) `
        -LogPath $runtime.LogPath

      if ($continueChoice.SelectedIndex -eq 2) {
        Write-Log `
          -LogPath $runtime.LogPath `
          -Level INFO `
          -Component 'Launch' `
          -Message 'User chose to skip remaining uninstall registry entries and continue'

        break
      }
    }
    else {
      break
    }
  }

  if ($allUninstallResults.Count -eq 0) {
    throw 'No uninstall action was confirmed.'
  }

  $artifactResult = Save-RunArtifacts `
    -Installer $selectedInstaller `
    -SelectedRegistryEntry $selectedUninstallEntry `
    -InstallResult $installResult `
    -UninstallResults $allUninstallResults `
    -DetectionMethodPath $runtime.DetectionMethodPath `
    -LogPath $runtime.LogPath

  $commandFileResult = Export-IntuneWinCommandFiles `
    -ScriptRoot $runtime.ScriptRoot `
    -Installer $selectedInstaller `
    -InstallResult $installResult `
    -UninstallResults $allUninstallResults `
    -LogPath $runtime.LogPath

  Show-RunSummary `
    -Installer $selectedInstaller `
    -SelectedRegistryEntry $selectedUninstallEntry `
    -InstallResult $installResult `
    -UninstallResults $allUninstallResults `
    -LogPath $runtime.LogPath

  $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')

  cls
  Show-Header -Title 'IntuneWin creation in progress'

  $intuneWinToolPath = [System.IO.Path]::GetFullPath(
    (Join-Path $runtime.ScriptRoot $config.intuneWin.toolPath)
  )

  $intuneWinOutputPath = [System.IO.Path]::GetFullPath(
    (Join-Path $runtime.ScriptRoot $config.intuneWin.outputFolder)
  )

  try {
    $intuneWinResult = New-IntuneWinPackage `
      -Installer $selectedInstaller `
      -ToolPath $intuneWinToolPath `
      -OutputPath $intuneWinOutputPath `
      -LogPath $runtime.LogPath

    if ($intuneWinResult.Success) {
      cls
      Show-Header -Title 'IntuneWin package has been created for your software'
      Write-Host ''
      Write-Host 'File(s) can be found in the IntuneWin folder'
      Write-Host ''
      Write-Host 'Press any key to close...'

      Write-Log -LogPath $runtime.LogPath -Level INFO -Component 'Launch' -Message 'Workflow completed successfully'
      $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
      exit 0
    }
    else {
      cls
      Show-Header -Title 'IntuneWin package creation failed'
      Write-Host ''
      Write-Host 'The IntuneWin creation process did not complete successfully.'
      Write-Host 'Please review the logs and verify the IntuneWin tool path and installer details.'
      Write-Host ''
      Write-Host 'Press any key to close...'

      Write-Log -LogPath $runtime.LogPath -Level ERROR -Component 'Launch' -Message 'IntuneWin creation failed with a non-zero exit code'
      $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
      exit 1
    }
  }
  catch {
    cls
    Show-Header -Title 'IntuneWin package creation failed'
    Write-Host ''
    Write-Host 'The IntuneWin creation process encountered an error.'
    Write-Host 'Please review the logs and verify the IntuneWin tool path and installer details.'
    Write-Host ''
    Write-Host 'Press any key to close...'

    Write-Log -LogPath $runtime.LogPath -Level ERROR -Component 'Launch' -Message 'IntuneWin creation encountered an exception' -Exception $_
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit 1
  }
}
catch {
  if ($runtime -and $runtime.LogPath) {
    try {
      Write-Log `
        -LogPath $runtime.LogPath `
        -Level ERROR `
        -Component 'Launch' `
        -Message 'Fatal startup/workflow failure' `
        -Exception $_
    }
    catch {
    }
  }

  Write-Host 'A fatal startup error occurred.'

  if ($_.Exception.Message) {
    Write-Host $_.Exception.Message
  }

  exit 1
}
