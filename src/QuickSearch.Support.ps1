<#
.SYNOPSIS
    Read the QS settings config file.
#>
Function ReadConfig($configPath)
{
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    return $config
}


Function SaveConfig {
    param(
        [object]$Config,
        [string]$ConfigPath
    )

    $configParentPath = Split-Path -Parent $ConfigPath
    if (-not [string]::IsNullOrWhiteSpace($configParentPath) -and -not (Test-Path -LiteralPath $configParentPath)) {
        New-Item -ItemType Directory -Path $configParentPath -Force | Out-Null
    }

    $Config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ConfigPath
}


Function SetQuickSearchDialogCenter {
    param(
        [System.Windows.Forms.Form]$Dialog,
        [System.Windows.Forms.Form]$Owner
    )

    if ($null -eq $Dialog -or $Dialog.IsDisposed) {
        return
    }

    if ($null -ne $Owner -and -not $Owner.IsDisposed) {
        $ownerBounds = $Owner.Bounds
        if ($Owner.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized -and $Owner.RestoreBounds.Width -gt 0 -and $Owner.RestoreBounds.Height -gt 0) {
            $ownerBounds = $Owner.RestoreBounds
        }

        if ($ownerBounds.Width -gt 0 -and $ownerBounds.Height -gt 0) {
            $targetLeft = [int]($ownerBounds.Left + (($ownerBounds.Width - $Dialog.Width) / 2))
            $targetTop = [int]($ownerBounds.Top + (($ownerBounds.Height - $Dialog.Height) / 2))
            $screenBounds = [System.Windows.Forms.Screen]::FromControl($Owner).WorkingArea
            $maxLeft = [Math]::Max($screenBounds.Left, $screenBounds.Right - $Dialog.Width)
            $maxTop = [Math]::Max($screenBounds.Top, $screenBounds.Bottom - $Dialog.Height)
            $targetLeft = [Math]::Min([Math]::Max($screenBounds.Left, $targetLeft), $maxLeft)
            $targetTop = [Math]::Min([Math]::Max($screenBounds.Top, $targetTop), $maxTop)
            $Dialog.StartPosition = 'Manual'
            $Dialog.Location = New-Object System.Drawing.Point($targetLeft, $targetTop)
            return
        }
    }

    $Dialog.StartPosition = 'CenterScreen'
}


Function ShowQuickSearchMessageBox {
    param(
        [System.Windows.Forms.Form]$Owner,
        [string]$Message,
        [string]$Title
    )

    if ($null -ne $Owner -and -not $Owner.IsDisposed) {
        [System.Windows.Forms.MessageBox]::Show($Owner, $Message, $Title) | Out-Null
        return
    }

    [System.Windows.Forms.MessageBox]::Show($Message, $Title) | Out-Null
}


$IndexScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'QuickSearch.Index.ps1'
. $IndexScriptPath
$QueryScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'QuickSearch.Query.ps1'
. $QueryScriptPath
$SearchScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'QuickSearch.Search.ps1'
. $SearchScriptPath
$AsyncScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'QuickSearch.Async.ps1'
. $AsyncScriptPath
$PreviewScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'QuickSearch.Preview.ps1'
. $PreviewScriptPath
$ProfileScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'QuickSearch.Profile.ps1'
. $ProfileScriptPath


Function ClearQuickSearchKeywordPlaceholder {
    param(
        [object]$TextBox
    )

    $state = $TextBox.Tag
    if ($null -ne $state -and $state.ShowingPlaceholder) {
        $TextBox.Clear()
        $TextBox.ForeColor = [System.Drawing.SystemColors]::WindowText
        $state.ShowingPlaceholder = $false
    }
}


Function SetQuickSearchKeywordPlaceholder {
    param(
        [object]$TextBox
    )

    $state = $TextBox.Tag
    if ($null -ne $state -and [string]::IsNullOrWhiteSpace($TextBox.Text)) {
        $TextBox.Text = $state.Placeholder
        $TextBox.ForeColor = [System.Drawing.SystemColors]::GrayText
        $state.ShowingPlaceholder = $true
    }
}


Function GetQuickSearchKeywordText {
    param(
        [object]$TextBox
    )

    $state = $TextBox.Tag
    if ($null -ne $state -and $state.ShowingPlaceholder) {
        return ''
    }

    return $TextBox.Text.Trim()
}


Function InitializeQuickSearchKeywordPlaceholder {
    param(
        [object]$TextBox,
        [string]$Placeholder
    )

    $TextBox.Tag = [PSCustomObject]@{
        Placeholder = $Placeholder
        ShowingPlaceholder = $true
    }
    SetQuickSearchKeywordPlaceholder -TextBox $TextBox
    $TextBox.Add_Enter({ param($sender, $eventArgs) ClearQuickSearchKeywordPlaceholder -TextBox $sender })
    $TextBox.Add_Leave({ param($sender, $eventArgs) SetQuickSearchKeywordPlaceholder -TextBox $sender })
}


