Function TestHtmlFile {
    param(
        [string]$FilePath
    )

    $extension = [System.IO.Path]::GetExtension($FilePath)
    return @('.html', '.htm') -contains $extension.ToLowerInvariant()
}


Function TestMarkdownHtmlContent {
    param(
        [string]$Content
    )

    if ([string]::IsNullOrWhiteSpace($Content)) {
        return $false
    }

    return [regex]::IsMatch($Content, '</?[A-Za-z][A-Za-z0-9:-]*(\s+[^>]*)?/?>')
}


Function ConvertTextToHtmlText {
    param(
        [string]$Text
    )

    if ($null -eq $Text) {
        return ''
    }

    return [System.Net.WebUtility]::HtmlEncode($Text)
}


Function RemoveQuickSearchActiveHtml {
    param(
        [string]$Html
    )

    if ([string]::IsNullOrEmpty($Html)) {
        return ''
    }

    $safeHtml = [regex]::Replace($Html, '(?is)<\s*(script|object|embed|iframe)\b[^>]*>.*?</\s*\1\s*>', '')
    $safeHtml = [regex]::Replace($safeHtml, '(?is)<\s*(script|object|embed|iframe)\b[^>]*?/?>', '')
    $safeHtml = [regex]::Replace($safeHtml, '(?i)\s+on[a-z]+\s*=\s*("[^"]*"|''[^'']*''|[^\s>]+)', '')
    $safeHtml = [regex]::Replace($safeHtml, '(?i)(href|src)\s*=\s*("\s*javascript:[^"]*"|''\s*javascript:[^'']*''|javascript:[^\s>]+)', '$1="#"')
    return $safeHtml
}


Function ConvertTextWithHtmlTagsToHtml {
    param(
        [string]$Text
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return ''
    }

    $builder = New-Object System.Text.StringBuilder
    $tagMatches = [regex]::Matches($Text, '</?[A-Za-z][^>]*>')
    $lastIndex = 0

    foreach ($tagMatch in $tagMatches) {
        if ($tagMatch.Index -gt $lastIndex) {
            [void]$builder.Append((ConvertTextToHtmlText $Text.Substring($lastIndex, $tagMatch.Index - $lastIndex)))
        }

        [void]$builder.Append((RemoveQuickSearchActiveHtml $tagMatch.Value))
        $lastIndex = $tagMatch.Index + $tagMatch.Length
    }

    if ($lastIndex -lt $Text.Length) {
        [void]$builder.Append((ConvertTextToHtmlText $Text.Substring($lastIndex)))
    }

    return $builder.ToString()
}


Function ConvertInlineMarkdownToHtml {
    param(
        [string]$Text
    )

    $fragment = ConvertTextWithHtmlTagsToHtml $Text
    $fragment = [regex]::Replace($fragment, '`([^`]+)`', '<code>$1</code>')
    $fragment = [regex]::Replace($fragment, '\*\*([^*]+)\*\*', '<strong>$1</strong>')
    $fragment = [regex]::Replace($fragment, '(?<!\*)\*([^*]+)\*(?!\*)', '<em>$1</em>')
    return $fragment
}


