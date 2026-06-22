<#
.SYNOPSIS
Builds and searches QuickSearch TEAM file indexes.
#>

$IndexStatusScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'QuickSearch.IndexStatus.ps1'
. $IndexStatusScriptPath
$QueryScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'QuickSearch.Query.ps1'
. $QueryScriptPath
$IndexPolicyScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'QuickSearch.IndexPolicy.ps1'
. $IndexPolicyScriptPath
$IndexResumeScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'QuickSearch.IndexResume.ps1'
. $IndexResumeScriptPath
$IndexShardScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'QuickSearch.IndexShard.ps1'
. $IndexShardScriptPath

Function GetFileIndexPropertyValue {
    param(
        [object]$Value,
        [string]$Name
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace($Name)) {
        return $null
    }

    if ($Value -is [System.Collections.IDictionary]) {
        if ($Value.Contains($Name)) {
            return $Value[$Name]
        }
        return $null
    }

    $property = $Value.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}


Function GetWildcardContainsPattern {
    param(
        [string]$Value
    )

    return "*$([System.Management.Automation.WildcardPattern]::Escape($Value))*"
}


Function GetFileIndexCache {
    $cacheVariable = Get-Variable -Name 'QuickSearchFileIndexCache' -Scope Script -ErrorAction SilentlyContinue
    if ($null -eq $cacheVariable -or $null -eq $cacheVariable.Value) {
        $script:QuickSearchFileIndexCache = @{}
    }

    return $script:QuickSearchFileIndexCache
}


Function ReadCachedFileIndexData {
    param(
        [string]$IndexFilePath
    )

    if ([string]::IsNullOrWhiteSpace($IndexFilePath) -or -not (Test-Path -LiteralPath $IndexFilePath -PathType Leaf)) {
        return $null
    }

    $indexFile = Get-Item -LiteralPath $IndexFilePath -ErrorAction Stop
    $cacheKey = $indexFile.FullName.ToLowerInvariant()
    $cache = GetFileIndexCache
    $cacheEntry = $null
    if ($cache.ContainsKey($cacheKey)) {
        $cacheEntry = $cache[$cacheKey]
    }

    if ($null -ne $cacheEntry -and $cacheEntry.Length -eq $indexFile.Length -and $cacheEntry.LastWriteUtcTicks -eq $indexFile.LastWriteTimeUtc.Ticks) {
        return $cacheEntry.Data
    }

    $indexData = Get-Content -LiteralPath $indexFile.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $cache[$cacheKey] = [PSCustomObject]@{
        Length = $indexFile.Length
        LastWriteUtcTicks = $indexFile.LastWriteTimeUtc.Ticks
        Data = $indexData
    }

    return $indexData
}


Function TestEnglishWord {
    param(
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Length -le 2) {
        return $false
    }

    return $Value -match '^[a-zA-Z]+$'
}


Function GetSearchTermsFromText {
    param(
        [string]$Text
    )

    $terms = New-Object System.Collections.ArrayList
    $seenTerms = @{}

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return @()
    }

    $matches = [regex]::Matches($Text, '[A-Za-z0-9]+')
    foreach ($match in $matches) {
        $term = $match.Value.ToLowerInvariant()
        if ($term.Length -le 1 -or $seenTerms.ContainsKey($term)) {
            continue
        }

        $seenTerms[$term] = $true
        [void]$terms.Add($term)
    }

    return @($terms)
}


