<#
.SYNOPSIS
Provides QuickSearch filesystem search helpers.
#>

Function GetQuickSearchFilenameWildcardPattern {
    param(
        [string]$Keyword
    )

    if ([string]::IsNullOrWhiteSpace($Keyword)) {
        return ''
    }

    return ('*' + [System.Management.Automation.WildcardPattern]::Escape($Keyword) + '*')
}


Function TestQuickSearchSearchFileAllowed {
    param(
        [System.IO.FileInfo]$File,
        [object]$Config,
        [bool]$UsePolicyFilter
    )

    if (-not $UsePolicyFilter) {
        return $true
    }

    return -not (TestIgnoredFile -File $File -Config $Config)
}


Function TestQuickSearchFileContentMatch {
    param(
        [System.IO.FileInfo]$File,
        [string]$Keyword
    )

    $fileStream = $null
    $reader = $null

    try {
        $fileStream = [System.IO.File]::Open($File.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $reader = [System.IO.StreamReader]::new($fileStream, [System.Text.Encoding]::Default, $true, 4096)

        while ($true) {
            $line = $reader.ReadLine()
            if ($null -eq $line) {
                break
            }

            if ($line.IndexOf($Keyword, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                return $true
            }
        }
    }
    catch {
        return $false
    }
    finally {
        if ($null -ne $reader) {
            $reader.Dispose()
        }
        elseif ($null -ne $fileStream) {
            $fileStream.Dispose()
        }
    }

    return $false
}


Function SearchFiles {
    param(
        [string]$Root,
        [string]$Keyword,
        [bool]$SearchContent,
        [object]$Config = $null
    )

    if ([string]::IsNullOrWhiteSpace($Keyword) -or -not (Test-Path -LiteralPath $Root)) {
        return @()
    }

    $usePolicyFilter = ($null -ne $Config -and $null -ne (Get-Command -Name TestIgnoredFile -ErrorAction SilentlyContinue))

    if ($SearchContent) {
        return @(
            foreach ($file in @(Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction SilentlyContinue)) {
                if (-not (TestQuickSearchSearchFileAllowed -File $file -Config $Config -UsePolicyFilter $usePolicyFilter)) {
                    continue
                }

                if (TestQuickSearchFileContentMatch -File $file -Keyword $Keyword) {
                    $file.FullName
                }
            }
        )
    }

    $keywordPattern = GetQuickSearchFilenameWildcardPattern $Keyword
    return @(
        Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like $keywordPattern } |
            ForEach-Object { $_.FullName }
    )
}