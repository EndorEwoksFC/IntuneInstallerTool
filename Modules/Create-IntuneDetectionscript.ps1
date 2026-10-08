# ============================================================
# Create-IntuneDetectionScript.ps1
#
# Purpose:
#   Creates the Intune detection script from RegistryComparison.json
#
# Function:
#   Create-IntuneDetectionScript
#
# Detection behavior:
#
#   Named registry keys:
#       Uses the exact registry path.
#
#   GUID / MSI ProductCode registry keys:
#       Searches the parent Uninstall location for the
#       matching DisplayName and validates DisplayVersion.
#
#   This allows MSI applications to be detected correctly
#   when the ProductCode changes between a fresh install
#   and an upgraded installation.
#
# ============================================================

function Create-IntuneDetectionScript
{
  param (
    [Parameter(Mandatory = $true)]
    [string]$JsonPath,

    [Parameter(Mandatory = $true)]
    [string]$ApplicationName,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
  )

  # ========================================================
  # Validate JSON file
  # ========================================================

  if (-not (Test-Path -LiteralPath $JsonPath))
  {
    throw "Registry comparison JSON file was not found: $JsonPath"
  }

  try
  {
    $Comparison = Get-Content -LiteralPath $JsonPath -Raw -ErrorAction Stop |
      ConvertFrom-Json -ErrorAction Stop
  }
  catch
  {
    throw "Unable to read RegistryComparison.json. $($_.Exception.Message)"
  }

  # ========================================================
  # Collect registry candidates
  # ========================================================

  $AllCandidates = @()

  $RegistrySections = @(
    @{
      Name = 'Native'
      Object = $Comparison.Native
    },
    @{
      Name = 'Wow6432Node'
      Object = $Comparison.Wow6432Node
    }
  )

  foreach ($Section in $RegistrySections)
  {
    if ($null -eq $Section.Object)
    {
      continue
    }

    if ($null -eq $Section.Object.Added)
    {
      continue
    }

    foreach ($Entry in @($Section.Object.Added))
    {
      if ([string]::IsNullOrWhiteSpace($Entry.DisplayName))
      {
        continue
      }

      if ([string]::IsNullOrWhiteSpace($Entry.RegistryPath))
      {
        continue
      }

      if ([string]::IsNullOrWhiteSpace($Entry.DisplayVersion))
      {
        continue
      }

      try
      {
        $RequiredVersion = [version]$Entry.DisplayVersion
      }
      catch
      {
        continue
      }

      $RegistryPath = $Entry.RegistryPath

      if ($RegistryPath -match '^HKLM\\')
      {
        $RegistryPath = $RegistryPath -replace '^HKLM\\', 'HKLM:\'
      }
      elseif ($RegistryPath -match '^HKCU\\')
      {
        $RegistryPath = $RegistryPath -replace '^HKCU\\', 'HKCU:\'
      }
      elseif ($RegistryPath -match '^HKCR\\')
      {
        $RegistryPath = $RegistryPath -replace '^HKCR\\', 'HKCR:\'
      }

      # ================================================
      # Determine whether the registry key is a GUID
      # / MSI ProductCode style key.
      #
      # Example:
      # {12345678-1234-1234-1234-123456789ABC}
      # ================================================

      $RegistryKeyName = Split-Path -Path $RegistryPath -Leaf

      $IsGuidRegistryKey = $RegistryKeyName -match '^\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}$'

      $DetectionType = 'Exact'

      if ($IsGuidRegistryKey)
      {
        $DetectionType = 'UninstallDisplayName'
      }

      $AllCandidates += [PSCustomObject]@{
        DisplayName = [string]$Entry.DisplayName
        DisplayVersion = [string]$Entry.DisplayVersion
        RequiredVersion = $RequiredVersion
        RegistryLocation = $Section.Name
        RegistryPath = $RegistryPath
        RegistryKeyName = $RegistryKeyName
        DetectionType = $DetectionType
      }
    }
  }

  if ($AllCandidates.Count -eq 0)
  {
    throw "No usable Added registry entries were found in RegistryComparison.json."
  }

  # ========================================================
  # Find matching application
  # ========================================================

  $SearchPattern = "*$ApplicationName*"

  $Candidates = @(
    $AllCandidates | Where-Object {
      $_.DisplayName -like $SearchPattern
    }
  )

  # ========================================================
  # If no match, allow user to select applications
  # ========================================================

  if ($Candidates.Count -eq 0)
  {
    Write-Host ''
    Write-Host 'The supplied application name did not match a registry entry.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'Select the application(s) to use for Intune detection:' -ForegroundColor Cyan
    Write-Host ''

    for ($Index = 0; $Index -lt $AllCandidates.Count; $Index++)
    {
      $Candidate = $AllCandidates[$Index]

      Write-Host "$($Index + 1). $($Candidate.DisplayName)"
      Write-Host "   Version:  $($Candidate.DisplayVersion)"
      Write-Host "   Location: $($Candidate.RegistryLocation)"
      Write-Host "   Registry: $($Candidate.RegistryPath)"

      if ($Candidate.DetectionType -eq 'UninstallDisplayName')
      {
        Write-Host "   Detection: MSI ProductCode / DisplayName search" -ForegroundColor Cyan
      }
      else
      {
        Write-Host "   Detection: Exact registry key" -ForegroundColor Gray
      }

      Write-Host ''
    }

    Write-Host '0. Cancel' -ForegroundColor Yellow
    Write-Host ''

    $Selection = Read-Host 'Select application(s)'

    if ([string]::IsNullOrWhiteSpace($Selection))
    {
      throw 'No application was selected.'
    }

    $SelectionValues = $Selection -split '[,\s]+' |
      Where-Object {
      -not [string]::IsNullOrWhiteSpace($_)
    }

    $SelectedIndexes = @()

    foreach ($SelectionValue in $SelectionValues)
    {
      $SelectedIndex = 0

      if (-not [int]::TryParse($SelectionValue, [ref]$SelectedIndex))
      {
        throw "Invalid selection: $SelectionValue"
      }

      if ($SelectedIndex -eq 0)
      {
        throw 'Operation cancelled by user.'
      }

      if ($SelectedIndex -lt 1 -or $SelectedIndex -gt $AllCandidates.Count)
      {
        throw "Selection out of range: $SelectedIndex"
      }

      if ($SelectedIndexes -notcontains ($SelectedIndex - 1))
      {
        $SelectedIndexes += ($SelectedIndex - 1)
      }
    }

    $Candidates = @(
      foreach ($SelectedIndex in $SelectedIndexes)
      {
        $AllCandidates[$SelectedIndex]
      }
    )
  }

  if ($Candidates.Count -eq 0)
  {
    throw 'No usable registry entries were selected.'
  }

  # ========================================================
  # Build generated detection script
  # ========================================================

  $ScriptLines = @()

  $ScriptLines += '#============================================================'
  $ScriptLines += '# Intune Detection Script'
  $ScriptLines += '#'
  $ScriptLines += '# Generated by Greif Installer Tool'
  $ScriptLines += '#'
  $ScriptLines += '# Detection logic:'
  $ScriptLines += '#   Installed version >= required version = Detected'
  $ScriptLines += '#   Installed version < required version  = Not Detected'
  $ScriptLines += '#   Application not installed             = Not Detected'
  $ScriptLines += '#'
  $ScriptLines += '# Registry detection:'
  $ScriptLines += '#   Named registry key                   = Exact key detection'
  $ScriptLines += '#   GUID / MSI ProductCode registry key  = DisplayName search'
  $ScriptLines += '#============================================================'
  $ScriptLines += ''
  $ScriptLines += '$ErrorActionPreference = ''SilentlyContinue'''
  $ScriptLines += ''

  foreach ($Candidate in $Candidates)
  {
    $EscapedRegistryPath = $Candidate.RegistryPath.Replace("'", "''")
    $EscapedDisplayName = $Candidate.DisplayName.Replace("'", "''")
    $RequiredVersion = $Candidate.RequiredVersion.ToString()

    # ====================================================
    # Detection Type: GUID / MSI ProductCode
    # ====================================================

    if ($Candidate.DetectionType -eq 'UninstallDisplayName')
    {
      # -----------------------------------------------
      # Determine parent Uninstall path
      # -----------------------------------------------

      $UninstallPath = Split-Path -Path $Candidate.RegistryPath -Parent
      $EscapedUninstallPath = $UninstallPath.Replace("'", "''")

      $ScriptLines += '#------------------------------------------------------------'
      $ScriptLines += "# $($Candidate.DisplayName)"
      $ScriptLines += "# Registry Location: $($Candidate.RegistryLocation)"
      $ScriptLines += "# Detection Type:    MSI ProductCode / DisplayName search"
      $ScriptLines += "# Required Version:  $($Candidate.DisplayVersion)"
      $ScriptLines += '#------------------------------------------------------------'
      $ScriptLines += ''
      $ScriptLines += "`$RegistryPath = '$EscapedUninstallPath'"
      $ScriptLines += ''
      $ScriptLines += '# Search all uninstall registry keys so the MSI ProductCode'
      $ScriptLines += '# can change between installations or upgrades.'
      $ScriptLines += '$ApplicationKeys = Get-ChildItem -Path $RegistryPath -ErrorAction SilentlyContinue'
      $ScriptLines += ''
      $ScriptLines += 'foreach ($Key in $ApplicationKeys)'
      $ScriptLines += '{'
      $ScriptLines += '    try'
      $ScriptLines += '    {'
      $ScriptLines += '        $Application = Get-ItemProperty -LiteralPath $Key.PSPath -ErrorAction Stop'
      $ScriptLines += ''
      $ScriptLines += '        if (-not [string]::IsNullOrWhiteSpace($Application.DisplayName))'
      $ScriptLines += '        {'
      $ScriptLines += "            if (`$Application.DisplayName -eq '$EscapedDisplayName')"
      $ScriptLines += '            {'
      $ScriptLines += '                if (-not [string]::IsNullOrWhiteSpace($Application.DisplayVersion))'
      $ScriptLines += '                {'
      $ScriptLines += '                    try'
      $ScriptLines += '                    {'
      $ScriptLines += '                        $InstalledVersion = [version]$Application.DisplayVersion'
      $ScriptLines += "                        `$RequiredVersion = [version]'$RequiredVersion'"
      $ScriptLines += ''
      $ScriptLines += '                        if ($InstalledVersion -ge $RequiredVersion)'
      $ScriptLines += '                        {'
      $ScriptLines += "                            Write-Output 'Detected'"
      $ScriptLines += '                            exit 0'
      $ScriptLines += '                        }'
      $ScriptLines += '                    }'
      $ScriptLines += '                    catch'
      $ScriptLines += '                    {'
      $ScriptLines += '                    }'
      $ScriptLines += '                }'
      $ScriptLines += '            }'
      $ScriptLines += '        }'
      $ScriptLines += '    }'
      $ScriptLines += '    catch'
      $ScriptLines += '    {'
      $ScriptLines += '    }'
      $ScriptLines += '}'
      $ScriptLines += ''
    }
    else
    {
      # ================================================
      # Detection Type: Exact Registry Key
      # ================================================

      $ScriptLines += '#------------------------------------------------------------'
      $ScriptLines += "# $($Candidate.DisplayName)"
      $ScriptLines += "# Registry Location: $($Candidate.RegistryLocation)"
      $ScriptLines += "# Detection Type:    Exact registry key"
      $ScriptLines += "# Required Version:  $($Candidate.DisplayVersion)"
      $ScriptLines += '#------------------------------------------------------------'
      $ScriptLines += ''
      $ScriptLines += "`$RegistryPath = '$EscapedRegistryPath'"
      $ScriptLines += ''
      $ScriptLines += 'if (Test-Path -LiteralPath $RegistryPath)'
      $ScriptLines += '{'
      $ScriptLines += '    try'
      $ScriptLines += '    {'
      $ScriptLines += '        $Application = Get-ItemProperty -LiteralPath $RegistryPath -ErrorAction Stop'
      $ScriptLines += '    }'
      $ScriptLines += '    catch'
      $ScriptLines += '    {'
      $ScriptLines += '        $Application = $null'
      $ScriptLines += '    }'
      $ScriptLines += ''
      $ScriptLines += '    if ($Application)'
      $ScriptLines += '    {'
      $ScriptLines += '        if (-not [string]::IsNullOrWhiteSpace($Application.DisplayName))'
      $ScriptLines += '        {'
      $ScriptLines += "            if (`$Application.DisplayName -eq '$EscapedDisplayName')"
      $ScriptLines += '            {'
      $ScriptLines += '                if (-not [string]::IsNullOrWhiteSpace($Application.DisplayVersion))'
      $ScriptLines += '                {'
      $ScriptLines += '                    try'
      $ScriptLines += '                    {'
      $ScriptLines += '                        $InstalledVersion = [version]$Application.DisplayVersion'
      $ScriptLines += "                        `$RequiredVersion = [version]'$RequiredVersion'"
      $ScriptLines += ''
      $ScriptLines += '                        if ($InstalledVersion -ge $RequiredVersion)'
      $ScriptLines += '                        {'
      $ScriptLines += "                            Write-Output 'Detected'"
      $ScriptLines += '                            exit 0'
      $ScriptLines += '                        }'
      $ScriptLines += '                    }'
      $ScriptLines += '                    catch'
      $ScriptLines += '                    {'
      $ScriptLines += '                    }'
      $ScriptLines += '                }'
      $ScriptLines += '            }'
      $ScriptLines += '        }'
      $ScriptLines += '    }'
      $ScriptLines += '}'
      $ScriptLines += ''
    }
  }

  # ========================================================
  # Final detection result
  # ========================================================

  $ScriptLines += "Write-Output 'Not Detected'"
  $ScriptLines += 'exit 1'

  # ========================================================
  # Create output directory
  # ========================================================

  $OutputDirectory = Split-Path -Path $OutputPath -Parent

  if (-not [string]::IsNullOrWhiteSpace($OutputDirectory))
  {
    if (-not (Test-Path -LiteralPath $OutputDirectory))
    {
      New-Item `
        -Path $OutputDirectory `
        -ItemType Directory `
        -Force |
        Out-Null
    }
  }

  # ========================================================
  # Write output
  # ========================================================

  Set-Content `
    -LiteralPath $OutputPath `
    -Value $ScriptLines `
    -Encoding UTF8 `
    -Force `
    -ErrorAction Stop

  # ========================================================
  # Return results
  # ========================================================

  return [PSCustomObject]@{
    OutputPath = $OutputPath
    CandidateCount = $Candidates.Count
    Candidates = $Candidates
  }
}
