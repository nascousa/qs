<#
.SYNOPSIS
Provides QuickSearch filesystem search helpers.
#>

$QueryScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'QuickSearch.Query.ps1'
. $QueryScriptPath

Function GetQuickSearchFilenameWildcardPattern {
    param([string]$Keyword)

    if ([string]::IsNullOrWhiteSpace($Keyword)) { return '' }
    return ('*' + [System.Management.Automation.WildcardPattern]::Escape($Keyword) + '*')
}


Function GetQuickSearchSearchConfigValue {
    param(
        [object]$Config,
        [string]$Name,
        [object]$DefaultValue = $null
    )

    if ($null -eq $Config -or [string]::IsNullOrWhiteSpace($Name)) { return $DefaultValue }
    $property = $Config.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return $DefaultValue }
    return $property.Value
}


Function GetQuickSearchIntegerConfigValue {
    param(
        [object]$Config,
        [string]$Name,
        [int]$DefaultValue
    )

    $value = GetQuickSearchSearchConfigValue -Config $Config -Name $Name -DefaultValue $DefaultValue
    $parsedValue = 0
    if ([int]::TryParse([string]$value, [ref]$parsedValue)) { return $parsedValue }
    return $DefaultValue
}


Function GetQuickSearchBooleanConfigValue {
    param(
        [object]$Config,
        [string]$Name,
        [bool]$DefaultValue
    )

    $value = GetQuickSearchSearchConfigValue -Config $Config -Name $Name -DefaultValue $DefaultValue
    if ($value -is [bool]) { return $value }

    $parsedValue = $false
    if ([bool]::TryParse([string]$value, [ref]$parsedValue)) { return $parsedValue }
    return $DefaultValue
}


Function GetQuickSearchUseRipgrep {
    param([object]$Config)

    $explicitValue = GetQuickSearchSearchConfigValue -Config $Config -Name 'UseRipgrepForLiveContentScan' -DefaultValue $null
    if ($null -ne $explicitValue) {
        return GetQuickSearchBooleanConfigValue -Config $Config -Name 'UseRipgrepForLiveContentScan' -DefaultValue $true
    }

    return GetQuickSearchBooleanConfigValue -Config $Config -Name 'UseRipgrep' -DefaultValue $true
}


Function GetQuickSearchMaxSearchResults {
    param([object]$Config)

    $maxResults = GetQuickSearchIntegerConfigValue -Config $Config -Name 'MaxSearchResults' -DefaultValue 200
    return [Math]::Max(0, $maxResults)
}


Function GetQuickSearchMaxContentScanFileSizeBytes {
    param([object]$Config)

    $maxFileSizeMb = GetQuickSearchIntegerConfigValue -Config $Config -Name 'MaxContentScanFileSizeMB' -DefaultValue 10
    if ($maxFileSizeMb -le 0) { return 0L }
    return ([int64]$maxFileSizeMb * 1024L * 1024L)
}


Function TestQuickSearchResultLimitReached {
    param(
        [System.Collections.ArrayList]$Results,
        [int]$MaxResults
    )

    return ($MaxResults -gt 0 -and $Results.Count -ge $MaxResults)
}


Function TestQuickSearchSearchFileAllowed {
    param(
        [System.IO.FileInfo]$File,
        [object]$Config,
        [bool]$UsePolicyFilter,
        [int64]$MaxContentScanFileSizeBytes = 0L
    )

    if ($null -eq $File) { return $false }
    if ($MaxContentScanFileSizeBytes -gt 0 -and $File.Length -gt $MaxContentScanFileSizeBytes) { return $false }
    if (-not $UsePolicyFilter) { return $true }
    return -not (TestIgnoredFile -File $File -Config $Config)
}


