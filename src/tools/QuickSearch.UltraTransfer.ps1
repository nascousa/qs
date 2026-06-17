#requires -Version 7.0
<#
.SYNOPSIS
Builds high-compression text-transfer payloads and restores them.

.DESCRIPTION
Packs a file or folder into a stored ZIP container, compresses that binary container with Brotli at the smallest available size, converts the compressed bytes to Base64 text, and splits the text into the fewest files needed for a 25000-character limit. If OutputPath is omitted in Encode mode, the output is written under tmp/transfer so release/ remains reserved for the lightweight QS payload.

.EXAMPLE
PS> pwsh -NoProfile -File .\src\tools\QuickSearch.UltraTransfer.ps1 -Mode Encode -InputPath .\docs -Force

.EXAMPLE
PS> pwsh -NoProfile -File .\src\tools\QuickSearch.UltraTransfer.ps1 -Mode Decode -InputPath .\tmp\transfer\1.4.23.txt -OutputPath .\tmp\restored -Force
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Encode', 'Decode')]
    [string]$Mode,

    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [string]$OutputPath,

    [string]$BinaryPath,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Script:TextCharacterLimit = 25000

function Resolve-QSOutputFilePath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $parentPath = Split-Path -Parent $Path
    if ([string]::IsNullOrWhiteSpace($parentPath)) {
        return [System.IO.Path]::GetFullPath((Join-Path -Path (Get-Location).Path -ChildPath $Path))
    }

    return [System.IO.Path]::GetFullPath($Path)
}

function Get-QSRepoRoot {
    if ('tools' -eq (Split-Path -Leaf $PSScriptRoot)) {
        return (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    }

    return (Split-Path -Parent $PSScriptRoot)
}

function Get-QSProjectVersion {
    $repoRoot = Get-QSRepoRoot
    $configPath = Join-Path -Path $repoRoot -ChildPath 'src\settings\config.json'
    if (Test-Path -LiteralPath $configPath) {
        try {
            $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
            if ($null -ne $config.Version -and -not [string]::IsNullOrWhiteSpace([string]$config.Version)) {
                return ([string]$config.Version).Trim()
            }
        }
        catch {
            Write-Host "Unable to read QS version from config: $configPath" -ForegroundColor Yellow
        }
    }

    $adcIndexPath = Join-Path -Path $repoRoot -ChildPath '.adc\index.md'
    if (Test-Path -LiteralPath $adcIndexPath) {
        $adcIndexContent = Get-Content -LiteralPath $adcIndexPath -Raw
        $versionMatch = [regex]::Match($adcIndexContent, '(?m)^version:\s*"?([^"\r\n]+)"?\s*$')
        if ($versionMatch.Success) {
            return $versionMatch.Groups[1].Value.Trim()
        }
    }

    return '0.0.0'
}

function Get-QSDefaultOutputPath {
    return (Join-Path -Path (Join-Path -Path (Get-QSRepoRoot) -ChildPath 'tmp\transfer') -ChildPath "$(Get-QSProjectVersion).txt")
}

function Assert-QSCanWriteFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$AllowOverwrite
    )

    if (Test-Path -LiteralPath $Path) {
        $existingItem = Get-Item -LiteralPath $Path
        if ($existingItem.PSIsContainer) {
            throw "Output path is a directory, expected a file: $Path"
        }

        if (-not $AllowOverwrite) {
            throw "Output file already exists. Use -Force to overwrite: $Path"
        }
    }

    $parentPath = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parentPath) -and -not (Test-Path -LiteralPath $parentPath)) {
        New-Item -ItemType Directory -Path $parentPath -Force | Out-Null
    }
}

