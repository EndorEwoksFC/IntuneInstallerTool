function Export-InstalledApplicationIcons {
    <#
    .SYNOPSIS
        Finds application images and exports them as PNG files.

    .DESCRIPTION
        This function retains the name Export-InstalledApplicationIcons for
        compatibility with existing Packaging Tool scripts.

        The function is intended to locate application artwork that can be
        used for Microsoft Intune application icons.

        The function:

        - Reads application directories from the supplied JSON file.
        - Scans application directories recursively.
        - Finds existing image files including:
              PNG
              JPG / JPEG
              BMP
              GIF
              TIFF / TIF
              WEBP (when supported by the installed .NET image libraries)
        - Scans EXE and DLL files for embedded image resources.
        - Extracts embedded PNG and JPEG image data.
        - Extracts Windows icon resources when applicable.
        - Converts supported source images and extracted icons to PNG.
        - Outputs PNG files only.
        - Uses collision-safe file names so existing images are not overwritten.
        - Does not create or copy ICO files.

        The function name is intentionally retained as
        Export-InstalledApplicationIcons so existing scripts do not need
        to be modified.

    .PARAMETER JsonPath
        Path to the JSON file containing the application comparison data.

    .PARAMETER OutputPath
        Directory where the converted PNG files will be written.

    .OUTPUTS
        PSCustomObject containing scan and export statistics.

    .NOTES
        Intended for use with Microsoft Intune application icon preparation.

        All generated image files are PNG regardless of the original image
        format.

        Supported source formats depend partly on the Windows/.NET image
        codecs available on the system running the function.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$JsonPath,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    $ErrorActionPreference = 'Stop'

    # ============================================================
    # Configuration
    # ============================================================

    $SupportedImageExtensions = @(
        '.png',
        '.jpg',
        '.jpeg',
        '.bmp',
        '.gif',
        '.tif',
        '.tiff',
        '.webp'
    )

    $ExecutableExtensions = @(
        '.exe',
        '.dll'
    )

    # ============================================================
    # Counters
    # ============================================================

    $DirectoriesScanned = 0
    $FilesScanned = 0
    $ImagesExported = 0
    $ExistingImagesConverted = 0
    $EmbeddedImagesExtracted = 0
    $IconsConverted = 0
    $FilesSkipped = 0

    # ============================================================
    # Validate JSON
    # ============================================================

    if (-not (Test-Path -LiteralPath $JsonPath)) {
        throw "JSON file was not found: $JsonPath"
    }

    try {
        $Comparison = Get-Content -LiteralPath $JsonPath -Raw |
            ConvertFrom-Json
    }
    catch {
        throw "Unable to read or parse JSON file: $JsonPath`n$($_.Exception.Message)"
    }

    # ============================================================
    # Validate Output Directory
    # ============================================================

    if (-not (Test-Path -LiteralPath $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory -Force |
            Out-Null
    }

    # ============================================================
    # Load System.Drawing
    # ============================================================

    try {
        Add-Type -AssemblyName System.Drawing
    }
    catch {
        throw "Unable to load System.Drawing. $($_.Exception.Message)"
    }

    # ============================================================
    # Helper - Get Unique Output Path
    # ============================================================

    function Get-UniqueOutputPath {
        param (
            [Parameter(Mandatory = $true)]
            [string]$Directory,

            [Parameter(Mandatory = $true)]
            [string]$BaseName
        )

        $SafeBaseName = $BaseName -replace '[\\/:*?"<>|]', '_'

        if ([string]::IsNullOrWhiteSpace($SafeBaseName)) {
            $SafeBaseName = 'ApplicationImage'
        }

        $Candidate = Join-Path $Directory "$SafeBaseName.png"

        if (-not (Test-Path -LiteralPath $Candidate)) {
            return $Candidate
        }

        $Counter = 1

        do {
            $Candidate = Join-Path $Directory "$SafeBaseName-$Counter.png"
            $Counter++
        }
        while (Test-Path -LiteralPath $Candidate)

        return $Candidate
    }

    # ============================================================
    # Helper - Save Image As PNG
    # ============================================================

    function Save-ImageAsPng {
        param (
            [Parameter(Mandatory = $true)]
            [System.Drawing.Image]$Image,

            [Parameter(Mandatory = $true)]
            [string]$OutputFile
        )

        $Bitmap = $null
        $Graphics = $null

        try {
            # Create a new bitmap so the source file is not locked
            # while the PNG is being written.

            $Bitmap = New-Object System.Drawing.Bitmap(
                $Image.Width,
                $Image.Height,
                [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
            )

            $Graphics = [System.Drawing.Graphics]::FromImage($Bitmap)

            $Graphics.Clear([System.Drawing.Color]::Transparent)

            $Graphics.DrawImage(
                $Image,
                0,
                0,
                $Image.Width,
                $Image.Height
            )

            $Bitmap.Save(
                $OutputFile,
                [System.Drawing.Imaging.ImageFormat]::Png
            )
        }
        finally {
            if ($Graphics) {
                $Graphics.Dispose()
            }

            if ($Bitmap) {
                $Bitmap.Dispose()
            }
        }
    }

    # ============================================================
    # Helper - Detect Image Type From Bytes
    # ============================================================

    function Get-ImageTypeFromBytes {
        param (
            [Parameter(Mandatory = $true)]
            [byte[]]$Bytes
        )

        if ($Bytes.Length -ge 8) {

            # PNG
            if (
                $Bytes[0] -eq 0x89 -and
                $Bytes[1] -eq 0x50 -and
                $Bytes[2] -eq 0x4E -and
                $Bytes[3] -eq 0x47 -and
                $Bytes[4] -eq 0x0D -and
                $Bytes[5] -eq 0x0A -and
                $Bytes[6] -eq 0x1A -and
                $Bytes[7] -eq 0x0A
            ) {
                return 'PNG'
            }
        }

        if ($Bytes.Length -ge 3) {

            # JPEG
            if (
                $Bytes[0] -eq 0xFF -and
                $Bytes[1] -eq 0xD8 -and
                $Bytes[2] -eq 0xFF
            ) {
                return 'JPEG'
            }
        }

        if ($Bytes.Length -ge 2) {

            # BMP
            if (
                $Bytes[0] -eq 0x42 -and
                $Bytes[1] -eq 0x4D
            ) {
                return 'BMP'
            }
        }

        if ($Bytes.Length -ge 6) {

            # GIF
            $GifHeader = [System.Text.Encoding]::ASCII.GetString(
                $Bytes,
                0,
                6
            )

            if (
                $GifHeader -eq 'GIF87a' -or
                $GifHeader -eq 'GIF89a'
            ) {
                return 'GIF'
            }
        }

        if ($Bytes.Length -ge 4) {

            # TIFF - Little Endian
            if (
                $Bytes[0] -eq 0x49 -and
                $Bytes[1] -eq 0x49 -and
                $Bytes[2] -eq 0x2A -and
                $Bytes[3] -eq 0x00
            ) {
                return 'TIFF'
            }

            # TIFF - Big Endian
            if (
                $Bytes[0] -eq 0x4D -and
                $Bytes[1] -eq 0x4D -and
                $Bytes[2] -eq 0x00 -and
                $Bytes[3] -eq 0x2A
            ) {
                return 'TIFF'
            }
        }

        return $null
    }

    # ============================================================
    # Native Resource Extraction
    # ============================================================

    if (-not ('ApplicationImageResourceExtractor' -as [type])) {

        Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public class ApplicationImageResourceExtractor
{
    private const uint LOAD_LIBRARY_AS_DATAFILE = 0x00000002;

    private delegate bool EnumResourceTypesDelegate(
        IntPtr hModule,
        IntPtr lpType,
        IntPtr lParam);

    private delegate bool EnumResourceNamesDelegate(
        IntPtr hModule,
        IntPtr lpType,
        IntPtr lpName,
        IntPtr lParam);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr LoadLibraryEx(
        string lpFileName,
        IntPtr hFile,
        uint dwFlags);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool FreeLibrary(
        IntPtr hModule);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool EnumResourceTypes(
        IntPtr hModule,
        EnumResourceTypesDelegate lpEnumFunc,
        IntPtr lParam);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool EnumResourceNames(
        IntPtr hModule,
        IntPtr lpType,
        EnumResourceNamesDelegate lpEnumFunc,
        IntPtr lParam);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr FindResource(
        IntPtr hModule,
        IntPtr lpName,
        IntPtr lpType);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr LoadResource(
        IntPtr hModule,
        IntPtr hResInfo);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr LockResource(
        IntPtr hResData);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint SizeofResource(
        IntPtr hModule,
        IntPtr hResInfo);

    public class ResourceData
    {
        public IntPtr Type;
        public IntPtr Name;
        public byte[] Data;
    }

    public static List<ResourceData> GetResources(string filePath)
    {
        var Results = new List<ResourceData>();

        IntPtr hModule = LoadLibraryEx(
            filePath,
            IntPtr.Zero,
            LOAD_LIBRARY_AS_DATAFILE);

        if (hModule == IntPtr.Zero)
        {
            return Results;
        }

        try
        {
            EnumResourceTypesDelegate TypeCallback =
                delegate(
                    IntPtr module,
                    IntPtr type,
                    IntPtr parameter)
                {
                    EnumResourceNamesDelegate NameCallback =
                        delegate(
                            IntPtr module2,
                            IntPtr type2,
                            IntPtr name,
                            IntPtr parameter2)
                        {
                            IntPtr resourceInfo =
                                FindResource(
                                    module2,
                                    name,
                                    type2);

                            if (resourceInfo == IntPtr.Zero)
                            {
                                return true;
                            }

                            uint size =
                                SizeofResource(
                                    module2,
                                    resourceInfo);

                            if (size == 0)
                            {
                                return true;
                            }

                            IntPtr resourceData =
                                LoadResource(
                                    module2,
                                    resourceInfo);

                            if (resourceData == IntPtr.Zero)
                            {
                                return true;
                            }

                            IntPtr lockedData =
                                LockResource(resourceData);

                            if (lockedData == IntPtr.Zero)
                            {
                                return true;
                            }

                            byte[] buffer =
                                new byte[size];

                            Marshal.Copy(
                                lockedData,
                                buffer,
                                0,
                                (int)size);

                            Results.Add(
                                new ResourceData
                                {
                                    Type = type2,
                                    Name = name,
                                    Data = buffer
                                });

                            return true;
                        };

                    EnumResourceNames(
                        module,
                        type,
                        NameCallback,
                        IntPtr.Zero);

                    return true;
                };

            EnumResourceTypes(
                hModule,
                TypeCallback,
                IntPtr.Zero);
        }
        finally
        {
            FreeLibrary(hModule);
        }

        return Results;
    }
}
"@
    }

    # ============================================================
    # Helper - Extract Image From Byte Array
    # ============================================================

    function Convert-ImageBytesToPng {
        param (
            [Parameter(Mandatory = $true)]
            [byte[]]$Bytes,

            [Parameter(Mandatory = $true)]
            [string]$OutputFile
        )

        $MemoryStream = $null
        $Image = $null

        try {
            $MemoryStream = New-Object System.IO.MemoryStream
            $MemoryStream.Write($Bytes, 0, $Bytes.Length)
            $MemoryStream.Position = 0

            $Image = [System.Drawing.Image]::FromStream(
                $MemoryStream,
                $true,
                $true
            )

            Save-ImageAsPng `
                -Image $Image `
                -OutputFile $OutputFile

            return $true
        }
        catch {
            return $false
        }
        finally {
            if ($Image) {
                $Image.Dispose()
            }

            if ($MemoryStream) {
                $MemoryStream.Dispose()
            }
        }
    }

    # ============================================================
    # Helper - Export Image File
    # ============================================================

    function Export-ImageFile {
        param (
            [Parameter(Mandatory = $true)]
            [string]$ImagePath
        )

        $Image = $null

        try {
            $BaseName = [System.IO.Path]::GetFileNameWithoutExtension(
                $ImagePath
            )

            $OutputFile = Get-UniqueOutputPath `
                -Directory $OutputPath `
                -BaseName $BaseName

            $Image = [System.Drawing.Image]::FromFile($ImagePath)

            Save-ImageAsPng `
                -Image $Image `
                -OutputFile $OutputFile

            $script:ExistingImagesConverted++
            $script:ImagesExported++

            Write-Verbose "Converted image: $ImagePath"
            Write-Verbose "Output: $OutputFile"

            return $true
        }
        catch {
            $script:FilesSkipped++

            Write-Verbose "Unable to convert image: $ImagePath"
            Write-Verbose $_.Exception.Message

            return $false
        }
        finally {
            if ($Image) {
                $Image.Dispose()
            }
        }
    }

    # ============================================================
    # Helper - Extract Embedded Images
    # ============================================================

    function Export-EmbeddedImages {
        param (
            [Parameter(Mandatory = $true)]
            [string]$FilePath
        )

        try {
            $Resources =
                [ApplicationImageResourceExtractor]::GetResources(
                    $FilePath
                )
        }
        catch {
            Write-Verbose "Unable to inspect resources: $FilePath"
            return
        }

        $ResourceNumber = 0

        foreach ($Resource in $Resources) {

            $ResourceNumber++

            $Bytes = $Resource.Data

            if (-not $Bytes -or $Bytes.Length -eq 0) {
                continue
            }

            $ImageType = Get-ImageTypeFromBytes -Bytes $Bytes

            if (-not $ImageType) {
                continue
            }

            $BaseName = [System.IO.Path]::GetFileNameWithoutExtension(
                $FilePath
            )

            $OutputName =
                "$BaseName-Embedded-$ResourceNumber"

            $OutputFile = Get-UniqueOutputPath `
                -Directory $OutputPath `
                -BaseName $OutputName

            if (
                Convert-ImageBytesToPng `
                    -Bytes $Bytes `
                    -OutputFile $OutputFile
            ) {
                $script:EmbeddedImagesExtracted++
                $script:ImagesExported++

                Write-Verbose "Extracted $ImageType image from:"
                Write-Verbose $FilePath
                Write-Verbose "Output: $OutputFile"
            }
        }
    }

    # ============================================================
    # Helper - Extract Windows Icon Resources
    #
    # Icons are NOT saved as ICO files.
    #
    # The icon resource is converted to PNG so it can be used
    # by Intune.
    # ============================================================

    function Export-EmbeddedIconsAsPng {
        param (
            [Parameter(Mandatory = $true)]
            [string]$FilePath
        )

        $IconTempPath = $null

        try {
            $Icon = [System.Drawing.Icon]::ExtractAssociatedIcon(
                $FilePath
            )

            if (-not $Icon) {
                return
            }

            $BaseName = [System.IO.Path]::GetFileNameWithoutExtension(
                $FilePath
            )

            $OutputName = "$BaseName-Icon"

            $OutputFile = Get-UniqueOutputPath `
                -Directory $OutputPath `
                -BaseName $OutputName

            $Bitmap = $null

            try {
                $Bitmap = $Icon.ToBitmap()

                Save-ImageAsPng `
                    -Image $Bitmap `
                    -OutputFile $OutputFile

                $script:IconsConverted++
                $script:ImagesExported++

                Write-Verbose "Converted application icon:"
                Write-Verbose $FilePath
                Write-Verbose "Output: $OutputFile"
            }
            finally {
                if ($Bitmap) {
                    $Bitmap.Dispose()
                }
            }
        }
        catch {
            Write-Verbose "Unable to extract application icon: $FilePath"
            Write-Verbose $_.Exception.Message
        }
    }

    # ============================================================
    # Process Added Applications
    # ============================================================

    if (-not $Comparison.Added) {
        Write-Verbose "No Added applications were found in the JSON file."

        return [PSCustomObject]@{
            DirectoriesScanned       = 0
            FilesScanned             = 0
            ImagesExported           = 0
            ExistingImagesConverted  = 0
            EmbeddedImagesExtracted  = 0
            IconsConverted           = 0
            FilesSkipped             = 0
        }
    }

    foreach ($Entry in $Comparison.Added) {

        if ([string]::IsNullOrWhiteSpace($Entry.FullPath)) {
            continue
        }

        $ApplicationPath = $Entry.FullPath

        if (-not (Test-Path -LiteralPath $ApplicationPath)) {
            Write-Verbose "Application path was not found: $ApplicationPath"
            continue
        }

        try {
            $Directories = @(
                Get-Item -LiteralPath $ApplicationPath
            )
        }
        catch {
            Write-Verbose "Unable to access: $ApplicationPath"
            continue
        }

        foreach ($Directory in $Directories) {

            if (-not $Directory.PSIsContainer) {
                continue
            }

            $DirectoriesScanned++

            Write-Verbose "Scanning directory: $($Directory.FullName)"

            try {
                $Files = Get-ChildItem `
                    -LiteralPath $Directory.FullName `
                    -File `
                    -Recurse `
                    -ErrorAction SilentlyContinue
            }
            catch {
                Write-Verbose "Unable to enumerate: $($Directory.FullName)"
                continue
            }

            foreach ($File in $Files) {

                $FilesScanned++

                $Extension = $File.Extension.ToLowerInvariant()

                # ====================================================
                # Existing Image Files
                # ====================================================

                if ($SupportedImageExtensions -contains $Extension) {

                    Export-ImageFile `
                        -ImagePath $File.FullName

                    continue
                }

                # ====================================================
                # EXE / DLL
                # ====================================================

                if ($ExecutableExtensions -contains $Extension) {

                    # Look for embedded PNG/JPEG/BMP/GIF/TIFF data.
                    Export-EmbeddedImages `
                        -FilePath $File.FullName

                    # Also attempt to obtain the application's
                    # associated Windows icon and convert it to PNG.
                    Export-EmbeddedIconsAsPng `
                        -FilePath $File.FullName

                    continue
                }
            }
        }
    }

    # ============================================================
    # Return Results
    # ============================================================

    return [PSCustomObject]@{
        DirectoriesScanned       = $DirectoriesScanned
        FilesScanned             = $FilesScanned
        ImagesExported           = $ImagesExported
        ExistingImagesConverted  = $ExistingImagesConverted
        EmbeddedImagesExtracted  = $EmbeddedImagesExtracted
        IconsConverted           = $IconsConverted
        FilesSkipped             = $FilesSkipped
    }
}