Function GetQuickSearchProjectVersion {
    param(
        [object]$Config,
        [string]$ConfigPath,
        [string]$RepoRoot
    )

    if ($null -ne $Config) {
        $versionProperty = $Config.PSObject.Properties['Version']
        if ($null -ne $versionProperty -and -not [string]::IsNullOrWhiteSpace([string]$versionProperty.Value)) {
            return ([string]$versionProperty.Value).Trim()
        }
    }

    $resolvedConfigPath = $ConfigPath
    if ([string]::IsNullOrWhiteSpace($resolvedConfigPath) -and -not [string]::IsNullOrWhiteSpace($RepoRoot)) {
        $resolvedConfigPath = Join-Path -Path $RepoRoot -ChildPath 'src\settings\config.json'
    }

    if (-not [string]::IsNullOrWhiteSpace($resolvedConfigPath) -and (Test-Path -LiteralPath $resolvedConfigPath)) {
        try {
            $configFromFile = Get-Content -LiteralPath $resolvedConfigPath -Raw | ConvertFrom-Json
            $versionProperty = $configFromFile.PSObject.Properties['Version']
            if ($null -ne $versionProperty -and -not [string]::IsNullOrWhiteSpace([string]$versionProperty.Value)) {
                return ([string]$versionProperty.Value).Trim()
            }
        }
        catch {
            Write-Host "Unable to read QS version from config: $resolvedConfigPath" -ForegroundColor Yellow
        }
    }

    $adcIndexPath = $null
    if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) {
        $adcIndexPath = Join-Path -Path $RepoRoot -ChildPath '.adc\index.md'
    }
    if (-not [string]::IsNullOrWhiteSpace($adcIndexPath) -and (Test-Path -LiteralPath $adcIndexPath)) {
        $adcIndexContent = Get-Content -LiteralPath $adcIndexPath -Raw
        $versionMatch = [regex]::Match($adcIndexContent, '(?m)^version:\s*"?([^"\r\n]+)"?\s*$')
        if ($versionMatch.Success) {
            return $versionMatch.Groups[1].Value.Trim()
        }
    }

    return '0.0.0'
}


Function ConvertVersionToTitleSuffix {
    param(
        [string]$Version
    )

    $versionMatch = [regex]::Match([string]$Version, '\d+(?:\.\d+){0,2}')
    if (-not $versionMatch.Success) {
        return 'v0.0.0'
    }

    $parts = @($versionMatch.Value.Split('.'))
    $major = 0
    $minor = 0
    $patch = 0
    [void][int]::TryParse($parts[0], [ref]$major)
    if ($parts.Count -gt 1) {
        [void][int]::TryParse($parts[1], [ref]$minor)
    }
    if ($parts.Count -gt 2) {
        [void][int]::TryParse($parts[2], [ref]$patch)
    }

    return ('v{0}.{1}.{2}' -f $major, $minor, $patch)
}


Function GetNextQuickSearchVersion {
    param(
        [string]$Version
    )

    $versionMatch = [regex]::Match([string]$Version, '\d+(?:\.\d+){0,2}')
    if (-not $versionMatch.Success) {
        return '0.0.1'
    }

    $parts = @($versionMatch.Value.Split('.'))
    $major = 0
    $minor = 0
    $patch = 0
    [void][int]::TryParse($parts[0], [ref]$major)
    if ($parts.Count -gt 1) {
        [void][int]::TryParse($parts[1], [ref]$minor)
    }
    if ($parts.Count -gt 2) {
        [void][int]::TryParse($parts[2], [ref]$patch)
    }

    $patch++
    if ($patch -gt 999) {
        $patch = 0
        $minor++
    }
    if ($minor -gt 99) {
        $minor = 0
        $major++
    }

    return ('{0}.{1}.{2}' -f $major, $minor, $patch)
}


Function GetQuickSearchWindowTitle {
    param(
        [string]$BaseTitle,
        [string]$Version
    )

    $title = $BaseTitle
    if ([string]::IsNullOrWhiteSpace($title)) {
        $title = 'QuickSearch'
    }

    $title = [regex]::Replace($title.Trim(), '\s+v\d+(?:\.\d+){1,2}$', '')
    return "$title $(ConvertVersionToTitleSuffix -Version $Version)"
}


Function SetConfigValue {
    param(
        [object]$Config,
        [string]$Name,
        [object]$Value
    )

    $property = $Config.PSObject.Properties[$Name]
    if ($null -ne $property) {
        $property.Value = $Value
    }
    else {
        Add-Member -InputObject $Config -NotePropertyName $Name -NotePropertyValue $Value -Force
    }
}


