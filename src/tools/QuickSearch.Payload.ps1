#requires -Version 7.0
<#
.SYNOPSIS
Builds minified UTF-8 Brotli Base64 payloads from QuickSearch PowerShell source.

.DESCRIPTION
This helper is intentionally separate from the Windows PowerShell 5.1-compatible
desktop runtime because BrotliStream is available in PowerShell 7+ on current
.NET runtimes. It removes parser-visible comments, compacts whitespace outside
string literals, encodes the resulting source as UTF-8, compresses it with
Brotli, and returns Base64 text.

.EXAMPLE
PS> pwsh -NoProfile -File .\src\tools\QuickSearch.Payload.ps1 -OutputPath .\quicksearch.payload.txt

.EXAMPLE
PS> pwsh -NoProfile -File .\src\tools\QuickSearch.Payload.ps1 -Decode -Path .\quicksearch.payload.txt -OutputPath .\quicksearch.decoded.ps1
#>

[CmdletBinding()]
param(
    [string[]]$Path,
    [string]$OutputPath,
    [switch]$Decode,
    [string]$Payload,
    [switch]$NoMinify
)

Set-StrictMode -Version Latest

Function TestQuickSearchPayloadTokenNeedsSpace {
    param(
        [string]$LeftText,
        [string]$RightText
    )

    if ([string]::IsNullOrEmpty($LeftText) -or [string]::IsNullOrEmpty($RightText)) {
        return $false
    }

    $leftLast = $LeftText.Substring($LeftText.Length - 1, 1)
    $rightFirst = $RightText.Substring(0, 1)

    if ($leftLast -match '[A-Za-z0-9_]' -and ($rightFirst -eq '[' -or $rightFirst -match '[A-Za-z0-9_''"@$-]')) {
        return $true
    }

    if ($leftLast -in @('$', '?', '}', ')', ']', '"', "'", '`') -and $rightFirst -match '[A-Za-z0-9_@$-]') {
        return $true
    }

    if ($LeftText.StartsWith('-') -and $rightFirst -match '[A-Za-z0-9_@$''"]') {
        return $true
    }

    return $false
}


Function ConvertTo-QuickSearchMinifiedPowerShell {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source
    )

    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseInput($Source, [ref]$tokens, [ref]$parseErrors) | Out-Null

    if (@($parseErrors).Count -gt 0) {
        $messages = @($parseErrors | ForEach-Object { $_.Message }) -join '; '
        throw "PowerShell source cannot be minified because parsing failed: $messages"
    }

    $builder = [System.Text.StringBuilder]::new()
    $previousEndOffset = 0
    $previousText = ''
    $hasPreviousToken = $false
    $skipKinds = @('Comment', 'EndOfInput', 'LineContinuation', 'NewLine')

    foreach ($token in $tokens) {
        if ([string]$token.Kind -in $skipKinds) {
            continue
        }

        $startOffset = $token.Extent.StartOffset
        $endOffset = $token.Extent.EndOffset
        $tokenText = $Source.Substring($startOffset, $endOffset - $startOffset)

        if ($hasPreviousToken -and $startOffset -gt $previousEndOffset) {
            $gap = $Source.Substring($previousEndOffset, $startOffset - $previousEndOffset)
            if ($gap -match '[\r\n]') {
                [void]$builder.Append("`n")
            }
            elseif (TestQuickSearchPayloadTokenNeedsSpace -LeftText $previousText -RightText $tokenText) {
                [void]$builder.Append(' ')
            }
        }

        [void]$builder.Append($tokenText)
        $previousEndOffset = $endOffset
        $previousText = $tokenText
        $hasPreviousToken = $true
    }

    return $builder.ToString().Trim()
}


Function Join-QuickSearchPowerShellSource {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Path
    )

    $builder = [System.Text.StringBuilder]::new()
    foreach ($sourcePath in $Path) {
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "Source file not found: $sourcePath"
        }

        if ($builder.Length -gt 0) {
            [void]$builder.AppendLine()
        }

        [void]$builder.Append((Get-Content -LiteralPath $sourcePath -Raw))
    }

    return $builder.ToString()
}


Function GetQuickSearchBrotliCompressionLevel {
    if ([Enum]::IsDefined([System.IO.Compression.CompressionLevel], 'SmallestSize')) {
        return [System.IO.Compression.CompressionLevel]::SmallestSize
    }

    return [System.IO.Compression.CompressionLevel]::Optimal
}