Function ConvertMarkdownToHtml {
    param(
        [string]$MarkdownText
    )

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('<article class="qs-markdown">')

    $insideCodeBlock = $false
    $lines = [regex]::Split([string]$MarkdownText, '\r?\n')
    foreach ($line in $lines) {
        if ($line -match '^\s*```') {
            if ($insideCodeBlock) {
                [void]$builder.Append('</code></pre>')
                $insideCodeBlock = $false
            }
            else {
                [void]$builder.Append('<pre><code>')
                $insideCodeBlock = $true
            }
            continue
        }

        if ($insideCodeBlock) {
            [void]$builder.Append((ConvertTextToHtmlText $line))
            [void]$builder.Append("`n")
            continue
        }

        if ([string]::IsNullOrWhiteSpace($line)) {
            [void]$builder.Append('<p></p>')
            continue
        }

        if ($line -match '^(#{1,6})\s+(.+)$') {
            $level = [Math]::Min(6, $Matches[1].Length)
            [void]$builder.Append("<h$level>")
            [void]$builder.Append((ConvertInlineMarkdownToHtml $Matches[2]))
            [void]$builder.Append("</h$level>")
            continue
        }

        if ($line -match '^\s*[-*+]\s+(.+)$') {
            [void]$builder.Append('<ul><li>')
            [void]$builder.Append((ConvertInlineMarkdownToHtml $Matches[1]))
            [void]$builder.Append('</li></ul>')
            continue
        }

        if ($line -match '^\s*(\d+[.)])\s+(.+)$') {
            [void]$builder.Append('<ol><li>')
            [void]$builder.Append((ConvertInlineMarkdownToHtml $Matches[2]))
            [void]$builder.Append('</li></ol>')
            continue
        }

        if ($line -match '^\s*>\s?(.+)$') {
            [void]$builder.Append('<blockquote>')
            [void]$builder.Append((ConvertInlineMarkdownToHtml $Matches[1]))
            [void]$builder.Append('</blockquote>')
            continue
        }

        if ($line -match '^\s*</?(article|aside|blockquote|br|details|div|dl|fieldset|figcaption|figure|footer|form|h[1-6]|header|hr|li|main|nav|ol|p|pre|section|table|tbody|td|tfoot|th|thead|tr|ul)\b') {
            [void]$builder.Append((RemoveQuickSearchActiveHtml $line))
            continue
        }

        [void]$builder.Append('<p>')
        [void]$builder.Append((ConvertInlineMarkdownToHtml $line))
        [void]$builder.Append('</p>')
    }

    if ($insideCodeBlock) {
        [void]$builder.Append('</code></pre>')
    }

    [void]$builder.Append('</article>')
    return $builder.ToString()
}


Function AddQuickSearchHtmlKeywordHighlight {
    param(
        [string]$Html,
        [string]$Keyword
    )

    if ([string]::IsNullOrWhiteSpace($Html) -or [string]::IsNullOrWhiteSpace($Keyword)) {
        return $Html
    }

    $escapedKeyword = [regex]::Escape($Keyword)
    $builder = New-Object System.Text.StringBuilder
    $tagMatches = [regex]::Matches($Html, '<[^>]+>')
    $lastIndex = 0
    $replaceOptions = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    $highlightState = [PSCustomObject]@{ Count = 0 }
    $highlightEvaluator = [System.Text.RegularExpressions.MatchEvaluator]{
        param([System.Text.RegularExpressions.Match]$Match)

        $highlightState.Count++
        if ($highlightState.Count -eq 1) {
            return '<span id="qs-active-highlight" class="qs-highlight">' + $Match.Value + '</span>'
        }

        return '<span class="qs-highlight">' + $Match.Value + '</span>'
    }

    foreach ($tagMatch in $tagMatches) {
        if ($tagMatch.Index -gt $lastIndex) {
            $segment = $Html.Substring($lastIndex, $tagMatch.Index - $lastIndex)
            $segment = [regex]::Replace($segment, $escapedKeyword, $highlightEvaluator, $replaceOptions)
            [void]$builder.Append($segment)
        }

        [void]$builder.Append($tagMatch.Value)
        $lastIndex = $tagMatch.Index + $tagMatch.Length
    }

    if ($lastIndex -lt $Html.Length) {
        $segment = $Html.Substring($lastIndex)
        $segment = [regex]::Replace($segment, $escapedKeyword, $highlightEvaluator, $replaceOptions)
        [void]$builder.Append($segment)
    }

    return $builder.ToString()
}


Function ScrollQuickSearchBrowserToHighlight {
    param(
        [System.Windows.Forms.WebBrowser]$Browser
    )

    if ($null -eq $Browser) {
        return
    }

    try {
        if ($null -ne $Browser.Document) {
            $highlightElement = $Browser.Document.GetElementById('qs-active-highlight')
            if ($null -ne $highlightElement) {
                $highlightElement.ScrollIntoView($true)
            }
        }
    }
    catch {
    }
}


Function SetQuickSearchWebBrowserDocument {
    param(
        [System.Windows.Forms.WebBrowser]$Browser,
        [string]$Html,
        [switch]$ScrollToHighlight
    )

    if ($null -eq $Browser) {
        return
    }

    $documentWritten = $false
    try {
        if (-not $Browser.IsHandleCreated) {
            [void]$Browser.Handle
        }

        if ($null -ne $Browser.Document) {
            [void]$Browser.Document.OpenNew($true)
            $Browser.Document.Write($Html)
            $documentWritten = $true
        }
    }
    catch {
    }

    if (-not $documentWritten) {
        $Browser.DocumentText = $Html
    }

    [System.Windows.Forms.Application]::DoEvents()
    if ($ScrollToHighlight) {
        ScrollQuickSearchBrowserToHighlight -Browser $Browser
    }
}