Function GetTopWords {
    param(
        [string]$FilePath,
        [int]$Count = 10
    )

    $tagCounts = [ordered]@{}
    $wordCounts = @{}
    $maxWordLength = 64
    $maxUniqueWords = 50000
    $fileStream = $null
    $reader = $null

    try {
        $fileStream = [System.IO.File]::Open($FilePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $reader = [System.IO.StreamReader]::new($fileStream, [System.Text.Encoding]::Default, $true, 4096)

        $buffer = [char[]]::new(8192)
        $wordBuilder = New-Object System.Text.StringBuilder
        $wordTooLong = $false

        while (($charactersRead = $reader.Read($buffer, 0, $buffer.Length)) -gt 0) {
            for ($bufferIndex = 0; $bufferIndex -lt $charactersRead; $bufferIndex++) {
                $characterCode = [int][char]$buffer[$bufferIndex]
                $isAsciiLetter = (65 -le $characterCode -and $characterCode -le 90) -or (97 -le $characterCode -and $characterCode -le 122)

                if ($isAsciiLetter) {
                    if (-not $wordTooLong) {
                        if ($wordBuilder.Length -lt $maxWordLength) {
                            [void]$wordBuilder.Append([char]$characterCode)
                        }
                        else {
                            [void]$wordBuilder.Clear()
                            $wordTooLong = $true
                        }
                    }
                    continue
                }

                if (-not $wordTooLong -and $wordBuilder.Length -gt 0) {
                    AddFileIndexWordCount -WordCounts $wordCounts -Word $wordBuilder.ToString() -MaxUniqueWords $maxUniqueWords
                }

                if ($wordBuilder.Length -gt 0) {
                    [void]$wordBuilder.Clear()
                }
                $wordTooLong = $false
            }
        }

        if (-not $wordTooLong -and $wordBuilder.Length -gt 0) {
            AddFileIndexWordCount -WordCounts $wordCounts -Word $wordBuilder.ToString() -MaxUniqueWords $maxUniqueWords
        }
    }
    catch {
        return $tagCounts
    }
    finally {
        if ($null -ne $reader) {
            $reader.Dispose()
        }
        elseif ($null -ne $fileStream) {
            $fileStream.Dispose()
        }
    }

    $topWords = $wordCounts.GetEnumerator() |
        Sort-Object -Property @{ Expression = 'Value'; Descending = $true }, @{ Expression = 'Key'; Descending = $false } |
        Select-Object -First $Count

    foreach ($entry in $topWords) {
        $tagCounts[$entry.Key] = $entry.Value
    }

    return $tagCounts
}


Function AddFileIndexWordCount {
    param(
        [hashtable]$WordCounts,
        [string]$Word,
        [int]$MaxUniqueWords
    )

    if (-not (TestEnglishWord $Word)) {
        return
    }

    $normalizedWord = $Word.ToLowerInvariant()
    if ($WordCounts.ContainsKey($normalizedWord)) {
        $WordCounts[$normalizedWord] = $WordCounts[$normalizedWord] + 1
    }
    elseif ($WordCounts.Count -lt $MaxUniqueWords) {
        $WordCounts[$normalizedWord] = 1
    }
}


Function ConvertToFileIndexTagCounts {
    param(
        [object]$TagCounts,
        [object[]]$Tags
    )

    $converted = [ordered]@{}

    if ($null -ne $TagCounts) {
        if ($TagCounts -is [System.Collections.IDictionary]) {
            foreach ($key in $TagCounts.Keys) {
                $normalizedKey = [string]$key
                if ([string]::IsNullOrWhiteSpace($normalizedKey)) {
                    continue
                }

                $countValue = 0
                [void][int]::TryParse([string]$TagCounts[$key], [ref]$countValue)
                if ($countValue -lt 1) {
                    $countValue = 1
                }
                $converted[$normalizedKey.ToLowerInvariant()] = $countValue
            }
        }
        else {
            foreach ($property in @($TagCounts.PSObject.Properties)) {
                $countValue = 0
                [void][int]::TryParse([string]$property.Value, [ref]$countValue)
                if ($countValue -lt 1) {
                    $countValue = 1
                }
                $converted[$property.Name.ToLowerInvariant()] = $countValue
            }
        }
    }

    if (0 -eq $converted.Count) {
        foreach ($tag in @($Tags)) {
            $normalizedTag = [string]$tag
            if ([string]::IsNullOrWhiteSpace($normalizedTag)) {
                continue
            }

            $normalizedTag = $normalizedTag.ToLowerInvariant()
            if (-not $converted.Contains($normalizedTag)) {
                $converted[$normalizedTag] = 1
            }
        }
    }

    return $converted
}


Function TestIgnoredFile {
    param(
        [System.IO.FileInfo]$File,
        [object]$Config
    )

    $ignoredFileNames = @($Config.IgnoredFilenames)
    $ignoredFileExtNames = @($Config.IgnoredFileExtNames)
    $ignoredPathParts = @($Config.Ignored)

    if ($File.Name -in $ignoredFileNames -or $File.BaseName -in $ignoredFileNames) {
        return $true
    }

    if ($File.Extension -in $ignoredFileExtNames) {
        return $true
    }

    if (-not (TestFileIndexExtensionAllowed -File $File -Config $Config)) {
        return $true
    }

    foreach ($ignoredPathPart in $ignoredPathParts) {
        if (-not [string]::IsNullOrWhiteSpace($ignoredPathPart) -and $File.FullName -like "*\$ignoredPathPart\*") {
            return $true
        }
    }

    return $false
}


Function AddFileIndexTerm {
    param(
        [System.Collections.IDictionary]$Terms,
        [string]$Term,
        [int]$DocumentId
    )

    if ([string]::IsNullOrWhiteSpace($Term)) {
        return
    }

    $normalizedTerm = $Term.ToLowerInvariant()
    if ($normalizedTerm.Length -le 1) {
        return
    }

    if (-not $Terms.Contains($normalizedTerm)) {
        $Terms[$normalizedTerm] = New-Object System.Collections.ArrayList
    }

    if (-not $Terms[$normalizedTerm].Contains($DocumentId)) {
        [void]$Terms[$normalizedTerm].Add($DocumentId)
    }
}


Function AddFileIndexDocumentTerms {
    param(
        [System.Collections.IDictionary]$Terms,
        [object]$Document
    )

    $documentId = [int](GetFileIndexPropertyValue -Value $Document -Name 'id')
    $documentName = [string](GetFileIndexPropertyValue -Value $Document -Name 'name')
    $documentPath = [string](GetFileIndexPropertyValue -Value $Document -Name 'path')

    foreach ($term in @(GetSearchTermsFromText $documentName)) {
        AddFileIndexTerm -Terms $Terms -Term $term -DocumentId $documentId
    }

    foreach ($term in @(GetSearchTermsFromText $documentPath)) {
        AddFileIndexTerm -Terms $Terms -Term $term -DocumentId $documentId
    }

    foreach ($tag in @((GetFileIndexPropertyValue -Value $Document -Name 'tags'))) {
        AddFileIndexTerm -Terms $Terms -Term ([string]$tag) -DocumentId $documentId
    }
}


Function GetFileIndexDocuments {
    param(
        [object]$IndexData
    )

    $schemaVersion = GetFileIndexPropertyValue -Value $IndexData -Name 'schemaVersion'
    if ($schemaVersion -eq 2) {
        return @((GetFileIndexPropertyValue -Value $IndexData -Name 'documents'))
    }

    return @($IndexData)
}


Function GetReusableFileIndexDocumentsByPath {
    param(
        [string]$IndexFilePath
    )

    return GetFileIndexReusableDocumentPathMap -IndexFilePath $IndexFilePath
}


Function ConvertFileIndexTimestampToUtcTicks {
    param(
        [object]$Value
    )

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [datetime]) {
        return $Value.ToUniversalTime().Ticks
    }

    $timestampText = [string]$Value
    if ([string]::IsNullOrWhiteSpace($timestampText)) {
        return $null
    }

    $timestamp = [datetime]::MinValue
    if ([datetime]::TryParse($timestampText, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$timestamp)) {
        return $timestamp.ToUniversalTime().Ticks
    }

    return $null
}


