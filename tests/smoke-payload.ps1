<#
.SYNOPSIS
Validates QuickSearch PowerShell payload minify, Brotli, and Base64 round trips.
#>

#requires -Version 7.0

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

$repoRoot = Split-Path -Parent $PSScriptRoot
$payloadScriptPath = Join-Path -Path $repoRoot -ChildPath 'src\tools\QuickSearch.Payload.ps1'
$payloadEncodeBatchPath = Join-Path -Path $repoRoot -ChildPath 'src\tools\QuickSearch.Payload.Encode.bat'
$payloadDecodeBatchPath = Join-Path -Path $repoRoot -ChildPath 'src\tools\QuickSearch.Payload.Decode.bat'
$mainScriptPath = Join-Path -Path $repoRoot -ChildPath 'src\QuickSearch.ps1'
$indexStatusScriptPath = Join-Path -Path $repoRoot -ChildPath 'src\QuickSearch.IndexStatus.ps1'
$indexPolicyScriptPath = Join-Path -Path $repoRoot -ChildPath 'src\QuickSearch.IndexPolicy.ps1'
$indexResumeScriptPath = Join-Path -Path $repoRoot -ChildPath 'src\QuickSearch.IndexResume.ps1'
$indexScriptPath = Join-Path -Path $repoRoot -ChildPath 'src\QuickSearch.Index.ps1'
$searchScriptPath = Join-Path -Path $repoRoot -ChildPath 'src\QuickSearch.Search.ps1'
$asyncScriptPath = Join-Path -Path $repoRoot -ChildPath 'src\QuickSearch.Async.ps1'
$previewScriptPath = Join-Path -Path $repoRoot -ChildPath 'src\QuickSearch.Preview.ps1'
$profileScriptPath = Join-Path -Path $repoRoot -ChildPath 'src\QuickSearch.Profile.ps1'
$supportScriptPath = Join-Path -Path $repoRoot -ChildPath 'src\QuickSearch.Support.ps1'
$testRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "qs-payload-smoke-$([System.Guid]::NewGuid().ToString('N'))"
$payloadOutputPath = Join-Path -Path $testRoot -ChildPath 'quicksearch.payload.txt'
$decodedOutputPath = Join-Path -Path $testRoot -ChildPath 'quicksearch.decoded.ps1'
$batchPayloadOutputPath = Join-Path -Path $testRoot -ChildPath 'quicksearch.batch.payload.txt'
$batchDecodedOutputPath = Join-Path -Path $testRoot -ChildPath 'quicksearch.batch.decoded.ps1'
$previousBatchNoPause = $env:QS_PAYLOAD_BATCH_NO_PAUSE
$previousBatchOutputPath = $env:QS_PAYLOAD_OUTPUT_PATH
$previousBatchInputPath = $env:QS_PAYLOAD_INPUT_PATH
$previousBatchDecodeOutputPath = $env:QS_PAYLOAD_DECODE_OUTPUT_PATH

. $payloadScriptPath

$sampleSource = @'
# leading comment should be removed
function Test-SamplePayload {
    param([string]$Value)
    $literal = "# keep literal text"
    if ($Value) {
        return "$Value $literal"
    }
    return [PSCustomObject]@{
        Results = @()
    }
}
'@

$minifiedSample = ConvertTo-QuickSearchMinifiedPowerShell -Source $sampleSource
Assert-True -Condition ($minifiedSample -notmatch 'leading comment should be removed') -Message 'Minifier should remove parser-visible comments.'
Assert-True -Condition ($minifiedSample -match '# keep literal text') -Message 'Minifier should preserve comment-looking text inside strings.'
[scriptblock]::Create($minifiedSample) | Out-Null
Assert-True -Condition ($minifiedSample -match 'return \[PSCustomObject\]') -Message 'Minifier should preserve spacing before type literals after return.'

$samplePayload = ConvertTo-QuickSearchBrotliBase64Payload -Source $sampleSource
Assert-True -Condition ($samplePayload -match '^[A-Za-z0-9+/]+={0,2}$') -Message 'Payload should be Base64 text.'
Assert-True -Condition ($minifiedSample -eq (ConvertFrom-QuickSearchBrotliBase64Payload -Payload $samplePayload)) -Message 'Payload should decode to the minified source.'

$quickSearchSource = Join-QuickSearchPowerShellSource -Path @($indexStatusScriptPath, $indexPolicyScriptPath, $indexResumeScriptPath, $indexScriptPath, $searchScriptPath, $asyncScriptPath, $previewScriptPath, $profileScriptPath, $supportScriptPath, $mainScriptPath)
$quickSearchMinified = ConvertTo-QuickSearchMinifiedPowerShell -Source $quickSearchSource
$quickSearchPayload = ConvertTo-QuickSearchBrotliBase64Payload -Source $quickSearchSource
$quickSearchDecoded = ConvertFrom-QuickSearchBrotliBase64Payload -Payload $quickSearchPayload
$quickSearchPlainBase64Length = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($quickSearchMinified)).Length