Function TestQuickSearchDirectoryAllowed {
    param(
        [string]$DirectoryPath,
        [object]$Config,
        [bool]$UsePolicyFilter
    )

    if (-not $UsePolicyFilter -or [string]::IsNullOrWhiteSpace($DirectoryPath)) { return $true }

    $directoryName = [System.IO.Path]::GetFileName($DirectoryPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar))
    foreach ($ignoredPathPart in @(GetQuickSearchSearchConfigValue -Config $Config -Name 'Ignored' -DefaultValue @())) {
        $ignoredText = ([string]$ignoredPathPart).Trim()
        if ([string]::IsNullOrWhiteSpace($ignoredText)) { continue }
        if ($directoryName.Equals($ignoredText, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
        if ($DirectoryPath -like "*\$ignoredText\*") { return $false }
    }

    return $true
}


Function TestQuickSearchPathWithinRoot {
    param(
        [string]$Path,
        [string]$Root
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Root)) { return $false }

    try {
        $fullPath = [System.IO.Path]::GetFullPath($Path)
        $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        return ($fullPath.Equals($fullRoot, [System.StringComparison]::OrdinalIgnoreCase) -or $fullPath.StartsWith($fullRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase))
    }
    catch {
        return $false
    }
}


Function GetQuickSearchLiveScanRoots {
    param(
        [string]$Root,
        [object]$Config,
        [string]$SelectedType,
        [string]$Scope = ''
    )

    if ([string]::IsNullOrWhiteSpace($Root)) { return @() }

    $selectedTypeText = ([string]$SelectedType).Trim()
    if ([string]::IsNullOrWhiteSpace($selectedTypeText)) { $selectedTypeText = 'ALL' }

    $scopeText = ([string]$Scope).Trim()
    if ([string]::IsNullOrWhiteSpace($scopeText)) {
        $scopeText = [string](GetQuickSearchSearchConfigValue -Config $Config -Name 'LiveContentScanScope' -DefaultValue 'Configured Types')
    }

    if (-not $selectedTypeText.Equals('ALL', [System.StringComparison]::OrdinalIgnoreCase)) { return @($Root) }
    if ($scopeText.Equals('All', [System.StringComparison]::OrdinalIgnoreCase)) { return @($Root) }

    $roots = New-Object System.Collections.ArrayList
    foreach ($typeName in @((GetQuickSearchSearchConfigValue -Config $Config -Name 'Types' -DefaultValue @('TSG', 'SOP', 'CASE')))) {
        $typeText = ([string]$typeName).Trim()
        if ([string]::IsNullOrWhiteSpace($typeText) -or $typeText -in @('ALL', 'TEAM')) { continue }

        $candidateRoot = Join-Path -Path $Root -ChildPath $typeText
        if (Test-Path -LiteralPath $candidateRoot -PathType Container) { [void]$roots.Add($candidateRoot) }
    }

    if ($roots.Count -eq 0) { [void]$roots.Add($Root) }
    return @($roots | ForEach-Object { [string]$_ })
}


Function GetQuickSearchIndexCandidateFiles {
    param(
        [string]$Root,
        [string]$IndexFilePath,
        [object]$Config,
        [bool]$UsePolicyFilter,
        [int64]$MaxContentScanFileSizeBytes
    )

    if ([string]::IsNullOrWhiteSpace($IndexFilePath) -or -not (Test-Path -LiteralPath $IndexFilePath -PathType Leaf)) { return @() }

    $indexData = $null
    try {
        if ($null -ne (Get-Command -Name ReadCachedFileIndexData -CommandType Function -ErrorAction SilentlyContinue)) {
            $indexData = ReadCachedFileIndexData -IndexFilePath $IndexFilePath
        }
        else {
            $indexData = Get-Content -LiteralPath $IndexFilePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        }
    }
    catch {
        return @()
    }

    if ($null -eq $indexData) { return @() }

    $documents = @($indexData.documents)
    if ($documents.Count -eq 0) { $documents = @($indexData) }

    return @(
        foreach ($document in $documents) {
            $path = [string]$document.path
            if ([string]::IsNullOrWhiteSpace($path)) { $path = [string]$document.FilePath }
            if (-not (TestQuickSearchPathWithinRoot -Path $path -Root $Root)) { continue }

            $file = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
            if ($file -isnot [System.IO.FileInfo]) { continue }

            if (TestQuickSearchSearchFileAllowed -File $file -Config $Config -UsePolicyFilter $UsePolicyFilter -MaxContentScanFileSizeBytes $MaxContentScanFileSizeBytes) {
                $file
            }
        }
    )
}