Function TestReusableFileIndexDocument {
    param(
        [object]$Document,
        [System.IO.FileInfo]$File
    )

    if ($null -eq $Document -or $null -eq $File) {
        return $false
    }

    $indexedSize = 0L
    [void][int64]::TryParse([string](GetFileIndexPropertyValue -Value $Document -Name 'sizeInBytes'), [ref]$indexedSize)
    if ($indexedSize -ne $File.Length) {
        return $false
    }

    $currentLastModifiedTicks = $File.LastWriteTime.ToUniversalTime().Ticks
    $indexedLastModifiedTicks = ConvertFileIndexTimestampToUtcTicks -Value (GetFileIndexPropertyValue -Value $Document -Name 'lastModified')
    if ($null -ne $indexedLastModifiedTicks -and [int64]$indexedLastModifiedTicks -eq $currentLastModifiedTicks) {
        return $true
    }

    $currentLastWriteUtcTicks = $File.LastWriteTimeUtc.Ticks
    $indexedLastWriteUtcTicks = ConvertFileIndexTimestampToUtcTicks -Value (GetFileIndexPropertyValue -Value $Document -Name 'lastWriteUtc')
    return ($null -ne $indexedLastWriteUtcTicks -and [int64]$indexedLastWriteUtcTicks -eq $currentLastWriteUtcTicks)
}