Function NewQuickSearchFindButtonIcon {
    $bitmap = New-Object System.Drawing.Bitmap(16, 16)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(45, 45, 45), 2)

    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.DrawEllipse($pen, 2, 2, 8, 8)
        $graphics.DrawLine($pen, 9, 9, 14, 14)
    }
    finally {
        $pen.Dispose()
        $graphics.Dispose()
    }

    return $bitmap
}


Function GetQuickSearchPreviewStyle {
    return '<style>body{font-family:Segoe UI,Arial,sans-serif;font-size:10pt;margin:12px;color:#111;background:#fff;}pre,code{font-family:Consolas,monospace;}pre{background:#f5f5f5;padding:8px;white-space:pre-wrap;}blockquote{border-left:3px solid #9aa1aa;margin-left:0;padding-left:10px;color:#444;}table{border-collapse:collapse;}td,th{border:1px solid #ccc;padding:4px 6px;}.qs-highlight{background:#fff27d;color:#111;font-weight:700;}</style>'
}


Function NewQuickSearchHtmlDocument {
    param(
        [string]$BodyHtml
    )

    $style = GetQuickSearchPreviewStyle
    return '<!doctype html><html><head><meta http-equiv="X-UA-Compatible" content="IE=edge"><meta charset="utf-8">' + $style + '</head><body>' + $BodyHtml + '</body></html>'
}


