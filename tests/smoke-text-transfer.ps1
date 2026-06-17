<#
.SYNOPSIS
Validates the QuickSearch ZIP plus Base64 text transfer utility.
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-LastCommandSucceeded {
    param(
        [string]$Message
    )

    Assert-True -Condition (0 -eq $LASTEXITCODE) -Message $Message
}

function Assert-ByteArraysEqual {
    param(
        [byte[]]$Expected,
        [byte[]]$Actual,
        [string]$Message
    )

    Assert-True -Condition ($Expected.Length -eq $Actual.Length) -Message $Message
    for ($byteIndex = 0; $byteIndex -lt $Expected.Length; $byteIndex++) {
        if ($Expected[$byteIndex] -ne $Actual[$byteIndex]) {
            throw $Message
        }
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$toolPath = Join-Path -Path $repoRoot -ChildPath 'src\tools\QuickSearch.TextTransfer.ps1'
$testRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "qs-text-transfer-smoke-$([System.Guid]::NewGuid().ToString('N'))"
$sourceRoot = Join-Path -Path $testRoot -ChildPath 'source'
$nestedRoot = Join-Path -Path $sourceRoot -ChildPath 'nested'
$emptyRoot = Join-Path -Path $sourceRoot -ChildPath 'empty-folder'
$base64Path = Join-Path -Path $testRoot -ChildPath 'payload.b64'
$zipPath = Join-Path -Path $testRoot -ChildPath 'payload.zip'
$restoreRoot = Join-Path -Path $testRoot -ChildPath 'restored'
$restoredZipPath = Join-Path -Path $testRoot -ChildPath 'restored.zip'
$defaultRepoRoot = Join-Path -Path $testRoot -ChildPath 'default-repo'
$defaultRepoSrc = Join-Path -Path $defaultRepoRoot -ChildPath 'src'
$defaultRepoTools = Join-Path -Path $defaultRepoSrc -ChildPath 'tools'
$defaultRepoSettings = Join-Path -Path $defaultRepoSrc -ChildPath 'settings'
$defaultToolPath = Join-Path -Path $defaultRepoTools -ChildPath 'QuickSearch.TextTransfer.ps1'
$defaultBase64Path = Join-Path -Path $defaultRepoRoot -ChildPath 'tmp\transfer\9.8.7.txt'
$defaultRestoreRoot = Join-Path -Path $testRoot -ChildPath 'default-restored'
$splitSourceRoot = Join-Path -Path $testRoot -ChildPath 'split-source'
$splitRestoreRoot = Join-Path -Path $testRoot -ChildPath 'split-restored'
$splitBase64Path = Join-Path -Path $testRoot -ChildPath 'split-payload.txt'
$splitSourceFilePath = Join-Path -Path $splitSourceRoot -ChildPath 'large.txt'
$splitChunkLimit = 25000

try {
    New-Item -ItemType Directory -Path $nestedRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $emptyRoot -Force | Out-Null

    $documentText = ('alpha beta gamma delta ' * 200).Trim()
    $notesText = ('nested notes and repeated transfer text ' * 120).Trim()
    Set-Content -LiteralPath (Join-Path -Path $sourceRoot -ChildPath 'document.txt') -Value $documentText -NoNewline
    Set-Content -LiteralPath (Join-Path -Path $nestedRoot -ChildPath 'notes.md') -Value $notesText -NoNewline

    & PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File $toolPath -Mode Encode -InputPath $sourceRoot -OutputPath $base64Path -ZipPath $zipPath -Force | Out-Null
    Assert-LastCommandSucceeded -Message 'Encode mode should complete successfully.'

    Assert-True -Condition (Test-Path -LiteralPath $base64Path) -Message 'Base64 output file should be created.'
    Assert-True -Condition (Test-Path -LiteralPath $zipPath) -Message 'Optional ZIP output file should be created.'

    $base64Text = Get-Content -LiteralPath $base64Path -Raw
    $zipBytesFromBase64 = [System.Convert]::FromBase64String($base64Text)
    $zipBytesFromFile = [System.IO.File]::ReadAllBytes($zipPath)
    Assert-ByteArraysEqual -Expected $zipBytesFromFile -Actual $zipBytesFromBase64 -Message 'Base64 text should decode to the same ZIP bytes written by -ZipPath.'
    Assert-True -Condition ($base64Text.Length -lt ($documentText.Length + $notesText.Length)) -Message 'Compressed Base64 should be smaller than the repetitive source text.'

    & PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File $toolPath -Mode Decode -InputPath $base64Path -OutputPath $restoreRoot -ZipPath $restoredZipPath -Force | Out-Null
    Assert-LastCommandSucceeded -Message 'Decode mode should complete successfully.'

    Assert-True -Condition (Test-Path -LiteralPath $restoredZipPath) -Message 'Decode mode should write the optional restored ZIP.'
    Assert-ByteArraysEqual -Expected ([System.IO.File]::ReadAllBytes($zipPath)) -Actual ([System.IO.File]::ReadAllBytes($restoredZipPath)) -Message 'Restored ZIP should match the original ZIP bytes.'
    Assert-True -Condition ($documentText -eq (Get-Content -LiteralPath (Join-Path -Path $restoreRoot -ChildPath 'document.txt') -Raw)) -Message 'Decoded document content should match the source.'
    Assert-True -Condition ($notesText -eq (Get-Content -LiteralPath (Join-Path -Path $restoreRoot -ChildPath 'nested\notes.md') -Raw)) -Message 'Decoded nested file content should match the source.'
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path -Path $restoreRoot -ChildPath 'empty-folder')) -Message 'Empty folders should be preserved.'

    New-Item -ItemType Directory -Path $defaultRepoTools -Force | Out-Null
    New-Item -ItemType Directory -Path $defaultRepoSettings -Force | Out-Null
    Copy-Item -LiteralPath $toolPath -Destination $defaultToolPath -Force
    Set-Content -LiteralPath (Join-Path -Path $defaultRepoSettings -ChildPath 'config.json') -Value '{"Version":"9.8.7"}' -NoNewline

    & PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File $defaultToolPath -Mode Encode -InputPath $sourceRoot -Force | Out-Null
    Assert-LastCommandSucceeded -Message 'Encode mode should write tmp/transfer/<version>.txt when OutputPath is omitted.'
    Assert-True -Condition (Test-Path -LiteralPath $defaultBase64Path) -Message 'Default Base64 output should be written under tmp/transfer/<version>.txt.'

    & PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File $defaultToolPath -Mode Decode -InputPath $defaultBase64Path -OutputPath $defaultRestoreRoot -Force | Out-Null
    Assert-LastCommandSucceeded -Message 'Default transfer Base64 output should decode successfully.'
    Assert-True -Condition ($documentText -eq (Get-Content -LiteralPath (Join-Path -Path $defaultRestoreRoot -ChildPath 'document.txt') -Raw)) -Message 'Default transfer output should restore document content.'

    New-Item -ItemType Directory -Path $splitSourceRoot -Force | Out-Null
    $splitText = ((1..5000 | ForEach-Object { [System.Guid]::NewGuid().ToString('N') }) -join "`n")
    Set-Content -LiteralPath $splitSourceFilePath -Value $splitText -NoNewline

    & PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File $toolPath -Mode Encode -InputPath $splitSourceRoot -OutputPath $splitBase64Path -Force | Out-Null
    Assert-LastCommandSucceeded -Message 'Encode mode should split Base64 output larger than 25000 characters.'
    Assert-True -Condition (Test-Path -LiteralPath $splitBase64Path) -Message 'Split output manifest should be created.'
    Assert-True -Condition ((Get-Item -LiteralPath $splitBase64Path).Length -le $splitChunkLimit) -Message 'Split output manifest should stay under 25000 characters.'

    $splitManifest = Get-Content -LiteralPath $splitBase64Path -Raw | ConvertFrom-Json
    Assert-True -Condition ('QS.TextTransfer.SplitBase64.v1' -eq $splitManifest.format) -Message 'Split manifest should use the expected format marker.'
    Assert-True -Condition ([int]$splitManifest.chunkCount -gt 1) -Message 'Split output should produce multiple chunks for large payloads.'

    foreach ($splitChunkName in @($splitManifest.chunks)) {
        $splitChunkPath = Join-Path -Path (Split-Path -Parent $splitBase64Path) -ChildPath ([string]$splitChunkName)
        Assert-True -Condition (Test-Path -LiteralPath $splitChunkPath) -Message "Split chunk should exist: $splitChunkPath"
        Assert-True -Condition ((Get-Item -LiteralPath $splitChunkPath).Length -le $splitChunkLimit) -Message "Split chunk should stay under 25000 characters: $splitChunkPath"
    }

    & PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File $toolPath -Mode Decode -InputPath $splitBase64Path -OutputPath $splitRestoreRoot -Force | Out-Null
    Assert-LastCommandSucceeded -Message 'Decode mode should restore from a split manifest.'
    Assert-True -Condition ($splitText -eq (Get-Content -LiteralPath (Join-Path -Path $splitRestoreRoot -ChildPath 'large.txt') -Raw)) -Message 'Split manifest decode should restore large text content.'

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $maliciousZipPath = Join-Path -Path $testRoot -ChildPath 'malicious.zip'
    $maliciousBase64Path = Join-Path -Path $testRoot -ChildPath 'malicious.b64'
    $maliciousRestoreRoot = Join-Path -Path $testRoot -ChildPath 'malicious-restore'
    $maliciousFileStream = [System.IO.File]::Open($maliciousZipPath, [System.IO.FileMode]::Create)
    $maliciousArchive = [System.IO.Compression.ZipArchive]::new($maliciousFileStream, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        $maliciousEntry = $maliciousArchive.CreateEntry('../escape.txt')
        $maliciousEntryStream = $maliciousEntry.Open()
        $maliciousWriter = [System.IO.StreamWriter]::new($maliciousEntryStream)
        try {
            $maliciousWriter.Write('should not extract')
        }
        finally {
            $maliciousWriter.Dispose()
            $maliciousEntryStream.Dispose()
        }
    }
    finally {
        $maliciousArchive.Dispose()
        $maliciousFileStream.Dispose()
    }

    [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($maliciousZipPath)) | Set-Content -LiteralPath $maliciousBase64Path -NoNewline
    $maliciousOutputPath = Join-Path -Path $testRoot -ChildPath 'malicious-output.txt'
    $maliciousErrorPath = Join-Path -Path $testRoot -ChildPath 'malicious-error.txt'
    $maliciousArguments = @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $toolPath,
        '-Mode',
        'Decode',
        '-InputPath',
        $maliciousBase64Path,
        '-OutputPath',
        $maliciousRestoreRoot,
        '-Force'
    )
    $maliciousProcess = Start-Process -FilePath 'PowerShell.exe' -ArgumentList $maliciousArguments -NoNewWindow -Wait -PassThru -RedirectStandardOutput $maliciousOutputPath -RedirectStandardError $maliciousErrorPath
    Assert-True -Condition (0 -ne $maliciousProcess.ExitCode) -Message 'Decode mode should reject path traversal ZIP entries.'
    Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path -Path $testRoot -ChildPath 'escape.txt'))) -Message 'Unsafe ZIP entries should not write outside the destination folder.'

    Write-Host 'QS text transfer smoke test OK' -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}