Function SearchQuickSearchContentCandidates {
    param(
        [System.IO.FileInfo[]]$Files,
        [string]$Keyword,
        [int]$MaxResults,
        [object]$Query = $null
    )

    if ($null -eq $Query) { $Query = ConvertToQuickSearchBooleanQuery -Text $Keyword }
    $matchedPaths = New-Object System.Collections.ArrayList
    foreach ($file in @($Files)) {
        if (TestQuickSearchResultLimitReached -Results $matchedPaths -MaxResults $MaxResults) { break }
        if ($file -is [System.IO.FileInfo] -and (TestQuickSearchFileContentMatch -File $file -Keyword $Keyword -Query $Query)) {
            [void]$matchedPaths.Add($file.FullName)
        }
    }

    return @($matchedPaths | ForEach-Object { [string]$_ })
}


Function SearchQuickSearchContentWithPowerShell {
    param(
        [string[]]$Roots,
        [string]$Keyword,
        [object]$Config,
        [bool]$UsePolicyFilter,
        [int64]$MaxContentScanFileSizeBytes,
        [int]$MaxResults,
        [object]$Query = $null
    )

    if ($null -eq $Query) { $Query = ConvertToQuickSearchBooleanQuery -Text $Keyword }
    $matchedPaths = New-Object System.Collections.ArrayList
    foreach ($scanRoot in @($Roots)) {
        if (TestQuickSearchResultLimitReached -Results $matchedPaths -MaxResults $MaxResults) { break }
        if ([string]::IsNullOrWhiteSpace($scanRoot) -or -not (Test-Path -LiteralPath $scanRoot -PathType Container)) { continue }

        $pendingDirectories = New-Object 'System.Collections.Generic.Stack[string]'
        $pendingDirectories.Push($scanRoot)
        while ($pendingDirectories.Count -gt 0) {
            if (TestQuickSearchResultLimitReached -Results $matchedPaths -MaxResults $MaxResults) { break }

            $currentDirectory = $pendingDirectories.Pop()
            try {
                foreach ($childDirectory in [System.IO.Directory]::EnumerateDirectories($currentDirectory)) {
                    if (TestQuickSearchDirectoryAllowed -DirectoryPath $childDirectory -Config $Config -UsePolicyFilter $UsePolicyFilter) {
                        $pendingDirectories.Push($childDirectory)
                    }
                }
            }
            catch {
            }

            try {
                foreach ($filePath in [System.IO.Directory]::EnumerateFiles($currentDirectory)) {
                    if (TestQuickSearchResultLimitReached -Results $matchedPaths -MaxResults $MaxResults) { break }

                    $file = $null
                    try { $file = [System.IO.FileInfo]::new($filePath) }
                    catch { continue }

                    if (-not (TestQuickSearchSearchFileAllowed -File $file -Config $Config -UsePolicyFilter $UsePolicyFilter -MaxContentScanFileSizeBytes $MaxContentScanFileSizeBytes)) { continue }
                    if (TestQuickSearchFileContentMatch -File $file -Keyword $Keyword -Query $Query) { [void]$matchedPaths.Add($file.FullName) }
                }
            }
            catch {
            }
        }
    }

    return @($matchedPaths | ForEach-Object { [string]$_ })
}


Function SearchQuickSearchFilenameWithPowerShell {
    param(
        [string[]]$Roots,
        [string]$Keyword,
        [int]$MaxResults,
        [object]$Config = $null,
        [bool]$UsePolicyFilter = $false,
        [object]$Query = $null
    )

    if ($null -eq $Query) { $Query = ConvertToQuickSearchBooleanQuery -Text $Keyword }
    $matchedPaths = New-Object System.Collections.ArrayList
    foreach ($scanRoot in @($Roots)) {
        if (TestQuickSearchResultLimitReached -Results $matchedPaths -MaxResults $MaxResults) { break }
        if ([string]::IsNullOrWhiteSpace($scanRoot) -or -not (Test-Path -LiteralPath $scanRoot -PathType Container)) { continue }

        $pendingDirectories = New-Object 'System.Collections.Generic.Stack[string]'
        $pendingDirectories.Push($scanRoot)
        while ($pendingDirectories.Count -gt 0) {
            if (TestQuickSearchResultLimitReached -Results $matchedPaths -MaxResults $MaxResults) { break }

            $currentDirectory = $pendingDirectories.Pop()
            try {
                foreach ($childDirectory in [System.IO.Directory]::EnumerateDirectories($currentDirectory)) {
                    if (TestQuickSearchDirectoryAllowed -DirectoryPath $childDirectory -Config $Config -UsePolicyFilter $UsePolicyFilter) {
                        $pendingDirectories.Push($childDirectory)
                    }
                }
            }
            catch {
            }

            try {
                foreach ($filePath in [System.IO.Directory]::EnumerateFiles($currentDirectory)) {
                    if (TestQuickSearchResultLimitReached -Results $matchedPaths -MaxResults $MaxResults) { break }
                    if (TestQuickSearchBooleanQueryText -Query $Query -Text ([System.IO.Path]::GetFileName($filePath))) { [void]$matchedPaths.Add($filePath) }
                }
            }
            catch {
            }
        }
    }

    return @($matchedPaths | ForEach-Object { [string]$_ })
}


