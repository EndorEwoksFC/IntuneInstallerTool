function Get-InstallerMetadata {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]$Installer,

        [Parameter(Mandatory)]
        [string]$MetadataPath,

        [string]$LogPath
    )

    if ($LogPath) {
        Write-Log -LogPath $LogPath -Level INFO -Component 'Get-InstallerMetadata' -Message "Starting metadata extraction for $($Installer.FullPath)"
    }

    if (-not (Test-Path -LiteralPath $Installer.FullPath)) {
        throw "Installer file was not found: $($Installer.FullPath)"
    }

    try {
        $item = Get-Item -LiteralPath $Installer.FullPath -ErrorAction Stop
        $versionInfo = $item.VersionInfo
        $metadata = [pscustomobject]@{
            Name = $item.Name
            FullPath = $item.FullName
            RelativePath = $Installer.RelativePath
            Extension = $Installer.Extension
            Publisher = ''
            ProductName = ''
            FileVersion = ''
            ProductVersion = ''
            WrapperType = ''
            ProductCode = ''
            PublicProperties = @()
            SuggestedArgs = ''
            SuggestionSource = ''
            SuggestionConfidence = ''
            Notes = @()
        }

        if ($versionInfo) {
            $metadata.Publisher = [string]$versionInfo.CompanyName
            $metadata.ProductName = [string]$versionInfo.ProductName
            $metadata.FileVersion = [string]$versionInfo.FileVersion
            $metadata.ProductVersion = [string]$versionInfo.ProductVersion
            $combined = ([string]$versionInfo.FileDescription + ' ' + [string]$versionInfo.ProductName)

            if ($Installer.Extension -eq '.exe') {
                if ($combined -match 'Inno') {
                    $metadata.WrapperType = 'Inno Setup'
                    $metadata.SuggestedArgs = '/VERYSILENT /NORESTART'
                    $metadata.SuggestionSource = 'WrapperHeuristic'
                    $metadata.SuggestionConfidence = 'Medium'
                }
                elseif ($combined -match 'NSIS') {
                    $metadata.WrapperType = 'NSIS'
                    $metadata.SuggestedArgs = '/S'
                    $metadata.SuggestionSource = 'WrapperHeuristic'
                    $metadata.SuggestionConfidence = 'Medium'
                }
                elseif ($combined -match 'InstallShield') {
                    $metadata.WrapperType = 'InstallShield'
                    $metadata.SuggestedArgs = '/s'
                    $metadata.SuggestionSource = 'WrapperHeuristic'
                    $metadata.SuggestionConfidence = 'Medium'
                }
                elseif ($combined -match 'Squirrel') {
                    $metadata.WrapperType = 'Squirrel'
                    $metadata.SuggestedArgs = '--silent'
                    $metadata.SuggestionSource = 'WrapperHeuristic'
                    $metadata.SuggestionConfidence = 'Low'
                }
            }
        }

        if ($Installer.Extension -eq '.msi') {
            $windowsInstaller = New-Object -ComObject WindowsInstaller.Installer
            $db = $windowsInstaller.GetType().InvokeMember('OpenDatabase', 'InvokeMethod', $null, $windowsInstaller, @($item.FullName, 0))
            $getProp = {
                param($name)

                try {
                    $view = $db.GetType().InvokeMember('OpenView', 'InvokeMethod', $null, $db, @("SELECT `Value` FROM `Property` WHERE `Property`='$name'"))
                    $view.GetType().InvokeMember('Execute', 'InvokeMethod', $null, $view, $null) | Out-Null
                    $rec = $view.GetType().InvokeMember('Fetch', 'InvokeMethod', $null, $view, $null)

                    if ($rec) {
                        return $rec.GetType().InvokeMember('StringData', 'GetProperty', $null, $rec, 1)
                    }
                }
                catch {
                }

                return ''
            }

            $metadata.ProductName = (& $getProp 'ProductName')
            $metadata.Publisher = (& $getProp 'Manufacturer')
            $metadata.ProductVersion = (& $getProp 'ProductVersion')
            $metadata.ProductCode = (& $getProp 'ProductCode')
            $metadata.SuggestedArgs = '/qn /norestart'
            $metadata.SuggestionSource = 'MSIStandard'
            $metadata.SuggestionConfidence = 'High'

            foreach ($prop in 'ALLUSERS', 'ACCEPTEULA') {
                $val = & $getProp $prop
                if (-not [string]::IsNullOrWhiteSpace($val)) {
                    $metadata.PublicProperties += "$prop=$val"
                }
            }
        }
        elseif ($Installer.Extension -eq '.msix') {
            $metadata.Notes += 'MSIX handling is limited in v1.'
        }
        elseif ($Installer.Extension -in @('.bat', '.cmd', '.ps1')) {
            $metadata.Notes += 'Script-based installer. No automatic silent recommendation by default.'
        }

        $lines = @(
            'Installer Metadata',
            '------------------',
            "Name: $($metadata.Name)",
            "Path: $($metadata.FullPath)",
            "Extension: $($metadata.Extension)",
            "Publisher: $($metadata.Publisher)",
            "ProductName: $($metadata.ProductName)",
            "FileVersion: $($metadata.FileVersion)",
            "ProductVersion: $($metadata.ProductVersion)",
            "ProductCode: $($metadata.ProductCode)",
            "WrapperType: $($metadata.WrapperType)",
            'PublicProperties:'
        )

        if ($metadata.PublicProperties.Count -gt 0) {
            foreach ($p in $metadata.PublicProperties) {
                $lines += "- $p"
            }
        }
        else {
            $lines += '-'
        }

        $lines += @(
            '',
            "SuggestedArgs: $($metadata.SuggestedArgs)",
            "SuggestionSource: $($metadata.SuggestionSource)",
            "SuggestionConfidence: $($metadata.SuggestionConfidence)",
            'Notes:'
        )

        if ($metadata.Notes.Count -gt 0) {
            foreach ($n in $metadata.Notes) {
                $lines += "- $n"
            }
        }
        else {
            $lines += '-'
        }

        [System.IO.File]::WriteAllLines($MetadataPath, $lines, [System.Text.UTF8Encoding]::new($false))

        if ($LogPath) {
            Write-Log -LogPath $LogPath -Level INFO -Component 'Get-InstallerMetadata' -Message "Metadata saved to $MetadataPath"
        }

        return $metadata
    }
    catch {
        if ($LogPath) {
            Write-Log -LogPath $LogPath -Level ERROR -Component 'Get-InstallerMetadata' -Message "Metadata extraction failed for $($Installer.FullPath)" -Exception $_
        }

        throw
    }
}