Function NewStringSet {
    return @{}
}


Function AddStringSetValue {
    param(
        [hashtable]$Set,
        [object]$Value
    )

    if ($null -eq $Value) {
        return
    }

    $key = [string]$Value
    if ([string]::IsNullOrWhiteSpace($key)) {
        return
    }

    $Set[$key] = $true
}


Function AddStringSetValues {
    param(
        [hashtable]$Set,
        [object]$Values
    )

    foreach ($value in @($Values)) {
        AddStringSetValue -Set $Set -Value $value
    }
}


Function IntersectStringSets {
    param(
        [hashtable]$Left,
        [hashtable]$Right
    )

    $intersection = NewStringSet
    foreach ($key in $Left.Keys) {
        if ($Right.ContainsKey($key)) {
            $intersection[$key] = $true
        }
    }

    return $intersection
}


Function CopyStringSet {
    param([hashtable]$Set)

    $copy = NewStringSet
    foreach ($key in $Set.Keys) {
        $copy[$key] = $true
    }

    return $copy
}


Function RemoveStringSetValues {
    param(
        [hashtable]$Set,
        [hashtable]$Values
    )

    foreach ($key in $Values.Keys) {
        if ($Set.ContainsKey($key)) {
            $Set.Remove($key)
        }
    }
}


Function AddStringSetKeys {
    param(
        [hashtable]$Set,
        [hashtable]$Values
    )

    foreach ($key in $Values.Keys) {
        $Set[$key] = $true
    }
}


Function GetFileIndexDocumentSearchText {
    param([object]$Document)

    $parts = New-Object System.Collections.ArrayList
    foreach ($propertyName in @('name', 'Filename', 'path', 'FilePath')) {
        $value = [string](GetFileIndexPropertyValue -Value $Document -Name $propertyName)
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            [void]$parts.Add($value)
        }
    }

    foreach ($tag in @((GetFileIndexPropertyValue -Value $Document -Name 'tags'))) {
        if (-not [string]::IsNullOrWhiteSpace([string]$tag)) {
            [void]$parts.Add([string]$tag)
        }
    }

    $tagCounts = GetFileIndexPropertyValue -Value $Document -Name 'tagCounts'
    if ($null -ne $tagCounts) {
        foreach ($property in @($tagCounts.PSObject.Properties)) {
            if (-not [string]::IsNullOrWhiteSpace($property.Name)) {
                [void]$parts.Add($property.Name)
            }
        }
    }

    return (@($parts) -join ' ')
}


Function GetFileIndexTermProperties {
    param(
        [object]$Terms
    )

    if ($null -eq $Terms) {
        return @()
    }

    if ($Terms -is [System.Collections.IDictionary]) {
        return @(
            foreach ($key in $Terms.Keys) {
                [PSCustomObject]@{
                    Name = [string]$key
                    Value = $Terms[$key]
                }
            }
        )
    }

    return @($Terms.PSObject.Properties)
}


Function GetFileIndexTermValue {
    param(
        [object]$Terms,
        [string]$Term
    )

    if ($null -eq $Terms -or [string]::IsNullOrWhiteSpace($Term)) {
        return @()
    }

    if ($Terms -is [System.Collections.IDictionary]) {
        if ($Terms.Contains($Term)) {
            return @($Terms[$Term])
        }
        return @()
    }

    $property = $Terms.PSObject.Properties[$Term]
    if ($null -eq $property) {
        return @()
    }

    return @($property.Value)
}