function Get-QSRelativeArchivePath {
    param(
        [Parameter(Mandatory = $true)][string]$RootPath,
        [Parameter(Mandatory = $true)][string]$ChildPath
    )

    $rootFullPath = [System.IO.Path]::GetFullPath($RootPath).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $childFullPath = [System.IO.Path]::GetFullPath($ChildPath)
    if (-not $childFullPath.StartsWith($rootFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside the source root: $ChildPath"
    }

    return ($childFullPath.Substring($rootFullPath.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) -replace '\\', '/')
}

function Add-QSStoredZipFile {
    param(
        [Parameter(Mandatory = $true)][System.IO.Compression.ZipArchive]$ZipArchive,
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$EntryName
    )

    $fileInfo = Get-Item -LiteralPath $FilePath
    $zipEntry = $ZipArchive.CreateEntry($EntryName, [System.IO.Compression.CompressionLevel]::NoCompression)
    $zipEntry.LastWriteTime = [System.DateTimeOffset]::new($fileInfo.LastWriteTime)
    $entryStream = $zipEntry.Open()
    $fileStream = [System.IO.File]::Open($fileInfo.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $fileStream.CopyTo($entryStream)
    }
    finally {
        $fileStream.Dispose()
        $entryStream.Dispose()
    }
}

function New-QSStoredZipBytes {
    param([Parameter(Mandatory = $true)][string]$SourcePath)

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        throw "Input path not found: $SourcePath"
    }

    $sourceItem = Get-Item -LiteralPath $SourcePath
    $memoryStream = [System.IO.MemoryStream]::new()
    $zipArchive = [System.IO.Compression.ZipArchive]::new($memoryStream, [System.IO.Compression.ZipArchiveMode]::Create, $true)
    try {
        if ($sourceItem.PSIsContainer) {
            $sourceRoot = $sourceItem.FullName.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
            foreach ($sourceChild in @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -Force)) {
                $entryName = Get-QSRelativeArchivePath -RootPath $sourceRoot -ChildPath $sourceChild.FullName
                if ([string]::IsNullOrWhiteSpace($entryName)) { continue }
                if ($sourceChild.PSIsContainer) {
                    if (0 -eq @(Get-ChildItem -LiteralPath $sourceChild.FullName -Force).Count) {
                        [void]$zipArchive.CreateEntry("$entryName/")
                    }
                }
                else {
                    Add-QSStoredZipFile -ZipArchive $zipArchive -FilePath $sourceChild.FullName -EntryName $entryName
                }
            }
        }
        else {
            Add-QSStoredZipFile -ZipArchive $zipArchive -FilePath $sourceItem.FullName -EntryName $sourceItem.Name
        }
    }
    finally {
        $zipArchive.Dispose()
    }

    try { return $memoryStream.ToArray() }
    finally { $memoryStream.Dispose() }
}

function Get-QSBrotliCompressionLevel {
    if ([Enum]::IsDefined([System.IO.Compression.CompressionLevel], 'SmallestSize')) {
        return [System.IO.Compression.CompressionLevel]::SmallestSize
    }

    return [System.IO.Compression.CompressionLevel]::Optimal
}

function Compress-QSBrotliBytes {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    $outputStream = [System.IO.MemoryStream]::new()
    $brotliStream = [System.IO.Compression.BrotliStream]::new($outputStream, (Get-QSBrotliCompressionLevel), $true)
    try { $brotliStream.Write($Bytes, 0, $Bytes.Length) }
    finally { $brotliStream.Dispose() }

    try { return $outputStream.ToArray() }
    finally { $outputStream.Dispose() }
}

function Expand-QSBrotliBytes {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    $inputStream = [System.IO.MemoryStream]::new($Bytes)
    $outputStream = [System.IO.MemoryStream]::new()
    $brotliStream = [System.IO.Compression.BrotliStream]::new($inputStream, [System.IO.Compression.CompressionMode]::Decompress)
    try { $brotliStream.CopyTo($outputStream) }
    finally {
        $brotliStream.Dispose()
        $inputStream.Dispose()
    }

    try { return $outputStream.ToArray() }
    finally { $outputStream.Dispose() }
}

function Get-QSPartNumber {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$BaseName,
        [Parameter(Mandatory = $true)][string]$Extension
    )

    $pattern = '^{0}\.part(\d{{3}}){1}$' -f [regex]::Escape($BaseName), [regex]::Escape($Extension)
    $match = [regex]::Match($Name, $pattern)
    if (-not $match.Success) { return $null }
    return [int]$match.Groups[1].Value
}

function Remove-QSStaleParts {
    param(
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [switch]$AllowOverwrite
    )

    $outputParent = Split-Path -Parent $OutputPath
    $outputBase = [System.IO.Path]::GetFileNameWithoutExtension($OutputPath)
    $outputExt = [System.IO.Path]::GetExtension($OutputPath)
    $staleParts = @()
    if (Test-Path -LiteralPath $outputParent) {
        $staleParts = @(Get-ChildItem -LiteralPath $outputParent -File -Filter "$outputBase.part*$outputExt")
    }

    if ($staleParts.Count -gt 0 -and -not $AllowOverwrite) {
        throw 'Existing part files found. Use -Force to overwrite them.'
    }

    foreach ($stalePart in $staleParts) {
        Remove-Item -LiteralPath $stalePart.FullName -Force
    }
}