Function InvokeQuickSearchRipgrepSearch {
    param(
        [string[]]$Roots,
        [string]$Keyword,
        [object]$Config,
        [int]$MaxResults,
        [object]$Query = $null
    )

    if (-not (GetQuickSearchUseRipgrep -Config $Config)) { return $null }
    if ($null -eq $Query) { $Query = ConvertToQuickSearchBooleanQuery -Text $Keyword }
    $singleTerm = GetQuickSearchSinglePositiveQueryTerm -Query $Query
    if ([string]::IsNullOrWhiteSpace($singleTerm)) { return $null }

    $ripgrepCommand = Get-Command -Name 'rg' -CommandType Application -ErrorAction SilentlyContinue
    if ($null -eq $ripgrepCommand) { return $null }

    $arguments = @('--fixed-strings', '--ignore-case', '--files-with-matches', '--no-heading', '--color', 'never')
    $maxFileSizeMb = GetQuickSearchIntegerConfigValue -Config $Config -Name 'MaxContentScanFileSizeMB' -DefaultValue 10
    if ($maxFileSizeMb -gt 0) { $arguments += @('--max-filesize', "${maxFileSizeMb}M") }

    foreach ($extension in @(ConvertToFileIndexExtensionList -Extensions @(GetQuickSearchSearchConfigValue -Config $Config -Name 'AllowedFileExtNames' -DefaultValue @()))) {
        $arguments += @('--glob', "*$extension")
    }
    foreach ($extension in @(ConvertToFileIndexExtensionList -Extensions @(GetQuickSearchSearchConfigValue -Config $Config -Name 'IgnoredFileExtNames' -DefaultValue @()))) {
        $arguments += @('--glob', "!*$extension")
    }
    foreach ($ignoredPathPart in @(GetQuickSearchSearchConfigValue -Config $Config -Name 'Ignored' -DefaultValue @())) {
        $ignoredText = ([string]$ignoredPathPart).Trim()
        if (-not [string]::IsNullOrWhiteSpace($ignoredText)) { $arguments += @('--glob', "!**/$ignoredText/**") }
    }
    foreach ($ignoredFileName in @(GetQuickSearchSearchConfigValue -Config $Config -Name 'IgnoredFilenames' -DefaultValue @())) {
        $ignoredText = ([string]$ignoredFileName).Trim()
        if (-not [string]::IsNullOrWhiteSpace($ignoredText)) {
            $arguments += @('--glob', "!$ignoredText")
            $arguments += @('--glob', "!$ignoredText.*")
        }
    }

    $existingRoots = @($Roots | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_ -PathType Container) })
    if ($existingRoots.Count -eq 0) { return @() }

    $arguments += @('--', $singleTerm)
    $arguments += $existingRoots

    try {
        if ($MaxResults -gt 0) { return @(& $ripgrepCommand.Source @arguments 2>$null | Select-Object -First $MaxResults) }
        return @(& $ripgrepCommand.Source @arguments 2>$null)
    }
    catch {
        return $null
    }
}