Function ConvertDelimitedTextToArray {
    param(
        [string]$Text
    )

    return @(
        $Text -split '[,;\r\n]+' |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}


Function ConvertArrayToDelimitedText {
    param(
        [object[]]$Values
    )

    return (@($Values) -join ', ')
}


Function GetDocPathTemplate {
    param(
        [object]$Config
    )

    $docPathTemplate = $Config.DocPath
    if ([string]::IsNullOrWhiteSpace($docPathTemplate)) {
        $docPathTemplate = $Config.Path
    }
    if ([string]::IsNullOrWhiteSpace($docPathTemplate)) {
        return ':\Orcas_Main\TSG-SOP\'
    }

    return $docPathTemplate
}


Function GetTeamPathTemplate {
    param(
        [object]$Config
    )

    $teamPathTemplate = $Config.TeamPath
    if ([string]::IsNullOrWhiteSpace($teamPathTemplate)) {
        return ':\Orcas_Main\team\'
    }

    return $teamPathTemplate
}


Function ResolveConfiguredPath {
    param(
        [string]$DriveLetter,
        [string]$PathTemplate
    )

    if ([string]::IsNullOrWhiteSpace($PathTemplate)) {
        return $null
    }

    if ($PathTemplate.StartsWith(':')) {
        return "$DriveLetter$PathTemplate"
    }

    return $PathTemplate
}


Function TestExistingLiteralPath {
    param(
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    return (Test-Path -LiteralPath $Path)
}


Function FormatQuickSearchFileTime {
    param(
        [object]$Value
    )

    if ($null -eq $Value) {
        return 'n/a'
    }

    try {
        return ([datetime]$Value).ToString('yyyy-MM-dd HH:mm')
    }
    catch {
        return 'n/a'
    }
}


Function NewQuickSearchResultItem {
    param(
        [string]$Path
    )

    $lastWriteTime = $null
    $creationTime = $null

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        try {
            $fileItem = Get-Item -LiteralPath $Path -ErrorAction Stop
            $lastWriteTime = $fileItem.LastWriteTime
            $creationTime = $fileItem.CreationTime
        }
        catch {
        }
    }

    $lastWriteText = FormatQuickSearchFileTime -Value $lastWriteTime
    $creationText = FormatQuickSearchFileTime -Value $creationTime
    $metadataText = ('Modified: {0}    Created: {1}' -f $lastWriteText, $creationText)
    $displayText = ('{0}    {1}' -f $metadataText, $Path)

    return [PSCustomObject]@{
        Path = [string]$Path
        Name = [System.IO.Path]::GetFileName([string]$Path)
        MetadataText = $metadataText
        DisplayText = $displayText
        LastWriteTime = $lastWriteTime
        CreationTime = $creationTime
        LastWriteText = $lastWriteText
        CreationText = $creationText
    }
}


Function GetQuickSearchResultItemPath {
    param(
        [object]$Item
    )

    if ($null -eq $Item) {
        return ''
    }

    $pathProperty = $Item.PSObject.Properties['Path']
    if ($null -ne $pathProperty) {
        return [string]$pathProperty.Value
    }

    return [string]$Item
}


Function GetQuickSearchResultItemDisplayText {
    param(
        [object]$Item
    )

    if ($null -eq $Item) {
        return ''
    }

    $displayTextProperty = $Item.PSObject.Properties['DisplayText']
    if ($null -ne $displayTextProperty) {
        return [string]$displayTextProperty.Value
    }

    return [string]$Item
}


Function SelectQuickSearchResultItems {
    param(
        [object[]]$Items,
        [string]$FilterText
    )

    $sourceItems = @($Items)
    if ([string]::IsNullOrWhiteSpace($FilterText)) {
        return @($sourceItems)
    }

    $matchedItems = New-Object System.Collections.ArrayList
    foreach ($item in $sourceItems) {
        $displayText = GetQuickSearchResultItemDisplayText -Item $item
        $pathText = GetQuickSearchResultItemPath -Item $item
        $searchText = "$displayText $pathText"

        if (TestQuickSearchFilterText -SearchText $searchText -FilterText $FilterText) {
            [void]$matchedItems.Add($item)
        }
    }

    return @($matchedItems)
}


Function ConvertQuickSearchFilterTextToTokens {
    param(
        [string]$FilterText
    )

    $tokens = New-Object System.Collections.ArrayList
    $builder = New-Object System.Text.StringBuilder
    $tokenEscaped = $false
    $escapeNext = $false

    foreach ($character in ([string]$FilterText).ToCharArray()) {
        if ($escapeNext) {
            [void]$builder.Append($character)
            $tokenEscaped = $true
            $escapeNext = $false
            continue
        }

        if ($character -eq '`') {
            $escapeNext = $true
            continue
        }

        if ([char]::IsWhiteSpace($character)) {
            if ($builder.Length -gt 0 -or $tokenEscaped) {
                [void]$tokens.Add([PSCustomObject]@{ Text = $builder.ToString(); Escaped = $tokenEscaped })
                [void]$builder.Clear()
                $tokenEscaped = $false
            }
            continue
        }

        [void]$builder.Append($character)
    }

    if ($escapeNext) {
        [void]$builder.Append('`')
        $tokenEscaped = $true
    }

    if ($builder.Length -gt 0 -or $tokenEscaped) {
        [void]$tokens.Add([PSCustomObject]@{ Text = $builder.ToString(); Escaped = $tokenEscaped })
    }

    return @($tokens)
}


Function TestQuickSearchFilterOperator {
    param(
        [object]$Token,
        [string]$Operator
    )

    if ($null -eq $Token -or $Token.Escaped) {
        return $false
    }

    return ([string]$Token.Text).Equals($Operator, [System.StringComparison]::OrdinalIgnoreCase)
}


Function TestQuickSearchFilterText {
    param(
        [string]$SearchText,
        [string]$FilterText
    )

    $tokens = @(ConvertQuickSearchFilterTextToTokens -FilterText $FilterText)
    if ($tokens.Count -eq 0) {
        return $true
    }

    $clauses = New-Object System.Collections.ArrayList
    $currentTerms = New-Object System.Collections.ArrayList
    $negateNext = $false

    foreach ($token in $tokens) {
        if (TestQuickSearchFilterOperator -Token $token -Operator 'or') {
            if ($currentTerms.Count -gt 0) {
                [void]$clauses.Add(@($currentTerms))
            }
            $currentTerms = New-Object System.Collections.ArrayList
            $negateNext = $false
            continue
        }

        if (TestQuickSearchFilterOperator -Token $token -Operator 'and') {
            continue
        }

        if (TestQuickSearchFilterOperator -Token $token -Operator 'not') {
            $negateNext = -not $negateNext
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$token.Text)) {
            [void]$currentTerms.Add([PSCustomObject]@{ Text = [string]$token.Text; Negated = $negateNext })
            $negateNext = $false
        }
    }

    if ($currentTerms.Count -gt 0) {
        [void]$clauses.Add(@($currentTerms))
    }

    if ($clauses.Count -eq 0) {
        return $true
    }

    foreach ($clause in $clauses) {
        $clauseMatched = $true
        foreach ($term in @($clause)) {
            $termMatched = ([string]$SearchText).IndexOf([string]$term.Text, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
            if ($term.Negated) {
                if ($termMatched) {
                    $clauseMatched = $false
                    break
                }
            }
            elseif (-not $termMatched) {
                $clauseMatched = $false
                break
            }
        }

        if ($clauseMatched) {
            return $true
        }
    }

    return $false
}


Function SortQuickSearchResultItems {
    param(
        [object[]]$Items,
        [string]$SortMode = 'NameAsc'
    )

    $sourceItems = @($Items)
    switch ($SortMode) {
        'NameDesc' {
            return @($sourceItems | Sort-Object -Property @{ Expression = { $_.Name }; Descending = $true }, @{ Expression = { $_.Path }; Descending = $true })
        }
        'Modified' {
            return @($sourceItems | Sort-Object -Property @{ Expression = { if ($null -ne $_.LastWriteTime) { $_.LastWriteTime } else { [datetime]::MinValue } }; Descending = $true }, @{ Expression = { $_.Name }; Descending = $false })
        }
        'Created' {
            return @($sourceItems | Sort-Object -Property @{ Expression = { if ($null -ne $_.CreationTime) { $_.CreationTime } else { [datetime]::MinValue } }; Descending = $true }, @{ Expression = { $_.Name }; Descending = $false })
        }
        default {
            return @($sourceItems | Sort-Object -Property @{ Expression = { $_.Name }; Descending = $false }, @{ Expression = { $_.Path }; Descending = $false })
        }
    }
}


Function TestMarkdownFile {
    param(
        [string]$FilePath
    )

    $extension = [System.IO.Path]::GetExtension($FilePath)
    return @('.md', '.markdown') -contains $extension.ToLowerInvariant()
}


Function ConvertTextToRtfText {
    param(
        [string]$Text
    )

    if ($null -eq $Text) {
        return ''
    }

    $builder = New-Object System.Text.StringBuilder
    foreach ($character in $Text.ToCharArray()) {
        $characterCode = [int][char]$character
        if (92 -eq $characterCode) {
            [void]$builder.Append('\\')
        }
        elseif (123 -eq $characterCode) {
            [void]$builder.Append('\{')
        }
        elseif (125 -eq $characterCode) {
            [void]$builder.Append('\}')
        }
        elseif (9 -eq $characterCode) {
            [void]$builder.Append('\tab ')
        }
        elseif ($characterCode -gt 127) {
            if ($characterCode -gt 32767) {
                $characterCode = $characterCode - 65536
            }
            [void]$builder.Append("\u$characterCode?")
        }
        else {
            [void]$builder.Append($character)
        }
    }

    return $builder.ToString()
}


Function ConvertInlineMarkdownToRtf {
    param(
        [string]$Text
    )

    $fragment = ConvertTextToRtfText $Text
    $fragment = [regex]::Replace($fragment, '`([^`]+)`', '{\f1\cf2 $1}')
    $fragment = [regex]::Replace($fragment, '\*\*([^*]+)\*\*', '{\b $1}')
    $fragment = [regex]::Replace($fragment, '(?<!\*)\*([^*]+)\*(?!\*)', '{\i $1}')
    return $fragment
}


Function ConvertMarkdownToRtf {
    param(
        [string]$MarkdownText
    )

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('{\rtf1\ansi\deff0')
    [void]$builder.Append('{\fonttbl{\f0 Segoe UI;}{\f1 Consolas;}}')
    [void]$builder.Append('{\colortbl;\red0\green0\blue0;\red96\green96\blue96;}')
    [void]$builder.Append('\viewkind4\uc1\pard\f0\fs20\cf1 ')

    $insideCodeBlock = $false
    $lines = [regex]::Split([string]$MarkdownText, '\r?\n')
    foreach ($line in $lines) {
        if ($line -match '^\s*```') {
            if ($insideCodeBlock) {
                [void]$builder.Append('\f0\fs20\par ')
                $insideCodeBlock = $false
            }
            else {
                [void]$builder.Append('\par\f1\fs19\cf2 ')
                $insideCodeBlock = $true
            }
            continue
        }

        if ($insideCodeBlock) {
            [void]$builder.Append((ConvertTextToRtfText $line))
            [void]$builder.Append('\line ')
            continue
        }

        if ([string]::IsNullOrWhiteSpace($line)) {
            [void]$builder.Append('\par ')
            continue
        }

        if ($line -match '^(#{1,6})\s+(.+)$') {
            $headingLevel = $Matches[1].Length
            $headingText = ConvertInlineMarkdownToRtf $Matches[2]
            $fontSize = switch ($headingLevel) {
                1 { 36 }
                2 { 30 }
                3 { 26 }
                4 { 24 }
                default { 22 }
            }
            [void]$builder.Append("\b\fs$fontSize $headingText\b0\fs20\par ")
            continue
        }

        if ($line -match '^\s*[-*+]\s+(.+)$') {
            $listText = ConvertInlineMarkdownToRtf $Matches[1]
            [void]$builder.Append("\li360\bullet\tab $listText\li0\par ")
            continue
        }

        if ($line -match '^\s*(\d+[.)])\s+(.+)$') {
            $listNumber = ConvertTextToRtfText $Matches[1]
            $listText = ConvertInlineMarkdownToRtf $Matches[2]
            [void]$builder.Append("\li360 $listNumber\tab $listText\li0\par ")
            continue
        }

        if ($line -match '^\s*>\s?(.+)$') {
            $quoteText = ConvertInlineMarkdownToRtf $Matches[1]
            [void]$builder.Append("\li360\i $quoteText\i0\li0\par ")
            continue
        }

        [void]$builder.Append((ConvertInlineMarkdownToRtf $line))
        [void]$builder.Append('\par ')
    }

    if ($insideCodeBlock) {
        [void]$builder.Append('\f0\fs20\par ')
    }

    [void]$builder.Append('}')
    return $builder.ToString()
}


Function SetPreviewContent {
    param(
        [System.Windows.Forms.RichTextBox]$PreviewBox,
        [string]$FilePath,
        [string]$Content
    )

    if (TestMarkdownFile $FilePath) {
        try {
            $PreviewBox.Rtf = ConvertMarkdownToRtf $Content
            return
        }
        catch {
            Write-Host "Markdown preview failed for $FilePath. Falling back to plain text." -ForegroundColor Yellow
        }
    }

    $PreviewBox.Text = $Content
}


Function ShowQuickSearchAbout {
    param(
        [System.Windows.Forms.Form]$Owner,
        [object]$Config
    )

    $newLine = [Environment]::NewLine
    $versionText = ConvertVersionToTitleSuffix -Version (GetQuickSearchProjectVersion -Config $Config)
    $message = @(
        "QuickSearch $versionText",
        '',
        'Author: Nate Scott (NASCO)',
        'Email: nate.scott@microsoft.com',
        '',
        'Basic use:',
        '1. Choose a drive, type, and search mode.',
        '2. Enter a keyword and click Search.',
        '3. Use Filename/Tags (Quick) for fast indexed TEAM searches.',
        '4. Use Content (Slow) when you need to search inside files.',
        '5. Select a result to preview it, then click Open to launch the file.',
        '6. Open Index to update TEAM index settings or run Re-Index Team Folder.',
        '',
        'Filter syntax:',
        'Use spaces or and to require all terms, for example: access and report',
        'Use or to match either side, for example: access or report',
        'Use not to exclude the next term, for example: access not draft',
        'Use ` to search an operator word literally, for example: access `and report'
    ) -join $newLine

    ShowQuickSearchMessageBox -Owner $Owner -Message $message -Title 'About QuickSearch'
}


Function ConvertQuickSearchByteSizeText {
    param(
        [long]$Bytes
    )

    if ($Bytes -ge 1048576) {
        return ('{0:N2} MB' -f ($Bytes / 1048576))
    }

    if ($Bytes -ge 1024) {
        return ('{0:N1} KB' -f ($Bytes / 1024))
    }

    return ("$Bytes bytes")
}


Function GetQuickSearchPropertyCount {
    param(
        [object]$Value
    )

    if ($null -eq $Value) {
        return 0
    }

    if ($Value -is [System.Collections.IDictionary]) {
        return $Value.Count
    }

    return @($Value.PSObject.Properties).Count
}


Function GetQuickSearchIndexSummaryText {
    param(
        [string]$IndexFilePath
    )

    $newLine = [Environment]::NewLine
    if ([string]::IsNullOrWhiteSpace($IndexFilePath)) {
        return 'Status: Index file is not configured.'
    }

    if (-not (Test-Path -LiteralPath $IndexFilePath -PathType Leaf)) {
        return @(
            'Status: Missing',
            "Index file: $IndexFilePath",
            'Files indexed: 0',
            'Unique generated tags: 0',
            'Search terms: 0'
        ) -join $newLine
    }

    if ($null -ne (Get-Command -Name TestFileIndexShardsAvailable -CommandType Function -ErrorAction SilentlyContinue) -and (TestFileIndexShardsAvailable -IndexFilePath $IndexFilePath)) {
        return GetFileIndexShardedSummaryText -IndexFilePath $IndexFilePath
    }

    try {
        $indexFile = Get-Item -LiteralPath $IndexFilePath -ErrorAction Stop
        $indexData = ReadCachedFileIndexData -IndexFilePath $indexFile.FullName
        if ($null -eq $indexData) {
            throw 'Index data could not be read.'
        }

        $schemaVersion = GetFileIndexPropertyValue -Value $indexData -Name 'schemaVersion'
        if ($null -eq $schemaVersion) { $schemaVersion = 'legacy' }

        $documentsValue = GetFileIndexPropertyValue -Value $indexData -Name 'documents'
        $documents = @()
        if ($null -ne $documentsValue) { $documents = @($documentsValue) }

        $termsValue = GetFileIndexPropertyValue -Value $indexData -Name 'terms'
        $searchTermCount = GetQuickSearchPropertyCount -Value $termsValue
        $uniqueGeneratedTags = @{}
        $tagAssignmentCount = 0
        foreach ($document in $documents) {
            $tagsValue = GetFileIndexPropertyValue -Value $document -Name 'tags'
            if ($null -eq $tagsValue) {
                continue
            }

            foreach ($tag in @($tagsValue)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$tag)) {
                    $uniqueGeneratedTags[[string]$tag] = $true
                    $tagAssignmentCount++
                }
            }
        }

        $createdUtc = GetFileIndexPropertyValue -Value $indexData -Name 'createdUtc'
        if ($null -eq $createdUtc) { $createdUtc = 'unknown' }
        $createdUtcText = [string]$createdUtc
        if ($createdUtc -is [datetime]) {
            $createdUtcText = $createdUtc.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss') + 'Z'
        }

        return @(
            'Status: Ready',
            "Files indexed: $($documents.Count)",
            "Unique generated tags: $($uniqueGeneratedTags.Count)",
            "Search terms: $searchTermCount",
            "Tag assignments: $tagAssignmentCount",
            "Schema version: $schemaVersion",
            "Created UTC: $createdUtcText",
            "Updated: $($indexFile.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))",
            "Index size: $(ConvertQuickSearchByteSizeText -Bytes $indexFile.Length)"
        ) -join $newLine
    }
    catch {
        return @(
            'Status: Error reading index data',
            "Index file: $IndexFilePath",
            "Error: $($_.Exception.Message)"
        ) -join $newLine
    }
}