function Write-QSSplitBase64 {
    param(
        [Parameter(Mandatory = $true)][string]$Base64Text,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [switch]$AllowOverwrite
    )

    $outputFullPath = Resolve-QSOutputFilePath $OutputPath
    Assert-QSCanWriteFile -Path $outputFullPath -AllowOverwrite:$AllowOverwrite
    Remove-QSStaleParts -OutputPath $outputFullPath -AllowOverwrite:$AllowOverwrite

    $outputParent = Split-Path -Parent $outputFullPath
    $outputBase = [System.IO.Path]::GetFileNameWithoutExtension($outputFullPath)
    $outputExt = [System.IO.Path]::GetExtension($outputFullPath)
    if ([string]::IsNullOrWhiteSpace($outputExt)) { $outputExt = '.txt' }
    $chunkCount = [int][Math]::Ceiling($Base64Text.Length / $Script:TextCharacterLimit)
    $chunkPaths = @()

    for ($chunkIndex = 0; $chunkIndex -lt $chunkCount; $chunkIndex++) {
        if (0 -eq $chunkIndex) {
            $chunkPath = $outputFullPath
        }
        else {
            $chunkPath = Join-Path -Path $outputParent -ChildPath ('{0}.part{1:D3}{2}' -f $outputBase, ($chunkIndex + 1), $outputExt)
        }

        Assert-QSCanWriteFile -Path $chunkPath -AllowOverwrite:$AllowOverwrite
        $chunkPaths += $chunkPath
    }

    for ($chunkIndex = 0; $chunkIndex -lt $chunkCount; $chunkIndex++) {
        $chunkStart = $chunkIndex * $Script:TextCharacterLimit
        $chunkLength = [Math]::Min($Script:TextCharacterLimit, $Base64Text.Length - $chunkStart)
        [System.IO.File]::WriteAllText($chunkPaths[$chunkIndex], $Base64Text.Substring($chunkStart, $chunkLength), [System.Text.Encoding]::ASCII)
    }

    return [PSCustomObject]@{ ChunkCount = $chunkCount; ChunkPaths = $chunkPaths }
}

function Read-QSSplitBase64 {
    param([Parameter(Mandatory = $true)][string]$Path)

    $inputItem = Get-Item -LiteralPath $Path
    $inputBase = [System.IO.Path]::GetFileNameWithoutExtension($inputItem.FullName)
    $inputExt = [System.IO.Path]::GetExtension($inputItem.FullName)
    $partItems = @(Get-ChildItem -LiteralPath $inputItem.DirectoryName -File -Filter "$inputBase.part*$inputExt" |
        ForEach-Object {
            $partNumber = Get-QSPartNumber -Name $_.Name -BaseName $inputBase -Extension $inputExt
            if ($null -ne $partNumber) { [PSCustomObject]@{ Number = $partNumber; Item = $_ } }
        } | Sort-Object Number)

    $expectedPart = 2
    foreach ($partItem in $partItems) {
        if ($partItem.Number -ne $expectedPart) {
            throw "Missing split payload part $expectedPart for $Path"
        }
        $expectedPart++
    }

    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.Append(([System.IO.File]::ReadAllText($inputItem.FullName) -replace '\s+', ''))
    foreach ($partItem in $partItems) {
        [void]$builder.Append(([System.IO.File]::ReadAllText($partItem.Item.FullName) -replace '\s+', ''))
    }

    return $builder.ToString()
}

function Assert-QSSafeZipEntryName {
    param([Parameter(Mandatory = $true)][string]$EntryName)

    if ([string]::IsNullOrWhiteSpace($EntryName) -or [System.IO.Path]::IsPathRooted($EntryName) -or $EntryName.Contains(':')) {
        throw "Unsafe ZIP entry name: $EntryName"
    }

    foreach ($entryPart in @($EntryName -split '[\\/]')) {
        if ('.' -eq $entryPart -or '..' -eq $entryPart) {
            throw "Unsafe ZIP entry name: $EntryName"
        }
    }
}