Assert-True -Condition ($quickSearchDecoded -eq $quickSearchMinified) -Message 'QuickSearch payload should decode to the minified source.'
Assert-True -Condition ($quickSearchPayload.Length -lt $quickSearchPlainBase64Length) -Message 'Brotli Base64 payload should be smaller than UTF-8 Base64 without Brotli.'
[scriptblock]::Create($quickSearchDecoded) | Out-Null

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

    & pwsh -NoProfile -ExecutionPolicy Bypass -File $payloadScriptPath -OutputPath $payloadOutputPath | Out-Null
    Assert-LastCommandSucceeded -Message 'Payload CLI encode mode should complete successfully with default source paths.'
    Assert-True -Condition (Test-Path -LiteralPath $payloadOutputPath) -Message 'Payload CLI should create the encoded output file.'

    & pwsh -NoProfile -ExecutionPolicy Bypass -File $payloadScriptPath -Decode -Path $payloadOutputPath -OutputPath $decodedOutputPath | Out-Null
    Assert-LastCommandSucceeded -Message 'Payload CLI decode mode should complete successfully.'
    Assert-True -Condition ($quickSearchMinified -eq (Get-Content -LiteralPath $decodedOutputPath -Raw)) -Message 'Payload CLI should decode to the minified default source.'

    Assert-True -Condition (Test-Path -LiteralPath $payloadEncodeBatchPath) -Message 'Payload encode batch launcher should exist.'
    Assert-True -Condition (Test-Path -LiteralPath $payloadDecodeBatchPath) -Message 'Payload decode batch launcher should exist.'
    $env:QS_PAYLOAD_BATCH_NO_PAUSE = '1'
    $env:QS_PAYLOAD_OUTPUT_PATH = $batchPayloadOutputPath
    & $env:ComSpec /c "`"$payloadEncodeBatchPath`"" | Out-Null
    Assert-LastCommandSucceeded -Message 'Payload encode batch launcher should complete successfully.'
    Assert-True -Condition (Test-Path -LiteralPath $batchPayloadOutputPath) -Message 'Payload encode batch launcher should create the encoded output file.'
    Assert-True -Condition ($quickSearchMinified -eq (ConvertFrom-QuickSearchBrotliBase64Payload -Payload (Get-Content -LiteralPath $batchPayloadOutputPath -Raw))) -Message 'Payload encode batch launcher output should decode to the minified default source.'

    $env:QS_PAYLOAD_INPUT_PATH = $batchPayloadOutputPath
    $env:QS_PAYLOAD_DECODE_OUTPUT_PATH = $batchDecodedOutputPath
    & $env:ComSpec /c "`"$payloadDecodeBatchPath`"" | Out-Null
    Assert-LastCommandSucceeded -Message 'Payload decode batch launcher should complete successfully.'
    Assert-True -Condition (Test-Path -LiteralPath $batchDecodedOutputPath) -Message 'Payload decode batch launcher should create the decoded output file.'
    Assert-True -Condition ($quickSearchMinified -eq (Get-Content -LiteralPath $batchDecodedOutputPath -Raw)) -Message 'Payload decode batch launcher output should match the minified default source.'

    Write-Host 'QS payload smoke test OK' -ForegroundColor Green
}
finally {
    if ($null -eq $previousBatchNoPause) {
        Remove-Item Env:\QS_PAYLOAD_BATCH_NO_PAUSE -ErrorAction SilentlyContinue
    }
    else {
        $env:QS_PAYLOAD_BATCH_NO_PAUSE = $previousBatchNoPause
    }

    if ($null -eq $previousBatchOutputPath) {
        Remove-Item Env:\QS_PAYLOAD_OUTPUT_PATH -ErrorAction SilentlyContinue
    }
    else {
        $env:QS_PAYLOAD_OUTPUT_PATH = $previousBatchOutputPath
    }

    if ($null -eq $previousBatchInputPath) {
        Remove-Item Env:\QS_PAYLOAD_INPUT_PATH -ErrorAction SilentlyContinue
    }
    else {
        $env:QS_PAYLOAD_INPUT_PATH = $previousBatchInputPath
    }

    if ($null -eq $previousBatchDecodeOutputPath) {
        Remove-Item Env:\QS_PAYLOAD_DECODE_OUTPUT_PATH -ErrorAction SilentlyContinue
    }
    else {
        $env:QS_PAYLOAD_DECODE_OUTPUT_PATH = $previousBatchDecodeOutputPath
    }

    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}