Function ConvertTo-QuickSearchBrotliBase64Payload {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,
        [switch]$NoMinify
    )

    $payloadSource = $Source
    if (-not $NoMinify) {
        $payloadSource = ConvertTo-QuickSearchMinifiedPowerShell -Source $Source
    }

    $sourceBytes = [System.Text.Encoding]::UTF8.GetBytes($payloadSource)
    $outputStream = [System.IO.MemoryStream]::new()
    $brotliStream = [System.IO.Compression.BrotliStream]::new($outputStream, (GetQuickSearchBrotliCompressionLevel), $true)
    try {
        $brotliStream.Write($sourceBytes, 0, $sourceBytes.Length)
    }
    finally {
        $brotliStream.Dispose()
    }

    return [Convert]::ToBase64String($outputStream.ToArray())
}


Function ConvertFrom-QuickSearchBrotliBase64Payload {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Payload
    )

    $compressedBytes = [Convert]::FromBase64String($Payload.Trim())
    $inputStream = [System.IO.MemoryStream]::new($compressedBytes)
    $brotliStream = [System.IO.Compression.BrotliStream]::new($inputStream, [System.IO.Compression.CompressionMode]::Decompress)
    $outputStream = [System.IO.MemoryStream]::new()
    try {
        $brotliStream.CopyTo($outputStream)
    }
    finally {
        $brotliStream.Dispose()
    }

    return [System.Text.Encoding]::UTF8.GetString($outputStream.ToArray())
}


Function GetQuickSearchRuntimeSourceRoot {
    if ('tools' -eq (Split-Path -Leaf $PSScriptRoot)) {
        return (Split-Path -Parent $PSScriptRoot)
    }

    return $PSScriptRoot
}


Function GetQuickSearchDefaultPayloadSourcePath {
    $sourceRoot = GetQuickSearchRuntimeSourceRoot
    return @(
        (Join-Path -Path $sourceRoot -ChildPath 'QuickSearch.IndexStatus.ps1'),
        (Join-Path -Path $sourceRoot -ChildPath 'QuickSearch.IndexPolicy.ps1'),
        (Join-Path -Path $sourceRoot -ChildPath 'QuickSearch.IndexResume.ps1'),
        (Join-Path -Path $sourceRoot -ChildPath 'QuickSearch.Query.ps1'),
        (Join-Path -Path $sourceRoot -ChildPath 'QuickSearch.Index.ps1'),
        (Join-Path -Path $sourceRoot -ChildPath 'QuickSearch.Search.ps1'),
        (Join-Path -Path $sourceRoot -ChildPath 'QuickSearch.Async.ps1'),
        (Join-Path -Path $sourceRoot -ChildPath 'QuickSearch.Preview.ps1'),
        (Join-Path -Path $sourceRoot -ChildPath 'QuickSearch.Profile.ps1'),
        (Join-Path -Path $sourceRoot -ChildPath 'QuickSearch.Support.ps1'),
        (Join-Path -Path $sourceRoot -ChildPath 'QuickSearch.ps1')
    )
}


Function ConvertTo-QuickSearchPathArray {
    param(
        [string[]]$Value
    )

    return @(
        foreach ($item in @($Value)) {
            if (-not [string]::IsNullOrWhiteSpace($item)) {
                $item
            }
        }
    )
}


if ($MyInvocation.InvocationName -ne '.') {
    if ($Decode) {
        $payloadText = $Payload
        if ([string]::IsNullOrWhiteSpace($payloadText)) {
            $payloadPath = @(ConvertTo-QuickSearchPathArray -Value $Path)
            if (1 -ne $payloadPath.Count) {
                throw 'Provide -Payload or one payload file through -Path when using -Decode.'
            }

            $payloadText = Get-Content -LiteralPath $payloadPath[0] -Raw
        }

        $decodedSource = ConvertFrom-QuickSearchBrotliBase64Payload -Payload $payloadText
        if ([string]::IsNullOrWhiteSpace($OutputPath)) {
            [Console]::Out.WriteLine($decodedSource)
        }
        else {
            Set-Content -LiteralPath $OutputPath -Value $decodedSource -NoNewline -Encoding utf8
        }

        return
    }

    $sourcePaths = @(ConvertTo-QuickSearchPathArray -Value $Path)
    if (0 -eq $sourcePaths.Count) {
        $sourcePaths = @(GetQuickSearchDefaultPayloadSourcePath)
    }

    $sourceText = Join-QuickSearchPowerShellSource -Path $sourcePaths
    $encodedPayload = ConvertTo-QuickSearchBrotliBase64Payload -Source $sourceText -NoMinify:$NoMinify

    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        [Console]::Out.WriteLine($encodedPayload)
    }
    else {
        Set-Content -LiteralPath $OutputPath -Value $encodedPayload -NoNewline -Encoding ascii
    }
}