Function GetQuickSearchIndexFileSummaryText {
    param(
        [string]$IndexFilePath
    )

    $newLine = [Environment]::NewLine
    if ([string]::IsNullOrWhiteSpace($IndexFilePath)) {
        return 'Status: Index file is not configured.'
    }

    if (-not (Test-Path -LiteralPath $IndexFilePath -PathType Leaf)) {
        return @(
            'Status: Missing',
            "Index file: $IndexFilePath",
            'Files indexed: 0',
            'Unique generated tags: 0',
            'Search terms: 0'
        ) -join $newLine
    }

    try {
        $indexFile = Get-Item -LiteralPath $IndexFilePath -ErrorAction Stop
        $indexSizeText = ConvertQuickSearchByteSizeText -Bytes $indexFile.Length
        if ($null -ne (Get-Command -Name TestFileIndexShardsAvailable -CommandType Function -ErrorAction SilentlyContinue) -and (TestFileIndexShardsAvailable -IndexFilePath $IndexFilePath)) {
            $manifest = ReadFileIndexShardManifest -IndexFilePath $IndexFilePath
            $indexSizeText = ConvertQuickSearchByteSizeText -Bytes (GetFileIndexShardDirectorySizeBytes -IndexFilePath $IndexFilePath -Manifest $manifest)
        }

        return @(
            'Status: Ready',
            "Index file: $IndexFilePath",
            "Updated: $($indexFile.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))",
            "Index size: $indexSizeText",
            'Click Refresh Data for full index counts.'
        ) -join $newLine
    }
    catch {
        return @(
            'Status: Error reading index file',
            "Index file: $IndexFilePath",
            "Error: $($_.Exception.Message)"
        ) -join $newLine
    }
}

