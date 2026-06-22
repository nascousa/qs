<#
.SYNOPSIS
Provides sharded QuickSearch index helpers.
#>

Function GetFileIndexShardDirectoryName {
    param(
        [string]$IndexFilePath
    )

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($IndexFilePath)
    if ([string]::IsNullOrWhiteSpace($baseName)) {
        $baseName = 'index'
    }

    return "$baseName-shards"
}


Function GetFileIndexShardRootPath {
    param(
        [string]$IndexFilePath,
        [object]$Manifest = $null
    )

    $indexParentPath = Split-Path -Parent $IndexFilePath
    if ([string]::IsNullOrWhiteSpace($indexParentPath)) {
        $indexParentPath = (Get-Location).Path
    }

    $shardDirectory = $null
    if ($null -ne $Manifest) {
        $shardDirectory = GetFileIndexPropertyValue -Value $Manifest -Name 'shardDirectory'
    }

    if ([string]::IsNullOrWhiteSpace([string]$shardDirectory)) {
        $shardDirectory = GetFileIndexShardDirectoryName -IndexFilePath $IndexFilePath
    }

    if ([System.IO.Path]::IsPathRooted([string]$shardDirectory)) {
        return [string]$shardDirectory
    }

    return (Join-Path -Path $indexParentPath -ChildPath ([string]$shardDirectory))
}


Function GetFileIndexShardTempRootPath {
    param(
        [string]$IndexFilePath
    )

    return "$(GetFileIndexShardRootPath -IndexFilePath $IndexFilePath).tmp"
}


Function GetFileIndexShardBackupRootPath {
    param(
        [string]$IndexFilePath
    )

    return "$(GetFileIndexShardRootPath -IndexFilePath $IndexFilePath).bak"
}


Function GetFileIndexManifestTempPath {
    param(
        [string]$IndexFilePath
    )

    return "$IndexFilePath.manifest.tmp"
}


Function GetFileIndexDefaultDocumentShardSize {
    return 1000
}


Function GetFileIndexTermShardKey {
    param(
        [string]$Term
    )

    if ([string]::IsNullOrWhiteSpace($Term)) {
        return 'other'
    }

    $firstCharacter = $Term.Substring(0, 1).ToLowerInvariant()
    if ($firstCharacter -match '^[a-z0-9]$') {
        return $firstCharacter
    }

    return 'other'
}


Function GetFileIndexDocumentShardKey {
    param(
        [int]$DocumentId,
        [int]$ShardSize = (GetFileIndexDefaultDocumentShardSize)
    )

    $effectiveDocumentId = [Math]::Max(1, $DocumentId)
    $effectiveShardSize = [Math]::Max(1, $ShardSize)
    $shardNumber = [int][Math]::Floor(($effectiveDocumentId - 1) / $effectiveShardSize)
    return ('{0:D4}' -f $shardNumber)
}


Function GetFileIndexShardFilePath {
    param(
        [string]$IndexFilePath,
        [object]$Manifest,
        [string]$FileName
    )

    return (Join-Path -Path (GetFileIndexShardRootPath -IndexFilePath $IndexFilePath -Manifest $Manifest) -ChildPath $FileName)
}


Function WriteFileIndexJsonFile {
    param(
        [string]$Path,
        [object]$Value
    )

    $json = $Value | ConvertTo-Json -Depth 20
    Set-Content -LiteralPath $Path -Value $json -ErrorAction Stop
}


Function NewFileIndexSortedTerms {
    param(
        [object]$Terms
    )

    $termIndex = [ordered]@{}
    foreach ($property in @(GetFileIndexTermProperties -Terms $Terms | Sort-Object -Property Name)) {
        $termIndex[[string]$property.Name] = @($property.Value | Sort-Object -Unique)
    }

    return $termIndex
}


Function GetFileIndexDictionaryCount {
    param(
        [object]$Value
    )

    if ($Value -is [System.Collections.IDictionary]) {
        return @($Value.Keys).Count
    }

    if ($null -eq $Value) {
        return 0
    }

    return @($Value.PSObject.Properties).Count
}