Function GetFileIndexTermDocumentIdSet {
    param(
        [object]$Terms,
        [string]$Term
    )

    $documentIds = NewStringSet
    if ([string]::IsNullOrWhiteSpace($Term)) {
        return $documentIds
    }

    $normalizedTerm = $Term.ToLowerInvariant()
    AddStringSetValues -Set $documentIds -Values (GetFileIndexTermValue -Terms $Terms -Term $normalizedTerm)

    $termPattern = GetWildcardContainsPattern $normalizedTerm
    foreach ($property in @(GetFileIndexTermProperties -Terms $Terms)) {
        if ([string]$property.Name -eq $normalizedTerm) {
            continue
        }

        if ($property.Name -like $termPattern) {
            AddStringSetValues -Set $documentIds -Values $property.Value
        }
    }

    return $documentIds
}


Function SearchInvertedFileIndex {
    param(
        [object]$IndexData,
        [string]$Keyword,
        [int]$MaxResults = 0
    )

    $documents = @((GetFileIndexPropertyValue -Value $IndexData -Name 'documents'))
    $terms = GetFileIndexPropertyValue -Value $IndexData -Name 'terms'
    if (0 -eq $documents.Count -or $null -eq $terms) {
        return @()
    }

    $query = ConvertToQuickSearchBooleanQuery -Text $Keyword
    if (-not (TestQuickSearchBooleanQueryHasTerms -Query $query)) { return @() }

    $allDocumentIds = NewStringSet
    foreach ($document in $documents) {
        AddStringSetValue -Set $allDocumentIds -Value ([string](GetFileIndexPropertyValue -Value $document -Name 'id'))
    }

    $candidateIds = NewStringSet
    foreach ($group in @($query.Groups)) {
        $matchingIds = $null
        foreach ($queryTerm in @($group.Includes)) {
            $termIds = GetFileIndexTermDocumentIdSet -Terms $terms -Term ([string]$queryTerm)
            if ($null -eq $matchingIds) {
                $matchingIds = $termIds
            }
            else {
                $matchingIds = IntersectStringSets -Left $matchingIds -Right $termIds
            }
        }

        if ($null -eq $matchingIds) {
            $matchingIds = CopyStringSet -Set $allDocumentIds
        }

        foreach ($queryTerm in @($group.Excludes)) {
            $excludedIds = GetFileIndexTermDocumentIdSet -Terms $terms -Term ([string]$queryTerm)
            RemoveStringSetValues -Set $matchingIds -Values $excludedIds
        }

        AddStringSetKeys -Set $candidateIds -Values $matchingIds
    }

    $matchedPaths = New-Object System.Collections.ArrayList
    $seenPaths = @{}
    foreach ($document in $documents) {
        $documentId = [string](GetFileIndexPropertyValue -Value $document -Name 'id')
        $documentName = [string](GetFileIndexPropertyValue -Value $document -Name 'name')
        $documentPath = [string](GetFileIndexPropertyValue -Value $document -Name 'path')

        if ([string]::IsNullOrWhiteSpace($documentName)) {
            $documentName = [string](GetFileIndexPropertyValue -Value $document -Name 'Filename')
        }
        if ([string]::IsNullOrWhiteSpace($documentPath)) {
            $documentPath = [string](GetFileIndexPropertyValue -Value $document -Name 'FilePath')
        }

        if (-not $candidateIds.ContainsKey($documentId)) {
            continue
        }
        if (-not (TestQuickSearchBooleanQueryText -Query $query -Text (GetFileIndexDocumentSearchText -Document $document))) {
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($documentPath) -and -not $seenPaths.ContainsKey($documentPath)) {
            $seenPaths[$documentPath] = $true
            [void]$matchedPaths.Add($documentPath)
            if ($MaxResults -gt 0 -and $matchedPaths.Count -ge $MaxResults) {
                break
            }
        }
    }

    return @($matchedPaths)
}