Function ShowIndexSettings {
    param(
        [System.Windows.Forms.Form]$Owner,
        [object]$Config,
        [string]$ConfigPath,
        [string]$IndexFilePath,
        [string]$DriveLetter,
        [string]$ProfilesDirectory = ''
    )

    $settingsForm = New-Object System.Windows.Forms.Form
    $settingsForm.Text = 'Index Settings'
    $settingsForm.ClientSize = New-Object System.Drawing.Size(660, 500)
    $settingsForm.AutoSize = $false
    $settingsForm.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $settingsForm.FormBorderStyle = 'FixedDialog'
    $settingsForm.StartPosition = 'CenterParent'
    $settingsForm.MaximizeBox = $false
    $settingsForm.MinimizeBox = $false

    $labelLeft = 18
    $labelWidth = 145
    $inputLeft = 180
    $inputWidth = 450

    $Label_DocPath = New-Object System.Windows.Forms.Label
    $Label_DocPath.Text = 'Doc path template'
    $Label_DocPath.Location = New-Object System.Drawing.Point($labelLeft, 20)
    $Label_DocPath.Width = $labelWidth
    $settingsForm.Controls.Add($Label_DocPath)

    $TextBox_DocPath = New-Object System.Windows.Forms.TextBox
    $TextBox_DocPath.Text = GetDocPathTemplate $Config
    $TextBox_DocPath.Location = New-Object System.Drawing.Point($inputLeft, 18)
    $TextBox_DocPath.Width = $inputWidth
    $settingsForm.Controls.Add($TextBox_DocPath)

    $Label_TeamPath = New-Object System.Windows.Forms.Label
    $Label_TeamPath.Text = 'TEAM path template'
    $Label_TeamPath.Location = New-Object System.Drawing.Point($labelLeft, 55)
    $Label_TeamPath.Width = $labelWidth
    $settingsForm.Controls.Add($Label_TeamPath)

    $TextBox_TeamPath = New-Object System.Windows.Forms.TextBox
    $TextBox_TeamPath.Text = GetTeamPathTemplate $Config
    $TextBox_TeamPath.Location = New-Object System.Drawing.Point($inputLeft, 53)
    $TextBox_TeamPath.Width = $inputWidth
    $settingsForm.Controls.Add($TextBox_TeamPath)

    $Label_ResolvedDocPath = New-Object System.Windows.Forms.Label
    $Label_ResolvedDocPath.Text = 'Resolved doc path'
    $Label_ResolvedDocPath.Location = New-Object System.Drawing.Point($labelLeft, 90)
    $Label_ResolvedDocPath.Width = $labelWidth
    $settingsForm.Controls.Add($Label_ResolvedDocPath)

    $TextBox_ResolvedDocPath = New-Object System.Windows.Forms.TextBox
    $TextBox_ResolvedDocPath.Text = ResolveConfiguredPath -DriveLetter $DriveLetter -PathTemplate $TextBox_DocPath.Text
    $TextBox_ResolvedDocPath.Location = New-Object System.Drawing.Point($inputLeft, 88)
    $TextBox_ResolvedDocPath.Width = $inputWidth
    $TextBox_ResolvedDocPath.ReadOnly = $true
    $settingsForm.Controls.Add($TextBox_ResolvedDocPath)

    $Label_ResolvedTeamPath = New-Object System.Windows.Forms.Label
    $Label_ResolvedTeamPath.Text = 'Resolved TEAM path'
    $Label_ResolvedTeamPath.Location = New-Object System.Drawing.Point($labelLeft, 125)
    $Label_ResolvedTeamPath.Width = $labelWidth
    $settingsForm.Controls.Add($Label_ResolvedTeamPath)

    $TextBox_ResolvedTeamPath = New-Object System.Windows.Forms.TextBox
    $TextBox_ResolvedTeamPath.Text = ResolveConfiguredPath -DriveLetter $DriveLetter -PathTemplate $TextBox_TeamPath.Text
    $TextBox_ResolvedTeamPath.Location = New-Object System.Drawing.Point($inputLeft, 123)
    $TextBox_ResolvedTeamPath.Width = $inputWidth
    $TextBox_ResolvedTeamPath.ReadOnly = $true
    $settingsForm.Controls.Add($TextBox_ResolvedTeamPath)

    $Label_TagCount = New-Object System.Windows.Forms.Label
    $Label_TagCount.Text = 'Top words per file'
    $Label_TagCount.Location = New-Object System.Drawing.Point($labelLeft, 160)
    $Label_TagCount.Width = $labelWidth
    $settingsForm.Controls.Add($Label_TagCount)

    $NumericUpDown_TagCount = New-Object System.Windows.Forms.NumericUpDown
    $NumericUpDown_TagCount.Location = New-Object System.Drawing.Point($inputLeft, 158)
    $NumericUpDown_TagCount.Width = 80
    $NumericUpDown_TagCount.Minimum = 1
    $NumericUpDown_TagCount.Maximum = 100
    $NumericUpDown_TagCount.Value = [Math]::Min(100, [Math]::Max(1, [int]$Config.TagCount))
    $settingsForm.Controls.Add($NumericUpDown_TagCount)

    $Label_IgnoredFilenames = New-Object System.Windows.Forms.Label
    $Label_IgnoredFilenames.Text = 'Ignored filenames'
    $Label_IgnoredFilenames.Location = New-Object System.Drawing.Point($labelLeft, 195)
    $Label_IgnoredFilenames.Width = $labelWidth
    $settingsForm.Controls.Add($Label_IgnoredFilenames)

    $TextBox_IgnoredFilenames = New-Object System.Windows.Forms.TextBox
    $TextBox_IgnoredFilenames.Text = ConvertArrayToDelimitedText @($Config.IgnoredFilenames)
    $TextBox_IgnoredFilenames.Location = New-Object System.Drawing.Point($inputLeft, 193)
    $TextBox_IgnoredFilenames.Width = $inputWidth
    $settingsForm.Controls.Add($TextBox_IgnoredFilenames)

    $Label_IgnoredExtensions = New-Object System.Windows.Forms.Label
    $Label_IgnoredExtensions.Text = 'Ignored extensions'
    $Label_IgnoredExtensions.Location = New-Object System.Drawing.Point($labelLeft, 230)
    $Label_IgnoredExtensions.Width = $labelWidth
    $settingsForm.Controls.Add($Label_IgnoredExtensions)

    $TextBox_IgnoredExtensions = New-Object System.Windows.Forms.TextBox
    $TextBox_IgnoredExtensions.Text = ConvertArrayToDelimitedText @($Config.IgnoredFileExtNames)
    $TextBox_IgnoredExtensions.Location = New-Object System.Drawing.Point($inputLeft, 228)
    $TextBox_IgnoredExtensions.Width = $inputWidth
    $settingsForm.Controls.Add($TextBox_IgnoredExtensions)

    $Label_AllowedExtensions = New-Object System.Windows.Forms.Label
    $Label_AllowedExtensions.Text = 'Allowed extensions'
    $Label_AllowedExtensions.Location = New-Object System.Drawing.Point($labelLeft, 265)
    $Label_AllowedExtensions.Width = $labelWidth
    $settingsForm.Controls.Add($Label_AllowedExtensions)

    $TextBox_AllowedExtensions = New-Object System.Windows.Forms.TextBox
    $TextBox_AllowedExtensions.Text = ConvertArrayToDelimitedText @($Config.AllowedFileExtNames)
    $TextBox_AllowedExtensions.Location = New-Object System.Drawing.Point($inputLeft, 263)
    $TextBox_AllowedExtensions.Width = $inputWidth
    $settingsForm.Controls.Add($TextBox_AllowedExtensions)

    $Label_IgnoredFolders = New-Object System.Windows.Forms.Label
    $Label_IgnoredFolders.Text = 'Ignored folders'
    $Label_IgnoredFolders.Location = New-Object System.Drawing.Point($labelLeft, 300)
    $Label_IgnoredFolders.Width = $labelWidth
    $settingsForm.Controls.Add($Label_IgnoredFolders)

    $TextBox_IgnoredFolders = New-Object System.Windows.Forms.TextBox
    $TextBox_IgnoredFolders.Text = ConvertArrayToDelimitedText @($Config.Ignored)
    $TextBox_IgnoredFolders.Location = New-Object System.Drawing.Point($inputLeft, 298)
    $TextBox_IgnoredFolders.Width = $inputWidth
    $settingsForm.Controls.Add($TextBox_IgnoredFolders)

    $Label_IndexData = New-Object System.Windows.Forms.Label
    $Label_IndexData.Text = 'Index data'
    $Label_IndexData.Location = New-Object System.Drawing.Point($labelLeft, 340)
    $Label_IndexData.Width = $labelWidth
    $settingsForm.Controls.Add($Label_IndexData)

    $TextBox_IndexData = New-Object System.Windows.Forms.TextBox
    $TextBox_IndexData.Location = New-Object System.Drawing.Point($inputLeft, 338)
    $TextBox_IndexData.Width = $inputWidth
    $TextBox_IndexData.Height = 82
    $TextBox_IndexData.Multiline = $true
    $TextBox_IndexData.ReadOnly = $true
    $TextBox_IndexData.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $settingsForm.Controls.Add($TextBox_IndexData)

    $Button_RefreshIndexData = New-Object System.Windows.Forms.Button
    $Button_RefreshIndexData.Text = 'Refresh Data'
    $Button_RefreshIndexData.Location = New-Object System.Drawing.Point($inputLeft, 425)
    $Button_RefreshIndexData.Width = 95
    $settingsForm.Controls.Add($Button_RefreshIndexData)

    $Label_Status = New-Object System.Windows.Forms.Label
    $Label_Status.Text = 'Ready'
    $Label_Status.Location = New-Object System.Drawing.Point(285, 428)
    $Label_Status.Width = 355
    $settingsForm.Controls.Add($Label_Status)

    $Button_Save = New-Object System.Windows.Forms.Button
    $Button_Save.Text = 'Save'
    $Button_Save.Location = New-Object System.Drawing.Point(470, 465)
    $Button_Save.Width = 80
    $settingsForm.Controls.Add($Button_Save)

    $Button_RebuildIndex = New-Object System.Windows.Forms.Button
    $Button_RebuildIndex.Text = 'Re-Index Team Folder'
    $Button_RebuildIndex.Location = New-Object System.Drawing.Point($labelLeft, 465)
    $Button_RebuildIndex.Width = 150
    $settingsForm.Controls.Add($Button_RebuildIndex)

    $Button_Close = New-Object System.Windows.Forms.Button
    $Button_Close.Text = 'Close'
    $Button_Close.Location = New-Object System.Drawing.Point(560, 465)
    $Button_Close.Width = 80
    $settingsForm.Controls.Add($Button_Close)

    $refreshIndexData = {
        $TextBox_IndexData.Text = GetQuickSearchIndexSummaryText -IndexFilePath $IndexFilePath
    }
    $refreshIndexFileData = {
        $TextBox_IndexData.Text = GetQuickSearchIndexFileSummaryText -IndexFilePath $IndexFilePath
    }
    & $refreshIndexFileData

    $saveSettings = {
        $docPathTemplate = $TextBox_DocPath.Text.Trim()
        SetConfigValue -Config $Config -Name 'DocPath' -Value $docPathTemplate
        SetConfigValue -Config $Config -Name 'Path' -Value $docPathTemplate
        SetConfigValue -Config $Config -Name 'DriveLetter' -Value $DriveLetter
        SetConfigValue -Config $Config -Name 'TeamPath' -Value $TextBox_TeamPath.Text.Trim()
        SetConfigValue -Config $Config -Name 'TagCount' -Value ([int]$NumericUpDown_TagCount.Value)
        SetConfigValue -Config $Config -Name 'IgnoredFilenames' -Value @(ConvertDelimitedTextToArray $TextBox_IgnoredFilenames.Text)
        SetConfigValue -Config $Config -Name 'AllowedFileExtNames' -Value @(ConvertDelimitedTextToArray $TextBox_AllowedExtensions.Text)
        SetConfigValue -Config $Config -Name 'IgnoredFileExtNames' -Value @(ConvertDelimitedTextToArray $TextBox_IgnoredExtensions.Text)
        SetConfigValue -Config $Config -Name 'Ignored' -Value @(ConvertDelimitedTextToArray $TextBox_IgnoredFolders.Text)
        SaveConfig -Config $Config -ConfigPath $ConfigPath
        $profileSaveResult = SaveQuickSearchProfilePathSettings -Config $Config -ProfilesDirectory $ProfilesDirectory -DriveLetter $DriveLetter
        $TextBox_ResolvedDocPath.Text = ResolveConfiguredPath -DriveLetter $DriveLetter -PathTemplate $Config.DocPath
        $TextBox_ResolvedTeamPath.Text = ResolveConfiguredPath -DriveLetter $DriveLetter -PathTemplate $Config.TeamPath
        if ($null -ne $profileSaveResult) {
            $Label_Status.Text = "Saved config and profile: $($profileSaveResult.Name)"
        }
        else {
            $Label_Status.Text = "Saved to $ConfigPath"
        }
        & $refreshIndexFileData
    }

    $TextBox_DocPath.Add_TextChanged({
        $TextBox_ResolvedDocPath.Text = ResolveConfiguredPath -DriveLetter $DriveLetter -PathTemplate $TextBox_DocPath.Text
    })

    $TextBox_TeamPath.Add_TextChanged({
        $TextBox_ResolvedTeamPath.Text = ResolveConfiguredPath -DriveLetter $DriveLetter -PathTemplate $TextBox_TeamPath.Text
    })

    $Button_Save.Add_Click($saveSettings)
    $Button_RefreshIndexData.Add_Click({
        $Label_Status.Text = 'Refreshing index data...'
        $Button_RefreshIndexData.Enabled = $false
        try {
            & $refreshIndexData
            $Label_Status.Text = 'Index data refreshed'
        }
        finally {
            $Button_RefreshIndexData.Enabled = $true
        }
    })

    $Button_RebuildIndex.Add_Click({
        & $saveSettings
        $teamRoot = ResolveConfiguredPath -DriveLetter $DriveLetter -PathTemplate $Config.TeamPath
        if ([string]::IsNullOrWhiteSpace($teamRoot) -or -not (Test-Path -LiteralPath $teamRoot)) {
            $Label_Status.Text = "TEAM path not found: $teamRoot"
            ShowQuickSearchMessageBox -Owner $settingsForm -Message "TEAM path cannot be found: $teamRoot" -Title 'Path Not Found'
            return
        }

        $Label_Status.Text = 'Re-indexing TEAM folder...'
        $Button_Save.Enabled = $false
        $Button_RebuildIndex.Enabled = $false
        try {
            $created = InvokeFileIndexWithProcessingDialog -Owner $settingsForm -Title 'Index Team Folder' -Message 'Indexing in progress, this may take up to 10 minutes, please wait...' -Root $teamRoot -Config $Config -IndexFilePath $IndexFilePath
        }
        finally {
            $Button_Save.Enabled = $true
            $Button_RebuildIndex.Enabled = $true
        }
        if ($created) {
            $Label_Status.Text = "Index rebuilt: $IndexFilePath"
            & $refreshIndexData
        }
        else {
            $Label_Status.Text = 'Index rebuild failed.'
        }
    })

    $Button_Close.Add_Click({
        $settingsForm.Close()
    })

    $settingsForm.AcceptButton = $Button_Save
    $settingsForm.CancelButton = $Button_Close

    SetQuickSearchDialogCenter -Dialog $settingsForm -Owner $Owner
    [void]$settingsForm.ShowDialog($Owner)
}

<#
.SYNOPSIS
    Countdown timer.
#>
Function Countdown()
{
    $time = $timer
    Write-Host "[ Countdown($time) ]`n" -ForegroundColor Cyan
    while ($time -ge 0) {
        if ($msgType -eq 2) {
            Write-Host " TSG Organizer will check all TSGs in $time seconds..." -ForegroundColor Green
        }

        $time = $time - 1
        Start-Sleep -Seconds 1
    }
    Write-Host "`n"
}
