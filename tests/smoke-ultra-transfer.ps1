<#
.SYNOPSIS
Validates QuickSearch high-compression text transfer payloads.
#>

#requires -Version 7.0

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-LastCommandSucceeded {
    param([string]$Message)
    Assert-True -Condition (0 -eq $LASTEXITCODE) -Message $Message
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$ultraScriptPath = Join-Path -Path $repoRoot -ChildPath 'src\tools\QuickSearch.UltraTransfer.ps1'
$textTransferPath = Join-Path -Path $repoRoot -ChildPath 'src\tools\QuickSearch.TextTransfer.ps1'
$testRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "qs-ultra-transfer-smoke-$([System.Guid]::NewGuid().ToString('N'))"
$sourceRoot = Join-Path -Path $testRoot -ChildPath 'source'
$nestedRoot = Join-Path -Path $sourceRoot -ChildPath 'nested'
$ultraOutputPath = Join-Path -Path $testRoot -ChildPath 'ultra.txt'
$zipOutputPath = Join-Path -Path $testRoot -ChildPath 'zip.txt'
$binaryPath = Join-Path -Path $testRoot -ChildPath 'payload.bin'
$ultraRestoreRoot = Join-Path -Path $testRoot -ChildPath 'ultra-restored'
$zipRestoreRoot = Join-Path -Path $testRoot -ChildPath 'zip-restored'
$defaultRepoRoot = Join-Path -Path $testRoot -ChildPath 'default-ultra-repo'
$defaultRepoSrc = Join-Path -Path $defaultRepoRoot -ChildPath 'src'
$defaultRepoTools = Join-Path -Path $defaultRepoSrc -ChildPath 'tools'
$defaultRepoSettings = Join-Path -Path $defaultRepoSrc -ChildPath 'settings'
$defaultUltraScriptPath = Join-Path -Path $defaultRepoTools -ChildPath 'QuickSearch.UltraTransfer.ps1'
$defaultUltraOutputPath = Join-Path -Path $defaultRepoRoot -ChildPath 'tmp\transfer\7.6.5.txt'
$defaultUltraRestoreRoot = Join-Path -Path $testRoot -ChildPath 'default-ultra-restored'
$largeTextPath = Join-Path -Path $sourceRoot -ChildPath 'large.txt'
$nestedTextPath = Join-Path -Path $nestedRoot -ChildPath 'notes.md'
$textLimit = 25000

try {
    New-Item -ItemType Directory -Path $nestedRoot -Force | Out-Null
    $largeText = (1..3000 | ForEach-Object { "repeated operational text alpha beta gamma delta epsilon $_" }) -join "`n"
    $nestedText = ('nested notes quicksearch payload transfer ' * 500).Trim()
    Set-Content -LiteralPath $largeTextPath -Value $largeText -NoNewline
    Set-Content -LiteralPath $nestedTextPath -Value $nestedText -NoNewline

    & pwsh -NoProfile -ExecutionPolicy Bypass -File $ultraScriptPath -Mode Encode -InputPath $sourceRoot -OutputPath $ultraOutputPath -BinaryPath $binaryPath -Force | Out-Null
    Assert-LastCommandSucceeded -Message 'Ultra transfer encode should complete successfully.'
    Assert-True -Condition (Test-Path -LiteralPath $ultraOutputPath) -Message 'Ultra transfer should create a first text chunk.'
    Assert-True -Condition (Test-Path -LiteralPath $binaryPath) -Message 'Ultra transfer should optionally write compressed binary bytes.'

    $ultraParts = @(Get-ChildItem -LiteralPath $testRoot -File | Where-Object { $_.Name -eq 'ultra.txt' -or $_.Name -like 'ultra.part*.txt' } | Sort-Object Name)
    Assert-True -Condition ($ultraParts.Count -ge 1) -Message 'Ultra transfer should create at least one text file.'
    foreach ($ultraPart in $ultraParts) {
        Assert-True -Condition ($ultraPart.Length -le $textLimit) -Message "Ultra transfer text file should stay under 25000 characters: $($ultraPart.Name)"
    }

    & PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File $textTransferPath -Mode Encode -InputPath $sourceRoot -OutputPath $zipOutputPath -Force | Out-Null
    Assert-LastCommandSucceeded -Message 'ZIP/Base64 encode should complete for comparison.'
    $zipParts = @(Get-ChildItem -LiteralPath $testRoot -File | Where-Object { $_.Name -eq 'zip.txt' -or $_.Name -like 'zip.part*.txt' } | Sort-Object Name)
    Assert-True -Condition ($ultraParts.Count -le $zipParts.Count) -Message 'Ultra transfer should use no more text files than ZIP/Base64 for the same source.'

    & pwsh -NoProfile -ExecutionPolicy Bypass -File $ultraScriptPath -Mode Decode -InputPath $ultraOutputPath -OutputPath $ultraRestoreRoot -Force | Out-Null
    Assert-LastCommandSucceeded -Message 'Ultra transfer decode should complete successfully.'
    Assert-True -Condition ($largeText -eq (Get-Content -LiteralPath (Join-Path -Path $ultraRestoreRoot -ChildPath 'large.txt') -Raw)) -Message 'Ultra transfer should restore large text.'
    Assert-True -Condition ($nestedText -eq (Get-Content -LiteralPath (Join-Path -Path $ultraRestoreRoot -ChildPath 'nested\notes.md') -Raw)) -Message 'Ultra transfer should restore nested text.'

    & PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File $textTransferPath -Mode Decode -InputPath $zipOutputPath -OutputPath $zipRestoreRoot -Force | Out-Null
    Assert-LastCommandSucceeded -Message 'ZIP/Base64 comparison payload should decode successfully.'
    Assert-True -Condition ($largeText -eq (Get-Content -LiteralPath (Join-Path -Path $zipRestoreRoot -ChildPath 'large.txt') -Raw)) -Message 'ZIP/Base64 comparison should restore large text.'

    New-Item -ItemType Directory -Path $defaultRepoTools -Force | Out-Null
    New-Item -ItemType Directory -Path $defaultRepoSettings -Force | Out-Null
    Copy-Item -LiteralPath $ultraScriptPath -Destination $defaultUltraScriptPath -Force
    Set-Content -LiteralPath (Join-Path -Path $defaultRepoSettings -ChildPath 'config.json') -Value '{"Version":"7.6.5"}' -NoNewline

    & pwsh -NoProfile -ExecutionPolicy Bypass -File $defaultUltraScriptPath -Mode Encode -InputPath $sourceRoot -Force | Out-Null
    Assert-LastCommandSucceeded -Message 'Ultra transfer encode should write tmp/transfer/<version>.txt when OutputPath is omitted.'
    Assert-True -Condition (Test-Path -LiteralPath $defaultUltraOutputPath) -Message 'Default ultra transfer output should be written under tmp/transfer/<version>.txt.'

    & pwsh -NoProfile -ExecutionPolicy Bypass -File $defaultUltraScriptPath -Mode Decode -InputPath $defaultUltraOutputPath -OutputPath $defaultUltraRestoreRoot -Force | Out-Null
    Assert-LastCommandSucceeded -Message 'Default ultra transfer output should decode successfully.'
    Assert-True -Condition ($largeText -eq (Get-Content -LiteralPath (Join-Path -Path $defaultUltraRestoreRoot -ChildPath 'large.txt') -Raw)) -Message 'Default ultra transfer output should restore large text.'

    Write-Host 'QS ultra transfer smoke test OK' -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}