Function ConvertHtmlToPreviewDocument {
    param(
        [string]$Html,
        [string]$Keyword
    )

    $safeHtml = RemoveQuickSearchActiveHtml $Html
    $bodyRegex = [regex]::new('(?is)<body\b[^>]*>(.*?)</body>')
    $bodyMatch = $bodyRegex.Match($safeHtml)
    if ($bodyMatch.Success) {
        $bodyContentGroup = $bodyMatch.Groups[1]
        $highlightedBody = AddQuickSearchHtmlKeywordHighlight -Html $bodyContentGroup.Value -Keyword $Keyword
        $highlightedHtml = $safeHtml.Substring(0, $bodyContentGroup.Index) + $highlightedBody + $safeHtml.Substring($bodyContentGroup.Index + $bodyContentGroup.Length)
    }
    else {
        $highlightedHtml = AddQuickSearchHtmlKeywordHighlight -Html $safeHtml -Keyword $Keyword
    }
    $style = GetQuickSearchPreviewStyle

    if ($highlightedHtml -match '(?is)<html\b') {
        if ($highlightedHtml -match '(?is)</head>') {
            $headEndRegex = [regex]::new('</head>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            return $headEndRegex.Replace($highlightedHtml, "$style</head>", 1)
        }

        $htmlStartRegex = [regex]::new('<html\b[^>]*>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        return $htmlStartRegex.Replace($highlightedHtml, '$0<head>' + $style + '</head>', 1)
    }

    return NewQuickSearchHtmlDocument -BodyHtml $highlightedHtml
}


Function NewQuickSearchPreviewHost {
    param(
        [System.Windows.Forms.RichTextBox]$TextBox,
        [System.Windows.Forms.WebBrowser]$Browser,
        [System.Windows.Forms.TextBox]$SearchTextBox = $null,
        [System.Windows.Forms.Button]$SearchButton = $null
    )

    return [PSCustomObject]@{
        TextBox = $TextBox
        Browser = $Browser
        SearchTextBox = $SearchTextBox
        SearchButton = $SearchButton
        ActiveView = 'Text'
        Expanded = $false
    }
}


Function SetQuickSearchPreviewHostBounds {
    param(
        [object]$PreviewHost,
        [System.Drawing.Point]$Location,
        [int]$Width,
        [int]$Height
    )

    $contentLocation = $Location
    $contentHeight = $Height
    $searchTextBox = $PreviewHost.SearchTextBox
    $searchButton = $PreviewHost.SearchButton
    if ($null -ne $searchTextBox -and $null -ne $searchButton) {
        $searchButtonWidth = 76
        $searchGap = 6
        $searchHeight = 22
        $searchTextWidth = [Math]::Max(120, $Width - $searchButtonWidth - $searchGap)
        $searchTextBox.Location = $Location
        $searchTextBox.Width = $searchTextWidth
        $searchTextBox.Height = 20
        $searchButton.Location = New-Object System.Drawing.Point(($Location.X + $searchTextWidth + $searchGap), $Location.Y)
        $searchButton.Width = $searchButtonWidth
        $searchButton.Height = 22
        $contentLocation = New-Object System.Drawing.Point($Location.X, ($Location.Y + $searchHeight + $searchGap))
        $contentHeight = [Math]::Max(80, $Height - $searchHeight - $searchGap)
    }

    foreach ($previewControl in @($PreviewHost.TextBox, $PreviewHost.Browser)) {
        $previewControl.Location = $contentLocation
        $previewControl.Width = $Width
        $previewControl.Height = $contentHeight
    }
}


Function UpdateQuickSearchPreviewHostVisibility {
    param(
        [object]$PreviewHost
    )

    $showHtml = $PreviewHost.Expanded -and ('Html' -eq $PreviewHost.ActiveView)
    $showText = $PreviewHost.Expanded -and (-not $showHtml)
    $PreviewHost.Browser.Visible = $showHtml
    $PreviewHost.TextBox.Visible = $showText
    foreach ($searchControl in @($PreviewHost.SearchTextBox, $PreviewHost.SearchButton)) {
        if ($null -ne $searchControl) {
            $searchControl.Visible = $PreviewHost.Expanded
        }
    }
}


Function DrawQuickSearchHighlightedListText {
    param(
        [System.Drawing.Graphics]$Graphics,
        [System.Drawing.Rectangle]$Bounds,
        [string]$Text,
        [string]$Keyword,
        [System.Drawing.Font]$Font,
        [System.Drawing.Brush]$TextBrush
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return
    }

    if ([string]::IsNullOrWhiteSpace($Keyword) -or $Text.IndexOf($Keyword, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
        $Graphics.DrawString($Text, $Font, $TextBrush, $Bounds.X, $Bounds.Y)
        return
    }

    $highlightBackBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 242, 125))
    $highlightTextBrush = [System.Drawing.Brushes]::Black
    $currentX = [single]$Bounds.X
    $currentIndex = 0

    try {
        while ($currentIndex -lt $Text.Length) {
            $matchIndex = $Text.IndexOf($Keyword, $currentIndex, [System.StringComparison]::OrdinalIgnoreCase)
            if ($matchIndex -lt 0) {
                $tailText = $Text.Substring($currentIndex)
                $Graphics.DrawString($tailText, $Font, $TextBrush, $currentX, $Bounds.Y)
                break
            }

            if ($matchIndex -gt $currentIndex) {
                $normalText = $Text.Substring($currentIndex, $matchIndex - $currentIndex)
                $Graphics.DrawString($normalText, $Font, $TextBrush, $currentX, $Bounds.Y)
                $currentX += $Graphics.MeasureString($normalText, $Font).Width
            }

            $matchText = $Text.Substring($matchIndex, $Keyword.Length)
            $matchSize = $Graphics.MeasureString($matchText, $Font)
            $highlightRectangle = New-Object System.Drawing.RectangleF($currentX, [single]$Bounds.Y, $matchSize.Width, [single]$Bounds.Height)
            $Graphics.FillRectangle($highlightBackBrush, $highlightRectangle)
            $Graphics.DrawString($matchText, $Font, $highlightTextBrush, $currentX, $Bounds.Y)
            $currentX += $matchSize.Width
            $currentIndex = $matchIndex + [Math]::Max(1, $Keyword.Length)
        }
    }
    finally {
        $highlightBackBrush.Dispose()
    }
}


Function GetQuickSearchMeasuredTextWidth {
    param(
        [System.Drawing.Graphics]$Graphics,
        [System.Drawing.Font]$Font,
        [string]$Text
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return 0
    }

    return $Graphics.MeasureString($Text, $Font).Width
}


Function GetQuickSearchEllipsizedText {
    param(
        [System.Drawing.Graphics]$Graphics,
        [System.Drawing.Font]$Font,
        [string]$Text,
        [int]$MaxWidth
    )

    if ([string]::IsNullOrEmpty($Text) -or $MaxWidth -le 0) {
        return '...'
    }

    if ((GetQuickSearchMeasuredTextWidth -Graphics $Graphics -Font $Font -Text $Text) -le $MaxWidth) {
        return $Text
    }

    $ellipsis = '...'
    if ((GetQuickSearchMeasuredTextWidth -Graphics $Graphics -Font $Font -Text $ellipsis) -gt $MaxWidth) {
        return $ellipsis
    }

    $left = 0
    $right = $Text.Length
    $bestText = $ellipsis
    while ($left -le $right) {
        $mid = [int](($left + $right) / 2)
        if ($mid -le 0) {
            $candidate = $ellipsis
        }
        else {
            $candidate = $ellipsis + $Text.Substring($Text.Length - $mid)
        }

        if ((GetQuickSearchMeasuredTextWidth -Graphics $Graphics -Font $Font -Text $candidate) -le $MaxWidth) {
            $bestText = $candidate
            $left = $mid + 1
        }
        else {
            $right = $mid - 1
        }
    }

    return $bestText
}


Function GetQuickSearchResultItemDisplayTextForWidth {
    param(
        [object]$Item,
        [System.Drawing.Graphics]$Graphics,
        [System.Drawing.Font]$Font,
        [int]$MaxWidth
    )

    $displayText = GetQuickSearchResultItemDisplayText -Item $Item
    if ([string]::IsNullOrEmpty($displayText) -or $null -eq $Graphics -or $null -eq $Font -or $MaxWidth -le 0) {
        return $displayText
    }

    if ((GetQuickSearchMeasuredTextWidth -Graphics $Graphics -Font $Font -Text $displayText) -le $MaxWidth) {
        return $displayText
    }

    $metadataProperty = $Item.PSObject.Properties['MetadataText']
    $pathProperty = $Item.PSObject.Properties['Path']
    if ($null -eq $metadataProperty -or $null -eq $pathProperty) {
        return GetQuickSearchEllipsizedText -Graphics $Graphics -Font $Font -Text $displayText -MaxWidth $MaxWidth
    }

    $metadataText = [string]$metadataProperty.Value
    $pathText = [string]$pathProperty.Value
    $separator = '    '
    $metadataWidth = GetQuickSearchMeasuredTextWidth -Graphics $Graphics -Font $Font -Text ($metadataText + $separator)
    $pathWidth = [int]($MaxWidth - $metadataWidth)
    if ($pathWidth -le 20) {
        return GetQuickSearchEllipsizedText -Graphics $Graphics -Font $Font -Text $displayText -MaxWidth $MaxWidth
    }

    $ellipsizedPath = GetQuickSearchEllipsizedText -Graphics $Graphics -Font $Font -Text $pathText -MaxWidth $pathWidth
    return ($metadataText + $separator + $ellipsizedPath)
}


Function SetQuickSearchPreviewPanelState {
    param(
        [System.Windows.Forms.Form]$Form,
        [System.Windows.Forms.ListBox]$ResultsListBox,
        [object]$PreviewHost,
        [System.Windows.Forms.Button]$PreviewButton,
        [bool]$Expanded,
        [System.Windows.Forms.Label]$FilterLabel = $null,
        [System.Windows.Forms.TextBox]$FilterTextBox = $null,
        [System.Windows.Forms.Button]$FilterButton = $null,
        [System.Windows.Forms.Panel]$SortPanel = $null,
        [System.Windows.Forms.Label]$SortLabel = $null,
        [System.Windows.Forms.RadioButton[]]$SortButtons = @()
    )

    $PreviewHost.Expanded = $Expanded
    $contentTop = 40
    $contentHeight = [Math]::Max(120, $Form.ClientSize.Height - 95)
    $resultsWidth = [Math]::Max(320, $Form.ClientSize.Width - 20)
    $previewLeft = $resultsWidth + 20
    $previewWidth = [Math]::Max(320, $Form.ClientSize.Width - $previewLeft - 15)

    if ($Expanded) {
        $resultsWidth = [Math]::Max(320, [int](($Form.ClientSize.Width - 35) / 2))
        $previewLeft = $resultsWidth + 20
        $previewWidth = [Math]::Max(320, $Form.ClientSize.Width - $previewLeft - 15)
        SetQuickSearchPreviewHostBounds -PreviewHost $PreviewHost -Location (New-Object System.Drawing.Point($previewLeft, $contentTop)) -Width $previewWidth -Height $contentHeight
        $PreviewButton.Text = 'Hide Preview'
    }
    else {
        $PreviewButton.Text = 'Show Preview'
    }

    $listTop = $contentTop
    $listHeight = $contentHeight
    if ($null -ne $FilterLabel -and $null -ne $FilterTextBox -and $null -ne $FilterButton) {
        $filterHeight = 22
        $filterGap = 6
        $filterLabelWidth = 38
        $filterButtonWidth = 55
        $filterTextLeft = 10 + $filterLabelWidth + $filterGap
        $filterTextWidth = [Math]::Max(120, $resultsWidth - $filterLabelWidth - $filterButtonWidth - (2 * $filterGap))
        $FilterLabel.Location = New-Object System.Drawing.Point(10, ($contentTop + 3))
        $FilterLabel.Width = $filterLabelWidth
        $FilterLabel.Visible = $true
        $FilterTextBox.Location = New-Object System.Drawing.Point($filterTextLeft, $contentTop)
        $FilterTextBox.Width = $filterTextWidth
        $FilterTextBox.Height = 20
        $FilterTextBox.Visible = $true
        $FilterButton.Location = New-Object System.Drawing.Point(($filterTextLeft + $filterTextWidth + $filterGap), $contentTop)
        $FilterButton.Width = $filterButtonWidth
        $FilterButton.Height = 22
        $FilterButton.Visible = $true
        $listTop = $contentTop + $filterHeight + $filterGap
        $listHeight = [Math]::Max(80, $contentHeight - $filterHeight - $filterGap)
    }

    $sortButtonsToShow = @($SortButtons | Where-Object { $null -ne $_ })
    if ($null -ne $SortLabel -and $sortButtonsToShow.Count -gt 0) {
        $sortTop = $listTop
        $sortHeight = 22
        $sortGap = 6
        $sortLabelWidth = 38
        $sortLeftOffset = 0
        $sortLabelTop = 3
        $sortButtonTop = 0
        if ($null -ne $SortPanel) {
            $SortPanel.Location = New-Object System.Drawing.Point(10, $sortTop)
            $SortPanel.Width = $resultsWidth
            $SortPanel.Height = $sortHeight
            $SortPanel.Visible = $true
        }
        else {
            $sortLeftOffset = 10
            $sortLabelTop = $sortTop + 3
            $sortButtonTop = $sortTop
        }

        $SortLabel.Text = 'Sort'
        $SortLabel.Location = New-Object System.Drawing.Point($sortLeftOffset, $sortLabelTop)
        $SortLabel.Width = $sortLabelWidth
        $SortLabel.Visible = $true

        $currentLeft = $sortLeftOffset + $sortLabelWidth + $sortGap
        $availableRight = $sortLeftOffset + $resultsWidth
        foreach ($sortButton in $sortButtonsToShow) {
            $buttonWidth = 74
            if ($sortButton.Text -match 'Modified') { $buttonWidth = 86 }
            if ($currentLeft + $buttonWidth -gt $availableRight) {
                $buttonWidth = [Math]::Max(62, $availableRight - $currentLeft)
            }

            $sortButton.Location = New-Object System.Drawing.Point($currentLeft, $sortButtonTop)
            $sortButton.Width = $buttonWidth
            $sortButton.Height = 20
            $sortButton.Visible = $true
            $currentLeft += $buttonWidth + $sortGap
        }

        $listTop = $sortTop + $sortHeight + $sortGap
        $listHeight = [Math]::Max(80, $contentHeight - ($listTop - $contentTop))
    }

    $ResultsListBox.Location = New-Object System.Drawing.Point(10, $listTop)
    $ResultsListBox.Width = $resultsWidth
    $ResultsListBox.Height = $listHeight

    UpdateQuickSearchPreviewHostVisibility -PreviewHost $PreviewHost
}


Function HighlightQuickSearchRichTextBoxKeyword {
    param(
        [System.Windows.Forms.RichTextBox]$RichTextBox,
        [string]$Keyword
    )

    if ([string]::IsNullOrWhiteSpace($Keyword) -or [string]::IsNullOrEmpty($RichTextBox.Text)) {
        return
    }

    $highlightColor = [System.Drawing.Color]::FromArgb(255, 242, 125)
    $originalSelectionStart = $RichTextBox.SelectionStart
    $originalSelectionLength = $RichTextBox.SelectionLength
    $text = $RichTextBox.Text
    $startIndex = 0

    $RichTextBox.SuspendLayout()
    try {
        while ($startIndex -lt $text.Length) {
            $matchIndex = $text.IndexOf($Keyword, $startIndex, [System.StringComparison]::OrdinalIgnoreCase)
            if ($matchIndex -lt 0) {
                break
            }

            $RichTextBox.Select($matchIndex, $Keyword.Length)
            $RichTextBox.SelectionBackColor = $highlightColor
            $selectedFont = $RichTextBox.SelectionFont
            if ($null -eq $selectedFont) {
                $selectedFont = $RichTextBox.Font
            }
            $boldStyle = [System.Drawing.FontStyle](([int]$selectedFont.Style) -bor ([int][System.Drawing.FontStyle]::Bold))
            $RichTextBox.SelectionFont = [System.Drawing.Font]::new($selectedFont, $boldStyle)
            $startIndex = $matchIndex + [Math]::Max(1, $Keyword.Length)
        }
    }
    finally {
        $RichTextBox.Select($originalSelectionStart, $originalSelectionLength)
        $RichTextBox.ResumeLayout()
    }
}


Function GetQuickSearchPreviewMode {
    param(
        [string]$FilePath,
        [string]$Content
    )

    if (TestHtmlFile $FilePath) {
        return 'Html'
    }

    if ((TestMarkdownFile $FilePath) -and (TestMarkdownHtmlContent $Content)) {
        return 'HtmlMarkdown'
    }

    return 'Text'
}


Function SetQuickSearchPreviewContent {
    param(
        [object]$PreviewHost,
        [string]$FilePath,
        [string]$Content,
        [string]$Keyword,
        [switch]$HighlightKeyword
    )

    $mode = GetQuickSearchPreviewMode -FilePath $FilePath -Content $Content
    $highlightText = if ($HighlightKeyword) { $Keyword } else { '' }

    if ('Html' -eq $mode) {
        $PreviewHost.ActiveView = 'Html'
        $previewDocument = ConvertHtmlToPreviewDocument -Html $Content -Keyword $highlightText
        SetQuickSearchWebBrowserDocument -Browser $PreviewHost.Browser -Html $previewDocument -ScrollToHighlight:($HighlightKeyword -and -not [string]::IsNullOrWhiteSpace($highlightText))
        UpdateQuickSearchPreviewHostVisibility -PreviewHost $PreviewHost
        return
    }

    if ('HtmlMarkdown' -eq $mode) {
        $PreviewHost.ActiveView = 'Html'
        $html = ConvertMarkdownToHtml $Content
        $previewDocument = ConvertHtmlToPreviewDocument -Html $html -Keyword $highlightText
        SetQuickSearchWebBrowserDocument -Browser $PreviewHost.Browser -Html $previewDocument -ScrollToHighlight:($HighlightKeyword -and -not [string]::IsNullOrWhiteSpace($highlightText))
        UpdateQuickSearchPreviewHostVisibility -PreviewHost $PreviewHost
        return
    }

    $PreviewHost.ActiveView = 'Text'
    if (TestMarkdownFile $FilePath) {
        try {
            $PreviewHost.TextBox.Rtf = ConvertMarkdownToRtf $Content
        }
        catch {
            Write-Host "Markdown preview failed for $FilePath. Falling back to plain text." -ForegroundColor Yellow
            $PreviewHost.TextBox.Text = $Content
        }
    }
    else {
        $PreviewHost.TextBox.Text = $Content
    }

    if ($HighlightKeyword) {
        HighlightQuickSearchRichTextBoxKeyword -RichTextBox $PreviewHost.TextBox -Keyword $Keyword
    }

    UpdateQuickSearchPreviewHostVisibility -PreviewHost $PreviewHost
}