Function SearchLegacyFileIndex {
    param(
        [object[]]$IndexItems,
        [string]$Keyword,
        [int]$MaxResults = 0
    )

    $query = ConvertToQuickSearchBooleanQuery -Text $Keyword
    if (-not (TestQuickSearchBooleanQueryHasTerms -Query $query)) { return @() }
    $matchedPaths = New-Object System.Collections.ArrayList

    foreach ($item in $IndexItems) {
        $itemName = [string](GetFileIndexPropertyValue -Value $item -Name 'name')
        if ([string]::IsNullOrWhiteSpace($itemName)) {
            $itemName = [string](GetFileIndexPropertyValue -Value $item -Name 'Filename')
        }

        $itemPath = [string](GetFileIndexPropertyValue -Value $item -Name 'path')
        if ([string]::IsNullOrWhiteSpace($itemPath)) {
            $itemPath = [string](GetFileIndexPropertyValue -Value $item -Name 'FilePath')
        }

        if ([string]::IsNullOrWhiteSpace($itemPath)) {
            continue
        }

        $tagWords = @()
        $tags = GetFileIndexPropertyValue -Value $item -Name 'tags'
        if ($null -ne $tags) {
            $tagWords += @($tags)
        }

        $tagCounts = GetFileIndexPropertyValue -Value $item -Name 'tagCounts'
        if ($null -ne $tagCounts) {
            foreach ($property in @($tagCounts.PSObject.Properties)) {
                $tagWords += $property.Name
            }
        }

        $itemSearchText = (@($itemName, $itemPath) + @($tagWords)) -join ' '
        if (TestQuickSearchBooleanQueryText -Query $query -Text $itemSearchText) {
            if (-not $matchedPaths.Contains($itemPath)) {
                [void]$matchedPaths.Add($itemPath)
                if ($MaxResults -gt 0 -and $matchedPaths.Count -ge $MaxResults) {
                    break
                }
            }
        }
    }

    return @($matchedPaths)
}


Function SearchFileIndex {
    param(
        [string]$IndexFilePath,
        [string]$Keyword,
        [int]$MaxResults = 0
    )

    if ([string]::IsNullOrWhiteSpace($Keyword) -or -not (Test-Path -LiteralPath $IndexFilePath)) {
        return @()
    }

    if (TestFileIndexShardsAvailable -IndexFilePath $IndexFilePath) {
        return SearchShardedFileIndex -IndexFilePath $IndexFilePath -Keyword $Keyword -MaxResults $MaxResults
    }

    try {
        $indexData = ReadCachedFileIndexData -IndexFilePath $IndexFilePath
    }
    catch {
        Write-Host "Unable to read index file: $IndexFilePath" -ForegroundColor Red
        return @()
    }

    if ($null -eq $indexData) {
        return @()
    }

    $schemaVersion = GetFileIndexPropertyValue -Value $indexData -Name 'schemaVersion'
    if ($schemaVersion -eq 2) {
        return SearchInvertedFileIndex -IndexData $indexData -Keyword $Keyword -MaxResults $MaxResults
    }

    return SearchLegacyFileIndex -IndexItems @($indexData) -Keyword $Keyword -MaxResults $MaxResults
}