function Get-QSSafeDestinationPath {
    param(
        [Parameter(Mandatory = $true)][string]$DestinationRoot,
        [Parameter(Mandatory = $true)][string]$EntryName
    )

    Assert-QSSafeZipEntryName -EntryName $EntryName
    $destinationRootFullPath = [System.IO.Path]::GetFullPath($DestinationRoot)
    $destinationRootWithSeparator = $destinationRootFullPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $destinationPath = [System.IO.Path]::GetFullPath((Join-Path -Path $destinationRootFullPath -ChildPath ($EntryName -replace '/', [System.IO.Path]::DirectorySeparatorChar)))
    if (-not $destinationPath.StartsWith($destinationRootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "ZIP entry would extract outside the destination folder: $EntryName"
    }

    return $destinationPath
}

function Expand-QSZipBytesToFolder {
    param(
        [Parameter(Mandatory = $true)][byte[]]$ZipBytes,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [switch]$AllowOverwrite
    )

    if (Test-Path -LiteralPath $DestinationPath) {
        $destinationItem = Get-Item -LiteralPath $DestinationPath
        if (-not $destinationItem.PSIsContainer) { throw "Output path is a file, expected a directory: $DestinationPath" }
    }
    else {
        New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
    }

    $destinationRoot = (Get-Item -LiteralPath $DestinationPath).FullName
    $memoryStream = [System.IO.MemoryStream]::new($ZipBytes)
    $zipArchive = [System.IO.Compression.ZipArchive]::new($memoryStream, [System.IO.Compression.ZipArchiveMode]::Read)
    try {
        foreach ($zipEntry in $zipArchive.Entries) {
            $destinationEntryPath = Get-QSSafeDestinationPath -DestinationRoot $destinationRoot -EntryName $zipEntry.FullName
            if ($zipEntry.FullName.EndsWith('/') -or $zipEntry.FullName.EndsWith('\')) {
                New-Item -ItemType Directory -Path $destinationEntryPath -Force | Out-Null
                continue
            }

            $destinationParent = Split-Path -Parent $destinationEntryPath
            if (-not (Test-Path -LiteralPath $destinationParent)) { New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null }
            if ((Test-Path -LiteralPath $destinationEntryPath) -and -not $AllowOverwrite) { throw "Restored file already exists. Use -Force to overwrite: $destinationEntryPath" }

            $fileMode = if ($AllowOverwrite) { [System.IO.FileMode]::Create } else { [System.IO.FileMode]::CreateNew }
            $entryStream = $zipEntry.Open()
            $outputStream = [System.IO.File]::Open($destinationEntryPath, $fileMode, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            try { $entryStream.CopyTo($outputStream) }
            finally {
                $outputStream.Dispose()
                $entryStream.Dispose()
            }
        }
    }
    finally {
        $zipArchive.Dispose()
        $memoryStream.Dispose()
    }
}

function Invoke-QSUltraEncode {
    $base64OutputPath = $OutputPath
    if ([string]::IsNullOrWhiteSpace($base64OutputPath)) { $base64OutputPath = Get-QSDefaultOutputPath }
    $archiveBytes = New-QSStoredZipBytes -SourcePath $InputPath
    $compressedBytes = Compress-QSBrotliBytes -Bytes $archiveBytes
    if (-not [string]::IsNullOrWhiteSpace($BinaryPath)) {
        $binaryFullPath = Resolve-QSOutputFilePath $BinaryPath
        Assert-QSCanWriteFile -Path $binaryFullPath -AllowOverwrite:$Force
        [System.IO.File]::WriteAllBytes($binaryFullPath, $compressedBytes)
    }

    $base64Text = [Convert]::ToBase64String($compressedBytes)
    $splitOutput = Write-QSSplitBase64 -Base64Text $base64Text -OutputPath $base64OutputPath -AllowOverwrite:$Force
    return [PSCustomObject]@{
        Mode = 'Encode'
        Format = 'StoredZip+Brotli+Base64'
        OutputPath = (Resolve-QSOutputFilePath $base64OutputPath)
        ArchiveBytes = $archiveBytes.Length
        CompressedBytes = $compressedBytes.Length
        Base64Characters = $base64Text.Length
        ChunkCount = $splitOutput.ChunkCount
        ChunkPaths = $splitOutput.ChunkPaths
    }
}

function Invoke-QSUltraDecode {
    if ([string]::IsNullOrWhiteSpace($OutputPath)) { throw 'OutputPath is required in Decode mode.' }
    if (-not (Test-Path -LiteralPath $InputPath)) { throw "Input text file not found: $InputPath" }
    $compressedBytes = [Convert]::FromBase64String((Read-QSSplitBase64 -Path $InputPath))
    if (-not [string]::IsNullOrWhiteSpace($BinaryPath)) {
        $binaryFullPath = Resolve-QSOutputFilePath $BinaryPath
        Assert-QSCanWriteFile -Path $binaryFullPath -AllowOverwrite:$Force
        [System.IO.File]::WriteAllBytes($binaryFullPath, $compressedBytes)
    }

    $archiveBytes = Expand-QSBrotliBytes -Bytes $compressedBytes
    Expand-QSZipBytesToFolder -ZipBytes $archiveBytes -DestinationPath $OutputPath -AllowOverwrite:$Force
    return [PSCustomObject]@{ Mode = 'Decode'; Format = 'StoredZip+Brotli+Base64'; DestinationPath = (Get-Item -LiteralPath $OutputPath).FullName; CompressedBytes = $compressedBytes.Length; ArchiveBytes = $archiveBytes.Length }
}

if ('Encode' -eq $Mode) {
    Invoke-QSUltraEncode
}
else {
    Invoke-QSUltraDecode
}