Function NewFileIndexShardManifest {
    param(
        [string]$Root,
        [string]$CreatedUtc,
        [int]$Processed,
        [int]$Total,
        [int]$Skipped,
        [int]$DocumentCount,
        [int]$TermCount,
        [int]$DocumentShardSize,
        [object[]]$DocumentShards,
        [object[]]$TermShards,
        [string]$ShardDirectory
    )

    return [PSCustomObject]@{
        schemaVersion = 3
        indexFormat = 'QuickSearch.ShardedIndex'
        root = [System.IO.Path]::GetFullPath($Root)
        createdUtc = $CreatedUtc
        complete = $true
        processed = $Processed
        total = $Total
        skipped = $Skipped
        documentCount = $DocumentCount
        termCount = $TermCount
        documentShardSize = $DocumentShardSize
        shardDirectory = $ShardDirectory
        documentShards = @($DocumentShards)
        termShards = @($TermShards)
    }
}


Function CompleteFileIndexShardDirectory {
    param(
        [string]$IndexFilePath,
        [object]$Manifest
    )

    $finalShardRoot = GetFileIndexShardRootPath -IndexFilePath $IndexFilePath -Manifest $Manifest
    $tempShardRoot = GetFileIndexShardTempRootPath -IndexFilePath $IndexFilePath
    $backupShardRoot = GetFileIndexShardBackupRootPath -IndexFilePath $IndexFilePath

    if (Test-Path -LiteralPath $backupShardRoot) {
        Remove-Item -LiteralPath $backupShardRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path -LiteralPath $finalShardRoot) {
        Move-Item -LiteralPath $finalShardRoot -Destination $backupShardRoot -Force
    }

    Move-Item -LiteralPath $tempShardRoot -Destination $finalShardRoot -Force
    if (Test-Path -LiteralPath $backupShardRoot) {
        Remove-Item -LiteralPath $backupShardRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}


Function CompleteFileIndexManifestFile {
    param(
        [string]$IndexFilePath
    )

    $tempManifestPath = GetFileIndexManifestTempPath -IndexFilePath $IndexFilePath
    if (-not (Test-Path -LiteralPath $tempManifestPath -PathType Leaf)) {
        return
    }

    if (Test-Path -LiteralPath $IndexFilePath -PathType Leaf) {
        $backupIndexFilePath = GetFileIndexBackupPath -IndexFilePath $IndexFilePath
        [System.IO.File]::Replace($tempManifestPath, $IndexFilePath, $backupIndexFilePath, $true)
        Remove-Item -LiteralPath $backupIndexFilePath -Force -ErrorAction SilentlyContinue
    }
    else {
        Move-Item -LiteralPath $tempManifestPath -Destination $IndexFilePath -Force
    }
}


Function WriteFileIndexShardsFromData {
    param(
        [string]$IndexFilePath,
        [object]$IndexData
    )

    if ($null -eq $IndexData) {
        return $false
    }

    $root = [string](GetFileIndexPropertyValue -Value $IndexData -Name 'root')
    if ([string]::IsNullOrWhiteSpace($root)) {
        $root = Split-Path -Parent $IndexFilePath
    }

    $documents = @((GetFileIndexPropertyValue -Value $IndexData -Name 'documents'))
    $terms = GetFileIndexPropertyValue -Value $IndexData -Name 'terms'
    if ($null -eq $terms) {
        $terms = [ordered]@{}
    }

    $processed = [int](GetFileIndexPropertyValue -Value $IndexData -Name 'processed')
    $total = [int](GetFileIndexPropertyValue -Value $IndexData -Name 'total')
    $skipped = [int](GetFileIndexPropertyValue -Value $IndexData -Name 'skipped')
    $createdUtc = [string](GetFileIndexPropertyValue -Value $IndexData -Name 'createdUtc')
    if ([string]::IsNullOrWhiteSpace($createdUtc)) {
        $createdUtc = [System.DateTime]::UtcNow.ToString('o')
    }

    $tempShardRoot = GetFileIndexShardTempRootPath -IndexFilePath $IndexFilePath
    if (Test-Path -LiteralPath $tempShardRoot) {
        Remove-Item -LiteralPath $tempShardRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Path $tempShardRoot -Force | Out-Null

    $documentShardSize = GetFileIndexDefaultDocumentShardSize
    $documentShardEntries = New-Object System.Collections.ArrayList
    $documentsByShard = @{}
    foreach ($document in $documents) {
        $documentId = [int](GetFileIndexPropertyValue -Value $document -Name 'id')
        $shardKey = GetFileIndexDocumentShardKey -DocumentId $documentId -ShardSize $documentShardSize
        if (-not $documentsByShard.ContainsKey($shardKey)) {
            $documentsByShard[$shardKey] = New-Object System.Collections.ArrayList
        }
        [void]$documentsByShard[$shardKey].Add($document)
    }

    foreach ($shardKey in @($documentsByShard.Keys | Sort-Object)) {
        $shardDocuments = @($documentsByShard[$shardKey] | Sort-Object -Property @{ Expression = { [int](GetFileIndexPropertyValue -Value $_ -Name 'id') }; Descending = $false })
        if ($shardDocuments.Count -eq 0) { continue }

        $startId = [int](GetFileIndexPropertyValue -Value $shardDocuments[0] -Name 'id')
        $endId = [int](GetFileIndexPropertyValue -Value $shardDocuments[$shardDocuments.Count - 1] -Name 'id')
        $fileName = "documents-$shardKey.json"
        $shardData = [PSCustomObject]@{
            schemaVersion = 3
            shardType = 'documents'
            key = $shardKey
            startId = $startId
            endId = $endId
            count = $shardDocuments.Count
            documents = @($shardDocuments)
        }
        WriteFileIndexJsonFile -Path (Join-Path -Path $tempShardRoot -ChildPath $fileName) -Value $shardData
        [void]$documentShardEntries.Add([PSCustomObject]@{ key = $shardKey; file = $fileName; startId = $startId; endId = $endId; count = $shardDocuments.Count })
    }

    $sortedTerms = NewFileIndexSortedTerms -Terms $terms
    $termsByShard = @{}
    foreach ($termKey in @($sortedTerms.Keys)) {
        $shardKey = GetFileIndexTermShardKey -Term ([string]$termKey)
        if (-not $termsByShard.ContainsKey($shardKey)) {
            $termsByShard[$shardKey] = [ordered]@{}
        }
        $termsByShard[$shardKey][$termKey] = @($sortedTerms[$termKey])
    }

    $termShardEntries = New-Object System.Collections.ArrayList
    foreach ($shardKey in @($termsByShard.Keys | Sort-Object)) {
        $fileName = "terms-$shardKey.json"
        $shardTerms = $termsByShard[$shardKey]
        $shardData = [PSCustomObject]@{
            schemaVersion = 3
            shardType = 'terms'
            key = $shardKey
            count = GetFileIndexDictionaryCount -Value $shardTerms
            terms = $shardTerms
        }
        WriteFileIndexJsonFile -Path (Join-Path -Path $tempShardRoot -ChildPath $fileName) -Value $shardData
        [void]$termShardEntries.Add([PSCustomObject]@{ key = $shardKey; file = $fileName; count = (GetFileIndexDictionaryCount -Value $shardTerms) })
    }

    $manifest = NewFileIndexShardManifest -Root $root -CreatedUtc $createdUtc -Processed $processed -Total $total -Skipped $skipped -DocumentCount $documents.Count -TermCount (GetFileIndexDictionaryCount -Value $sortedTerms) -DocumentShardSize $documentShardSize -DocumentShards @($documentShardEntries) -TermShards @($termShardEntries) -ShardDirectory (GetFileIndexShardDirectoryName -IndexFilePath $IndexFilePath)
    WriteFileIndexJsonFile -Path (GetFileIndexManifestTempPath -IndexFilePath $IndexFilePath) -Value $manifest
    CompleteFileIndexShardDirectory -IndexFilePath $IndexFilePath -Manifest $manifest
    CompleteFileIndexManifestFile -IndexFilePath $IndexFilePath
    return $true
}


Function ReadFileIndexShardManifest {
    param(
        [string]$IndexFilePath
    )

    if ([string]::IsNullOrWhiteSpace($IndexFilePath) -or -not (Test-Path -LiteralPath $IndexFilePath -PathType Leaf)) {
        return $null
    }

    $manifest = $null
    try {
        $manifest = ReadCachedFileIndexData -IndexFilePath $IndexFilePath
    }
    catch {
        return $null
    }
    if ($null -eq $manifest) { return $null }
    if (3 -ne [int](GetFileIndexPropertyValue -Value $manifest -Name 'schemaVersion')) { return $null }
    if ('QuickSearch.ShardedIndex' -ne [string](GetFileIndexPropertyValue -Value $manifest -Name 'indexFormat')) { return $null }
    if ($true -ne [bool](GetFileIndexPropertyValue -Value $manifest -Name 'complete')) { return $null }

    $shardRoot = GetFileIndexShardRootPath -IndexFilePath $IndexFilePath -Manifest $manifest
    if (-not (Test-Path -LiteralPath $shardRoot -PathType Container)) { return $null }
    return $manifest
}


Function TestFileIndexShardsAvailable {
    param(
        [string]$IndexFilePath
    )

    return ($null -ne (ReadFileIndexShardManifest -IndexFilePath $IndexFilePath))
}


Function ReadFileIndexShardFile {
    param(
        [string]$IndexFilePath,
        [object]$Manifest,
        [string]$FileName
    )

    $shardPath = GetFileIndexShardFilePath -IndexFilePath $IndexFilePath -Manifest $Manifest -FileName $FileName
    if (-not (Test-Path -LiteralPath $shardPath -PathType Leaf)) {
        return $null
    }

    return ReadCachedFileIndexData -IndexFilePath $shardPath
}


Function GetFileIndexShardedTermProperties {
    param(
        [string]$IndexFilePath,
        [object]$Manifest
    )

    $properties = New-Object System.Collections.ArrayList
    foreach ($termShard in @((GetFileIndexPropertyValue -Value $Manifest -Name 'termShards'))) {
        $fileName = [string](GetFileIndexPropertyValue -Value $termShard -Name 'file')
        $shardData = ReadFileIndexShardFile -IndexFilePath $IndexFilePath -Manifest $Manifest -FileName $fileName
        if ($null -eq $shardData) { continue }
        $terms = GetFileIndexPropertyValue -Value $shardData -Name 'terms'
        foreach ($property in @(GetFileIndexTermProperties -Terms $terms)) {
            [void]$properties.Add($property)
        }
    }

    return @($properties)
}


Function GetFileIndexTermDocumentIdSetFromProperties {
    param(
        [object[]]$TermProperties,
        [string]$Term
    )

    $documentIds = NewStringSet
    if ([string]::IsNullOrWhiteSpace($Term)) {
        return $documentIds
    }

    $normalizedTerm = $Term.ToLowerInvariant()
    $termPattern = GetWildcardContainsPattern $normalizedTerm
    foreach ($property in @($TermProperties)) {
        $propertyName = [string]$property.Name
        if ($propertyName -eq $normalizedTerm -or $propertyName -like $termPattern) {
            AddStringSetValues -Set $documentIds -Values $property.Value
        }
    }

    return $documentIds
}


Function AddFileIndexManifestDocumentIds {
    param(
        [hashtable]$Set,
        [object]$Manifest
    )

    foreach ($documentShard in @((GetFileIndexPropertyValue -Value $Manifest -Name 'documentShards'))) {
        $startId = [int](GetFileIndexPropertyValue -Value $documentShard -Name 'startId')
        $endId = [int](GetFileIndexPropertyValue -Value $documentShard -Name 'endId')
        for ($documentId = $startId; $documentId -le $endId; $documentId++) {
            AddStringSetValue -Set $Set -Value ([string]$documentId)
        }
    }
}


Function GetFileIndexDocumentShardEntriesByKey {
    param(
        [object]$Manifest
    )

    $entries = @{}
    foreach ($documentShard in @((GetFileIndexPropertyValue -Value $Manifest -Name 'documentShards'))) {
        $key = [string](GetFileIndexPropertyValue -Value $documentShard -Name 'key')
        if (-not [string]::IsNullOrWhiteSpace($key)) {
            $entries[$key] = $documentShard
        }
    }

    return $entries
}


Function GetFileIndexShardedDocumentsForIdSet {
    param(
        [string]$IndexFilePath,
        [object]$Manifest,
        [hashtable]$DocumentIds
    )

    if ($null -eq $DocumentIds -or $DocumentIds.Count -eq 0) {
        return @()
    }

    $documentShardSize = [int](GetFileIndexPropertyValue -Value $Manifest -Name 'documentShardSize')
    if ($documentShardSize -lt 1) { $documentShardSize = GetFileIndexDefaultDocumentShardSize }
    $entriesByKey = GetFileIndexDocumentShardEntriesByKey -Manifest $Manifest
    $keysToLoad = @{}
    foreach ($documentIdText in @($DocumentIds.Keys)) {
        $documentId = 0
        if ([int]::TryParse([string]$documentIdText, [ref]$documentId)) {
            $keysToLoad[(GetFileIndexDocumentShardKey -DocumentId $documentId -ShardSize $documentShardSize)] = $true
        }
    }

    $documents = New-Object System.Collections.ArrayList
    foreach ($shardKey in @($keysToLoad.Keys | Sort-Object)) {
        if (-not $entriesByKey.ContainsKey($shardKey)) { continue }
        $fileName = [string](GetFileIndexPropertyValue -Value $entriesByKey[$shardKey] -Name 'file')
        $shardData = ReadFileIndexShardFile -IndexFilePath $IndexFilePath -Manifest $Manifest -FileName $fileName
        if ($null -eq $shardData) { continue }
        foreach ($document in @((GetFileIndexPropertyValue -Value $shardData -Name 'documents'))) {
            $documentId = [string](GetFileIndexPropertyValue -Value $document -Name 'id')
            if ($DocumentIds.ContainsKey($documentId)) {
                [void]$documents.Add($document)
            }
        }
    }

    return @($documents)
}


Function GetFileIndexShardedDocuments {
    param(
        [string]$IndexFilePath
    )

    $manifest = ReadFileIndexShardManifest -IndexFilePath $IndexFilePath
    if ($null -eq $manifest) { return @() }

    $documents = New-Object System.Collections.ArrayList
    foreach ($documentShard in @((GetFileIndexPropertyValue -Value $manifest -Name 'documentShards') | Sort-Object -Property @{ Expression = { [int](GetFileIndexPropertyValue -Value $_ -Name 'startId') }; Descending = $false })) {
        $fileName = [string](GetFileIndexPropertyValue -Value $documentShard -Name 'file')
        $shardData = ReadFileIndexShardFile -IndexFilePath $IndexFilePath -Manifest $manifest -FileName $fileName
        if ($null -eq $shardData) { continue }
        foreach ($document in @((GetFileIndexPropertyValue -Value $shardData -Name 'documents'))) {
            [void]$documents.Add($document)
        }
    }

    return @($documents)
}


Function SearchShardedFileIndex {
    param(
        [string]$IndexFilePath,
        [string]$Keyword,
        [int]$MaxResults = 0
    )

    $manifest = ReadFileIndexShardManifest -IndexFilePath $IndexFilePath
    if ($null -eq $manifest) { return @() }

    $query = ConvertToQuickSearchBooleanQuery -Text $Keyword
    if (-not (TestQuickSearchBooleanQueryHasTerms -Query $query)) { return @() }

    $termProperties = @(GetFileIndexShardedTermProperties -IndexFilePath $IndexFilePath -Manifest $manifest)
    $allDocumentIds = NewStringSet
    AddFileIndexManifestDocumentIds -Set $allDocumentIds -Manifest $manifest

    $candidateIds = NewStringSet
    foreach ($group in @($query.Groups)) {
        $matchingIds = $null
        foreach ($queryTerm in @($group.Includes)) {
            $termIds = GetFileIndexTermDocumentIdSetFromProperties -TermProperties $termProperties -Term ([string]$queryTerm)
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
            $excludedIds = GetFileIndexTermDocumentIdSetFromProperties -TermProperties $termProperties -Term ([string]$queryTerm)
            RemoveStringSetValues -Set $matchingIds -Values $excludedIds
        }

        AddStringSetKeys -Set $candidateIds -Values $matchingIds
    }

    $matchedPaths = New-Object System.Collections.ArrayList
    $seenPaths = @{}
    $documents = @(GetFileIndexShardedDocumentsForIdSet -IndexFilePath $IndexFilePath -Manifest $manifest -DocumentIds $candidateIds)
    foreach ($document in $documents) {
        $documentPath = [string](GetFileIndexPropertyValue -Value $document -Name 'path')
        if ([string]::IsNullOrWhiteSpace($documentPath)) {
            $documentPath = [string](GetFileIndexPropertyValue -Value $document -Name 'FilePath')
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


Function GetFileIndexShardDirectorySizeBytes {
    param(
        [string]$IndexFilePath,
        [object]$Manifest
    )

    $totalBytes = 0L
    $shardRoot = GetFileIndexShardRootPath -IndexFilePath $IndexFilePath -Manifest $Manifest
    if (Test-Path -LiteralPath $IndexFilePath -PathType Leaf) {
        $totalBytes += (Get-Item -LiteralPath $IndexFilePath).Length
    }
    if (Test-Path -LiteralPath $shardRoot -PathType Container) {
        foreach ($file in @(Get-ChildItem -LiteralPath $shardRoot -File -ErrorAction SilentlyContinue)) {
            $totalBytes += $file.Length
        }
    }

    return $totalBytes
}


Function GetFileIndexShardedSummaryText {
    param(
        [string]$IndexFilePath
    )

    $manifest = ReadFileIndexShardManifest -IndexFilePath $IndexFilePath
    if ($null -eq $manifest) { return $null }

    $documentShards = @((GetFileIndexPropertyValue -Value $manifest -Name 'documentShards'))
    $termShards = @((GetFileIndexPropertyValue -Value $manifest -Name 'termShards'))
    $indexFile = Get-Item -LiteralPath $IndexFilePath -ErrorAction SilentlyContinue
    $updatedText = 'n/a'
    if ($null -ne $indexFile) {
        $updatedText = $indexFile.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
    }

    return @(
        'Status: Ready (sharded)',
        "Files indexed: $([int](GetFileIndexPropertyValue -Value $manifest -Name 'documentCount'))",
        "Search terms: $([int](GetFileIndexPropertyValue -Value $manifest -Name 'termCount'))",
        "Document shards: $($documentShards.Count)",
        "Term shards: $($termShards.Count)",
        'Schema version: 3',
        "Created UTC: $([string](GetFileIndexPropertyValue -Value $manifest -Name 'createdUtc'))",
        "Updated: $updatedText",
        "Index size: $(ConvertQuickSearchByteSizeText -Bytes (GetFileIndexShardDirectorySizeBytes -IndexFilePath $IndexFilePath -Manifest $manifest))"
    ) -join [Environment]::NewLine
}