Function CreateFileIndex {
    param (
        [string]$Root = $PSScriptRoot,
        [object]$Config,
        [string]$IndexFilePath = (Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath 'data') -ChildPath 'index.json'),
        [string]$StatusFilePath = ''
    )

    if (-not (Test-Path -LiteralPath $Root)) {
        Write-Host "Index root does not exist: $Root" -ForegroundColor Red
        WriteFileIndexStatus -Path $StatusFilePath -Stage 'Failed'
        return $false
    }

    $tagCount = 10
    if ($null -ne $Config -and $null -ne $Config.TagCount) {
        $tagCount = [Math]::Max(1, [int]$Config.TagCount)
    }
    $maxTagFileSizeBytes = GetFileIndexMaxTagFileSizeBytes -Config $Config

    WriteFileIndexStatus -Path $StatusFilePath -Stage 'Scanning files'
    $previousDocumentsByPath = GetReusableFileIndexDocumentsByPath -IndexFilePath $IndexFilePath
    $files = @(Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction SilentlyContinue)
    $indexedFiles = New-Object System.Collections.ArrayList
    $terms = [ordered]@{}
    $documentId = 0
    $processedFiles = 0
    $skippedFiles = 0
    $reusedFiles = 0
    $lastStatusUtc = [System.DateTime]::UtcNow
    $lastCheckpointUtc = [System.DateTime]::UtcNow
    WriteFileIndexStatus -Path $StatusFilePath -Stage 'Indexing files' -Processed 0 -Total $files.Count

    foreach ($file in $files) {
        $processedFiles++
        WriteFileIndexStatus -Path $StatusFilePath -Stage 'Indexing files' -Processed $processedFiles -Total $files.Count -Indexed $indexedFiles.Count -Skipped $skippedFiles -Reused $reusedFiles -CurrentFile $file.Name
        $lastStatusUtc = [System.DateTime]::UtcNow
        if ($null -ne $Config -and (TestIgnoredFile -File $file -Config $Config)) {
            $skippedFiles++
            if (($processedFiles -eq $files.Count) -or (([System.DateTime]::UtcNow - $lastStatusUtc).TotalMilliseconds -ge 750)) {
                WriteFileIndexStatus -Path $StatusFilePath -Stage 'Indexing files' -Processed $processedFiles -Total $files.Count -Indexed $indexedFiles.Count -Skipped $skippedFiles -Reused $reusedFiles
                $lastStatusUtc = [System.DateTime]::UtcNow
            }
            continue
        }

        $documentId++
        $previousDocument = $null
        if ($previousDocumentsByPath.ContainsKey($file.FullName)) {
            $previousDocument = $previousDocumentsByPath[$file.FullName]
        }

        $indexedFile = $null
        if ($null -ne $previousDocument -and (TestReusableFileIndexDocument -Document $previousDocument -File $file)) {
            $indexedFile = ConvertToFileIndexDocument -File $file -DocumentId $documentId -ReusableDocument $previousDocument -TagCounts $null
            $reusedFiles++
        }
        else {
            $tagCounts = GetFileIndexTagCountsForFile -File $file -Count $tagCount -PreviousDocumentsByPath $previousDocumentsByPath -MaxFileSizeBytes $maxTagFileSizeBytes
            $indexedFile = ConvertToFileIndexDocument -File $file -DocumentId $documentId -ReusableDocument $null -TagCounts $tagCounts
        }

        [void]$indexedFiles.Add($indexedFile)
        AddFileIndexDocumentTerms -Terms $terms -Document $indexedFile
        if (([System.DateTime]::UtcNow - $lastCheckpointUtc).TotalSeconds -ge 2 -or $processedFiles -eq $files.Count) {
            WriteFileIndexCheckpoint -IndexFilePath $IndexFilePath -Root $Root -Documents $indexedFiles -Terms $terms -Processed $processedFiles -Total $files.Count -Skipped $skippedFiles
            $lastCheckpointUtc = [System.DateTime]::UtcNow
        }

        if (($processedFiles -eq $files.Count) -or (([System.DateTime]::UtcNow - $lastStatusUtc).TotalMilliseconds -ge 750)) {
            WriteFileIndexStatus -Path $StatusFilePath -Stage 'Indexing files' -Processed $processedFiles -Total $files.Count -Indexed $indexedFiles.Count -Skipped $skippedFiles -Reused $reusedFiles
            $lastStatusUtc = [System.DateTime]::UtcNow
        }
    }

    WriteFileIndexStatus -Path $StatusFilePath -Stage 'Writing index' -Processed $processedFiles -Total $files.Count -Indexed $indexedFiles.Count -Skipped $skippedFiles -Reused $reusedFiles
    WriteFileIndexCheckpoint -IndexFilePath $IndexFilePath -Root $Root -Documents $indexedFiles -Terms $terms -Processed $processedFiles -Total $files.Count -Skipped $skippedFiles -Complete $true
    $checkpointData = ReadFileIndexData -Path (GetFileIndexTempPath -IndexFilePath $IndexFilePath)
    CompleteFileIndexFromCheckpoint -IndexFilePath $IndexFilePath
    if ($null -ne $checkpointData) {
        [void](WriteFileIndexShardsFromData -IndexFilePath $IndexFilePath -IndexData $checkpointData)
    }

    WriteFileIndexStatus -Path $StatusFilePath -Stage 'Completed' -Processed $processedFiles -Total $files.Count -Indexed $indexedFiles.Count -Skipped $skippedFiles -Reused $reusedFiles
    Write-Host "QuickSearch sharded index has been created successfully!" -ForegroundColor Green
    return $true
}