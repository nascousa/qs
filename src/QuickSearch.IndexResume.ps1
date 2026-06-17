<#
.SYNOPSIS
Provides resumable QuickSearch index checkpoint helpers.
#>

Function GetFileIndexTempPath {
    param(
        [string]$IndexFilePath
    )

    return "$IndexFilePath.tmp"
}


Function GetFileIndexBackupPath {
    param(
        [string]$IndexFilePath
    )

    return "$IndexFilePath.bak"
}


Function ReadFileIndexData {
    param(
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return $null
    }
}


Function GetFileIndexReusableDocumentPathMap {
    param(
        [string]$IndexFilePath
    )

    $documentsByPath = @{}
    foreach ($candidatePath in @((GetFileIndexTempPath -IndexFilePath $IndexFilePath), $IndexFilePath)) {
        $indexData = ReadFileIndexData -Path $candidatePath
        if ($null -eq $indexData) {
            continue
        }

        foreach ($document in @(GetFileIndexDocuments -IndexData $indexData)) {
            $documentPath = GetFileIndexPropertyValue -Value $document -Name 'path'
            if ([string]::IsNullOrWhiteSpace($documentPath)) {
                $documentPath = GetFileIndexPropertyValue -Value $document -Name 'FilePath'
            }

            if (-not [string]::IsNullOrWhiteSpace($documentPath) -and -not $documentsByPath.ContainsKey($documentPath)) {
                $documentsByPath[$documentPath] = $document
            }
        }
    }

    return $documentsByPath
}


Function ConvertToFileIndexDocument {
    param(
        [System.IO.FileInfo]$File,
        [int]$DocumentId,
        [object]$ReusableDocument,
        [object]$TagCounts
    )

    $effectiveTagCounts = $TagCounts
    if ($null -eq $effectiveTagCounts) {
        $effectiveTagCounts = [ordered]@{}
    }

    if ($null -ne $ReusableDocument -and (TestReusableFileIndexDocument -Document $ReusableDocument -File $File)) {
        $effectiveTagCounts = ConvertToFileIndexTagCounts -TagCounts (GetFileIndexPropertyValue -Value $ReusableDocument -Name 'tagCounts') -Tags @((GetFileIndexPropertyValue -Value $ReusableDocument -Name 'tags'))
    }

    return [PSCustomObject]@{
        id = $DocumentId
        name = $File.Name
        path = $File.FullName
        sizeInBytes = $File.Length
        lastModified = $File.LastWriteTime.ToString('o')
        lastWriteUtc = $File.LastWriteTimeUtc.ToString('o')
        tags = @($effectiveTagCounts.Keys)
        tagCounts = $effectiveTagCounts
    }
}


Function NewFileIndexData {
    param(
        [string]$Root,
        [object[]]$Documents,
        [object]$Terms,
        [int]$Processed,
        [int]$Total,
        [int]$Skipped,
        [bool]$Complete
    )

    $termIndex = [ordered]@{}
    foreach ($termKey in @($Terms.Keys | Sort-Object)) {
        $termIndex[$termKey] = @($Terms[$termKey] | Sort-Object -Unique)
    }

    return [PSCustomObject]@{
        schemaVersion = 2
        root = [System.IO.Path]::GetFullPath($Root)
        createdUtc = [System.DateTime]::UtcNow.ToString('o')
        complete = $Complete
        processed = $Processed
        total = $Total
        skipped = $Skipped
        documents = @($Documents)
        terms = $termIndex
    }
}


Function WriteFileIndexCheckpoint {
    param(
        [string]$IndexFilePath,
        [string]$Root,
        [System.Collections.ArrayList]$Documents,
        [System.Collections.IDictionary]$Terms,
        [int]$Processed,
        [int]$Total,
        [int]$Skipped,
        [bool]$Complete = $false
    )

    $indexParentPath = Split-Path -Parent $IndexFilePath
    if (-not [string]::IsNullOrWhiteSpace($indexParentPath) -and -not (Test-Path -LiteralPath $indexParentPath)) {
        New-Item -ItemType Directory -Path $indexParentPath -Force | Out-Null
    }

    $indexData = NewFileIndexData -Root $Root -Documents @($Documents) -Terms $Terms -Processed $Processed -Total $Total -Skipped $Skipped -Complete $Complete
    $json = $indexData | ConvertTo-Json -Depth 20
    Set-Content -LiteralPath (GetFileIndexTempPath -IndexFilePath $IndexFilePath) -Value $json -ErrorAction Stop
}


Function CompleteFileIndexFromCheckpoint {
    param(
        [string]$IndexFilePath
    )

    $tempIndexFilePath = GetFileIndexTempPath -IndexFilePath $IndexFilePath
    if (-not (Test-Path -LiteralPath $tempIndexFilePath)) {
        return
    }

    if (Test-Path -LiteralPath $IndexFilePath) {
        $backupIndexFilePath = GetFileIndexBackupPath -IndexFilePath $IndexFilePath
        [System.IO.File]::Replace($tempIndexFilePath, $IndexFilePath, $backupIndexFilePath, $true)
        Remove-Item -LiteralPath $backupIndexFilePath -Force -ErrorAction SilentlyContinue
    }
    else {
        Move-Item -LiteralPath $tempIndexFilePath -Destination $IndexFilePath -Force
    }
}
