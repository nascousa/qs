<#
.SYNOPSIS
Provides lightweight QuickSearch index policy helpers.
#>

Function GetFileIndexMaxTagFileSizeBytes {
    param(
        [object]$Config
    )

    $sizeInMb = 10
    $configuredSizeInMb = GetFileIndexConfigValue -Config $Config -Name 'MaxTagFileSizeMB'
    if ($null -ne $configuredSizeInMb) {
        $parsedSizeInMb = 0
        if ([int]::TryParse([string]$configuredSizeInMb, [ref]$parsedSizeInMb)) {
            $sizeInMb = $parsedSizeInMb
        }
    }

    if ($sizeInMb -le 0) {
        return 0L
    }

    return ([int64]$sizeInMb * 1024L * 1024L)
}


Function GetFileIndexConfigValue {
    param(
        [object]$Config,
        [string]$Name
    )

    if ($null -eq $Config -or [string]::IsNullOrWhiteSpace($Name)) {
        return $null
    }

    $property = $Config.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}


Function ConvertToFileIndexExtensionList {
    param(
        [object[]]$Extensions
    )

    return @(
        foreach ($extension in @($Extensions)) {
            $normalized = ([string]$extension).Trim().ToLowerInvariant()
            if ([string]::IsNullOrWhiteSpace($normalized)) {
                continue
            }
            if (-not $normalized.StartsWith('.')) {
                $normalized = ".$normalized"
            }
            $normalized
        }
    )
}


Function TestFileIndexExtensionAllowed {
    param(
        [System.IO.FileInfo]$File,
        [object]$Config
    )

    $allowedFileExtNames = @(ConvertToFileIndexExtensionList -Extensions @(GetFileIndexConfigValue -Config $Config -Name 'AllowedFileExtNames'))
    if (0 -eq $allowedFileExtNames.Count) {
        return $true
    }

    if ($null -eq $File -or [string]::IsNullOrWhiteSpace($File.Extension)) {
        return $false
    }

    return ($allowedFileExtNames -contains $File.Extension.ToLowerInvariant())
}


Function TestFileIndexTagSizeLimited {
    param(
        [System.IO.FileInfo]$File,
        [int64]$MaxFileSizeBytes,
        [hashtable]$PreviousDocumentsByPath
    )

    if ($null -eq $File -or $MaxFileSizeBytes -le 0 -or $File.Length -le $MaxFileSizeBytes) {
        return $false
    }

    if ($null -ne $PreviousDocumentsByPath -and $PreviousDocumentsByPath.ContainsKey($File.FullName)) {
        if (TestReusableFileIndexDocument -Document $PreviousDocumentsByPath[$File.FullName] -File $File) {
            return $false
        }
    }

    return $true
}


Function GetFileIndexTagCountsForFile {
    param(
        [System.IO.FileInfo]$File,
        [int]$Count,
        [hashtable]$PreviousDocumentsByPath,
        [int64]$MaxFileSizeBytes = 0L
    )

    if ($null -ne $PreviousDocumentsByPath -and $PreviousDocumentsByPath.ContainsKey($File.FullName)) {
        $previousDocument = $PreviousDocumentsByPath[$File.FullName]
        if (TestReusableFileIndexDocument -Document $previousDocument -File $File) {
            return ConvertToFileIndexTagCounts -TagCounts (GetFileIndexPropertyValue -Value $previousDocument -Name 'tagCounts') -Tags @((GetFileIndexPropertyValue -Value $previousDocument -Name 'tags'))
        }
    }

    if (TestFileIndexTagSizeLimited -File $File -MaxFileSizeBytes $MaxFileSizeBytes -PreviousDocumentsByPath $PreviousDocumentsByPath) {
        return [ordered]@{}
    }

    return GetTopWords -FilePath $File.FullName -Count $Count
}
