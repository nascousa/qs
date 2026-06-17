<#
.SYNOPSIS
Writes lightweight QuickSearch index progress state for UI polling.
#>

Function WriteFileIndexStatus {
    param(
        [string]$Path,
        [string]$Stage,
        [int]$Processed = 0,
        [int]$Total = 0,
        [int]$Indexed = 0,
        [int]$Skipped = 0,
        [int]$Reused = 0,
        [string]$CurrentFile = ''
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    try {
        $statusParent = Split-Path -Parent $Path
        if (-not [string]::IsNullOrWhiteSpace($statusParent) -and -not (Test-Path -LiteralPath $statusParent)) {
            New-Item -ItemType Directory -Path $statusParent -Force | Out-Null
        }

        [PSCustomObject]@{
            stage = $Stage
            processed = $Processed
            total = $Total
            indexed = $Indexed
            skipped = $Skipped
            reused = $Reused
            currentFile = $CurrentFile
            updatedUtc = [System.DateTime]::UtcNow.ToString('o')
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Path -NoNewline -ErrorAction Stop
    }
    catch {
    }
}
