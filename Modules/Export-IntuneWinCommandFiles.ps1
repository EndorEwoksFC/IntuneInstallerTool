function Export-IntuneWinCommandFiles {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$ScriptRoot,

        [Parameter(Mandatory)]
        [object]$Installer,

        [Parameter(Mandatory)]
        [object]$InstallResult,

        [Parameter(Mandatory)]
        [object[]]$UninstallResults,

        [Parameter(Mandatory)]
        [string]$LogPath
    )

    $intuneWinFolder = Join-Path -Path $ScriptRoot -ChildPath 'IntuneWin'
    $installFilePath = Join-Path -Path $intuneWinFolder -ChildPath 'Install.ps1'
    $uninstallFilePath = Join-Path -Path $intuneWinFolder -ChildPath 'Uninstall.ps1'

    try {
        #============================================================
        # Create IntuneWin command folder
        #============================================================

        if (-not (Test-Path -Path $intuneWinFolder)) {
            New-Item -Path $intuneWinFolder -ItemType Directory -Force | Out-Null

            Write-Log `
                -LogPath $LogPath `
                -Level INFO `
                -Component 'Export-IntuneWinCommandFiles' `
                -Message ("Created IntuneWin folder: {0}" -f $intuneWinFolder)
        }


        #============================================================
        # Validate confirmed install command
        #============================================================

        $confirmedInstallCommand = [string]$InstallResult.ConfirmedInstallCommand

        if ([string]::IsNullOrWhiteSpace($confirmedInstallCommand)) {
            throw 'No confirmed install command was supplied.'
        }


        #============================================================
        # Determine installer information
        #============================================================

        $installerName = [string]$Installer.Name
        $installerExtension = [string]$Installer.Extension

        if ([string]::IsNullOrWhiteSpace($installerExtension)) {
            $installerExtension = [System.IO.Path]::GetExtension($installerName)
        }

        $installerExtension = $installerExtension.ToLowerInvariant()


        Write-Log `
            -LogPath $LogPath `
            -Level INFO `
            -Component 'Export-IntuneWinCommandFiles' `
            -Message ("Generating Intune install wrapper for installer '{0}' ({1})" -f $installerName, $installerExtension)


        #============================================================
        # Build Install.ps1
        #============================================================

        $installLines = New-Object System.Collections.Generic.List[string]

        switch ($installerExtension) {

            #========================================================
            # MSI
            #========================================================

            '.msi' {

                $installLines.Add('$MsiPath = Join-Path $PSScriptRoot "' + $installerName + '"')
                $installLines.Add('')

                # Extract the arguments from the confirmed command.
                #
                # Expected example:
                # msiexec.exe /i "C:\PackageTest\Application.msi" /qn /norestart ALLUSERS=1
                #
                # or:
                # "C:\PackageTest\Application.msi" /qn /norestart
                #
                $arguments = $confirmedInstallCommand

                $escapedOriginalPath = [regex]::Escape([string]$Installer.FullPath)

                # Remove common MSI executable portions.
                $arguments = [regex]::Replace(
                    $arguments,
                    '(?i)^\s*msiexec(?:\.exe)?\s*',
                    ''
                )

                # Remove the original installer path.
                $arguments = [regex]::Replace(
                    $arguments,
                    '"' + $escapedOriginalPath + '"',
                    '',
                    1
                )

                $arguments = [regex]::Replace(
                    $arguments,
                    $escapedOriginalPath,
                    '',
                    1
                )

                # Remove an initial /i or /package switch because
                # the wrapper supplies /i itself.
                $arguments = [regex]::Replace(
                    $arguments,
                    '(?i)^\s*/(?:i|package)\s*',
                    ''
                )

                $arguments = $arguments.Trim()

                # Escape quotes for the PowerShell string.
                $escapedArguments = $arguments.Replace('"', '`"')

                $installLines.Add('$Arguments = "/i `"$MsiPath`" ' + $escapedArguments + '"')
                $installLines.Add('')

                $installLines.Add('$Process = Start-Process -FilePath "msiexec.exe" `')
                $installLines.Add('                         -ArgumentList $Arguments `')
                $installLines.Add('                         -Wait `')
                $installLines.Add('                         -PassThru')
                $installLines.Add('')
                $installLines.Add('exit $Process.ExitCode')
            }


            #========================================================
            # EXE
            #========================================================

            '.exe' {

                $installLines.Add('$InstallerPath = Join-Path $PSScriptRoot "' + $installerName + '"')
                $installLines.Add('')

                $arguments = $confirmedInstallCommand
                $escapedOriginalPath = [regex]::Escape([string]$Installer.FullPath)

                # Remove the original quoted installer path.
                $arguments = [regex]::Replace(
                    $arguments,
                    '"' + $escapedOriginalPath + '"',
                    '',
                    1
                )

                # Remove the original unquoted installer path if necessary.
                $arguments = [regex]::Replace(
                    $arguments,
                    $escapedOriginalPath,
                    '',
                    1
                )

                $arguments = $arguments.Trim()

                $escapedArguments = $arguments.Replace('"', '`"')

                $installLines.Add('$Arguments = "' + $escapedArguments + '"')
                $installLines.Add('')

                $installLines.Add('$Process = Start-Process -FilePath $InstallerPath `')
                $installLines.Add('                         -ArgumentList $Arguments `')
                $installLines.Add('                         -Wait `')
                $installLines.Add('                         -PassThru')
                $installLines.Add('')
                $installLines.Add('exit $Process.ExitCode')
            }


            #========================================================
            # MSIX / MSIXBundle
            #========================================================

            '.msix' {
                $isMsix = $true
            }

            '.msixbundle' {
                $isMsix = $true
            }


            #========================================================
            # Unsupported installer type
            #========================================================

            default {
                throw "Installer type '$installerExtension' is not currently supported by Export-IntuneWinCommandFiles."
            }
        }


        #============================================================
        # MSIX / MSIXBundle wrapper
        #============================================================

        if ($isMsix) {

            $installLines.Clear()

            $installLines.Add('$PackagePath = Join-Path $PSScriptRoot "' + $installerName + '"')
            $installLines.Add('')
            $installLines.Add('$DependencyPaths = @()')
            $installLines.Add('')
            $installLines.Add('try {')
            $installLines.Add('    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop')
            $installLines.Add('')
            $installLines.Add('    $packageZip = [System.IO.Compression.ZipFile]::OpenRead($PackagePath)')
            $installLines.Add('')
            $installLines.Add('    try {')
            $installLines.Add('        $manifestEntry = $packageZip.Entries | Where-Object {')
            $installLines.Add('            $_.FullName -ieq "AppxManifest.xml" -or')
            $installLines.Add('            $_.FullName -like "*/AppxManifest.xml"')
            $installLines.Add('        } | Select-Object -First 1')
            $installLines.Add('')
            $installLines.Add('        if ($manifestEntry) {')
            $installLines.Add('            $reader = New-Object System.IO.StreamReader($manifestEntry.Open())')
            $installLines.Add('            try {')
            $installLines.Add('                $manifestXml = [xml]$reader.ReadToEnd()')
            $installLines.Add('            }')
            $installLines.Add('            finally {')
            $installLines.Add('                $reader.Dispose()')
            $installLines.Add('            }')
            $installLines.Add('')
            $installLines.Add('            $dependencyNodes = $manifestXml.Package.Dependencies.PackageDependency')
            $installLines.Add('')
            $installLines.Add('            if ($dependencyNodes) {')
            $installLines.Add('                $dependencyPackages = Get-ChildItem -Path $PSScriptRoot -File |')
            $installLines.Add('                    Where-Object { $_.Extension -in ".appx", ".appxbundle" }')
            $installLines.Add('')
            $installLines.Add('                foreach ($dependencyNode in $dependencyNodes) {')
            $installLines.Add('                    $dependencyName = [string]$dependencyNode.Name')
            $installLines.Add('')
            $installLines.Add('                    foreach ($dependencyPackage in $dependencyPackages) {')
            $installLines.Add('                        try {')
            $installLines.Add('                            $dependencyZip = [System.IO.Compression.ZipFile]::OpenRead($dependencyPackage.FullName)')
            $installLines.Add('')
            $installLines.Add('                            try {')
            $installLines.Add('                                $dependencyManifest = $dependencyZip.Entries | Where-Object {')
            $installLines.Add('                                    $_.FullName -ieq "AppxManifest.xml" -or')
            $installLines.Add('                                    $_.FullName -like "*/AppxManifest.xml"')
            $installLines.Add('                                } | Select-Object -First 1')
            $installLines.Add('')
            $installLines.Add('                                if ($dependencyManifest) {')
            $installLines.Add('                                    $dependencyReader = New-Object System.IO.StreamReader($dependencyManifest.Open())')
            $installLines.Add('                                    try {')
            $installLines.Add('                                        $dependencyXml = [xml]$dependencyReader.ReadToEnd()')
            $installLines.Add('                                    }')
            $installLines.Add('                                    finally {')
            $installLines.Add('                                        $dependencyReader.Dispose()')
            $installLines.Add('                                    }')
            $installLines.Add('')
            $installLines.Add('                                    $identity = $dependencyXml.Package.Identity')
            $installLines.Add('')
            $installLines.Add('                                    if ($identity -and $identity.Name -eq $dependencyName) {')
            $installLines.Add('                                        if ($DependencyPaths -notcontains $dependencyPackage.FullName) {')
            $installLines.Add('                                            $DependencyPaths += $dependencyPackage.FullName')
            $installLines.Add('                                        }')
            $installLines.Add('                                    }')
            $installLines.Add('                                }')
            $installLines.Add('                            }')
            $installLines.Add('                            finally {')
            $installLines.Add('                                $dependencyZip.Dispose()')
            $installLines.Add('                            }')
            $installLines.Add('                        }')
            $installLines.Add('                        catch {')
            $installLines.Add('                            # Ignore files that are not valid AppX packages.')
            $installLines.Add('                        }')
            $installLines.Add('                    }')
            $installLines.Add('                }')
            $installLines.Add('            }')
            $installLines.Add('        }')
            $installLines.Add('    }')
            $installLines.Add('    finally {')
            $installLines.Add('        $packageZip.Dispose()')
            $installLines.Add('    }')
            $installLines.Add('')
            $installLines.Add('    if ($DependencyPaths.Count -gt 0) {')
            $installLines.Add('        Add-AppxProvisionedPackage `')
            $installLines.Add('            -Online `')
            $installLines.Add('            -PackagePath $PackagePath `')
            $installLines.Add('            -DependencyPackagePath $DependencyPaths `')
            $installLines.Add('            -SkipLicense `')
            $installLines.Add('            -ErrorAction Stop')
            $installLines.Add('    }')
            $installLines.Add('    else {')
            $installLines.Add('        Add-AppxProvisionedPackage `')
            $installLines.Add('            -Online `')
            $installLines.Add('            -PackagePath $PackagePath `')
            $installLines.Add('            -SkipLicense `')
            $installLines.Add('            -ErrorAction Stop')
            $installLines.Add('    }')
            $installLines.Add('')
            $installLines.Add('    exit 0')
            $installLines.Add('}')
            $installLines.Add('catch {')
            $installLines.Add('    Write-Error $_')
            $installLines.Add('    exit 1')
            $installLines.Add('}')
        }


        #============================================================
        # Write Install.ps1
        #============================================================

        [System.IO.File]::WriteAllLines(
            $installFilePath,
            $installLines,
            [System.Text.UTF8Encoding]::new($false)
        )


        #============================================================
        # Build Uninstall.ps1
        #============================================================

        $uninstallLines = New-Object System.Collections.Generic.List[string]

        foreach ($result in $UninstallResults) {

            $confirmedUninstallCommand = [string]$result.ConfirmedUninstallCommand

            if (-not [string]::IsNullOrWhiteSpace($confirmedUninstallCommand)) {
                $uninstallLines.Add($confirmedUninstallCommand)
                $uninstallLines.Add('')
            }
        }

        if ($uninstallLines.Count -eq 0) {
            $uninstallLines.Add('Write-Host "No confirmed uninstall command was provided."')
            $uninstallLines.Add('exit 1')
        }


        #============================================================
        # Write Uninstall.ps1
        #============================================================

        [System.IO.File]::WriteAllLines(
            $uninstallFilePath,
            $uninstallLines,
            [System.Text.UTF8Encoding]::new($false)
        )


        #============================================================
        # Logging
        #============================================================

        Write-Log `
            -LogPath $LogPath `
            -Level INFO `
            -Component 'Export-IntuneWinCommandFiles' `
            -Message ("Wrote Install.ps1 to {0}" -f $installFilePath)

        Write-Log `
            -LogPath $LogPath `
            -Level INFO `
            -Component 'Export-IntuneWinCommandFiles' `
            -Message ("Wrote Uninstall.ps1 to {0}" -f $uninstallFilePath)


        #============================================================
        # Return result
        #============================================================

        return [pscustomobject]@{
            Success = $true
            IntuneWinFolder = $intuneWinFolder
            InstallFilePath = $installFilePath
            UninstallFilePath = $uninstallFilePath
            InstallerName = $installerName
            InstallerExtension = $installerExtension
        }
    }
    catch {
        Write-Log `
            -LogPath $LogPath `
            -Level ERROR `
            -Component 'Export-IntuneWinCommandFiles' `
            -Message 'Failed to export IntuneWin command files' `
            -Exception $_

        throw
    }
}