Function TestQuickSearchFileContentMatch {
    param(
        [System.IO.FileInfo]$File,
        [string]$Keyword,
        [object]$Query = $null
    )

    if ($null -eq $Query) { $Query = ConvertToQuickSearchBooleanQuery -Text $Keyword }
    if (-not (TestQuickSearchBooleanQueryHasTerms -Query $Query)) { return $false }
    $singleTerm = GetQuickSearchSinglePositiveQueryTerm -Query $Query
    $queryTerms = @(GetQuickSearchBooleanQueryTerms -Query $Query)
    $termPresence = @{}
    foreach ($term in $queryTerms) {
        $termPresence[([string]$term).ToLowerInvariant()] = $false
    }

    $fileStream = $null
    $reader = $null

    try {
        $fileStream = [System.IO.File]::Open($File.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $reader = [System.IO.StreamReader]::new($fileStream, [System.Text.Encoding]::Default, $true, 4096)

        while ($true) {
            $line = $reader.ReadLine()
            if ($null -eq $line) { break }
            if (-not [string]::IsNullOrWhiteSpace($singleTerm)) {
                if ($line.IndexOf($singleTerm, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
                continue
            }

            foreach ($term in $queryTerms) {
                $key = ([string]$term).ToLowerInvariant()
                if (-not $termPresence[$key] -and (TestQuickSearchTextContainsTerm -Text $line -Term ([string]$term))) {
                    $termPresence[$key] = $true
                }
            }
        }
    }
    catch {
        return $false
    }
    finally {
        if ($null -ne $reader) { $reader.Dispose() }
        elseif ($null -ne $fileStream) { $fileStream.Dispose() }
    }

    return (TestQuickSearchBooleanQueryPresence -Query $Query -Presence $termPresence)
}


Function SearchFiles {
    param(
        [string]$Root,
        [string]$Keyword,
        [bool]$SearchContent,
        [object]$Config = $null,
        [string]$SelectedType = '',
        [string]$IndexFilePath = '',
        [string]$ScanScope = ''
    )

    if ([string]::IsNullOrWhiteSpace($Keyword) -or -not (Test-Path -LiteralPath $Root)) { return @() }

    $query = ConvertToQuickSearchBooleanQuery -Text $Keyword
    if (-not (TestQuickSearchBooleanQueryHasTerms -Query $query)) { return @() }

    $usePolicyFilter = ($null -ne $Config -and $null -ne (Get-Command -Name TestIgnoredFile -ErrorAction SilentlyContinue))
    $maxResults = GetQuickSearchMaxSearchResults -Config $Config
    $maxContentScanFileSizeBytes = GetQuickSearchMaxContentScanFileSizeBytes -Config $Config
    $selectedTypeText = ([string]$SelectedType).Trim()

    if ($SearchContent) {
        $scanRoots = @(GetQuickSearchLiveScanRoots -Root $Root -Config $Config -SelectedType $selectedTypeText -Scope $ScanScope)
        $indexExists = (-not [string]::IsNullOrWhiteSpace($IndexFilePath) -and (Test-Path -LiteralPath $IndexFilePath -PathType Leaf))
        $useTeamIndexCandidates = ($selectedTypeText.Equals('TEAM', [System.StringComparison]::OrdinalIgnoreCase) -and $indexExists)
        if ($useTeamIndexCandidates) {
            $candidateFiles = @(GetQuickSearchIndexCandidateFiles -Root $Root -IndexFilePath $IndexFilePath -Config $Config -UsePolicyFilter $usePolicyFilter -MaxContentScanFileSizeBytes $maxContentScanFileSizeBytes)
            return @(SearchQuickSearchContentCandidates -Files $candidateFiles -Keyword $Keyword -MaxResults $maxResults -Query $query)
        }

        $ripgrepResults = InvokeQuickSearchRipgrepSearch -Roots $scanRoots -Keyword $Keyword -Config $Config -MaxResults $maxResults -Query $query
        if ($null -ne $ripgrepResults) { return @($ripgrepResults | ForEach-Object { [string]$_ }) }

        return @(SearchQuickSearchContentWithPowerShell -Roots $scanRoots -Keyword $Keyword -Config $Config -UsePolicyFilter $usePolicyFilter -MaxContentScanFileSizeBytes $maxContentScanFileSizeBytes -MaxResults $maxResults -Query $query)
    }

    return @(SearchQuickSearchFilenameWithPowerShell -Roots @($Root) -Keyword $Keyword -MaxResults $maxResults -Config $Config -UsePolicyFilter $usePolicyFilter -Query $query)
}
