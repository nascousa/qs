<#
.SYNOPSIS
Validates QuickSearch index generation and tag lookup without launching the UI.
#>

$ErrorActionPreference = 'Stop'

Set-StrictMode -Version Latest

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path -Path $repoRoot -ChildPath 'src\QuickSearch.ps1'
$supportScriptPath = Join-Path -Path $repoRoot -ChildPath 'src\QuickSearch.Support.ps1'
$asyncScriptPath = Join-Path -Path $repoRoot -ChildPath 'src\QuickSearch.Async.ps1'
$launcherPath = Join-Path -Path $repoRoot -ChildPath 'src\QuickSearch.bat'
$hiddenLauncherPath = Join-Path -Path $repoRoot -ChildPath 'src\QuickSearch.vbs'
$repoConfigPath = Join-Path -Path $repoRoot -ChildPath 'src\settings\config.json'
$repoProfilesPath = Join-Path -Path $repoRoot -ChildPath 'src\profiles'
$repoDefaultProfilePath = Join-Path -Path $repoProfilesPath -ChildPath 'default.profile.json'
$repoNateProfilePath = Join-Path -Path $repoProfilesPath -ChildPath 'nate.profile.json'
$repoDataPath = Join-Path -Path $repoRoot -ChildPath 'src\data'
$repoSampleIndexPath = Join-Path -Path $repoDataPath -ChildPath 'index.sample.json'
$testRoot = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "qs-index-smoke-$([System.Guid]::NewGuid().ToString('N'))"
$fixtureRoot = Join-Path -Path $testRoot -ChildPath 'team'
$indexPath = Join-Path -Path (Join-Path -Path $testRoot -ChildPath 'data') -ChildPath 'index.json'
$legacyIndexPath = Join-Path -Path $testRoot -ChildPath 'legacy-index.json'
$previousSkipAutorun = $env:QS_SKIP_AUTORUN

try {
    $env:QS_SKIP_AUTORUN = '1'
    . $scriptPath

    Assert-True -Condition (Test-Path -LiteralPath $repoConfigPath) -Message 'QS config.json should live under src\settings.'
    Assert-True -Condition (Test-Path -LiteralPath $repoProfilesPath -PathType Container) -Message 'QS profiles should live under src\profiles.'
    Assert-True -Condition (Test-Path -LiteralPath $repoDefaultProfilePath) -Message 'QS default profile should be src\profiles\default.profile.json.'
    Assert-True -Condition (Test-Path -LiteralPath $repoNateProfilePath) -Message 'QS alternate profile fixture should be src\profiles\nate.profile.json.'
    Assert-True -Condition (Test-Path -LiteralPath $repoDataPath -PathType Container) -Message 'QS index data directory should live under src\data.'
    $repoConfig = Get-Content -LiteralPath $repoConfigPath -Raw | ConvertFrom-Json
    Get-Content -LiteralPath $repoDefaultProfilePath -Raw | ConvertFrom-Json | Out-Null
    Get-Content -LiteralPath $repoNateProfilePath -Raw | ConvertFrom-Json | Out-Null
    Assert-True -Condition ('1.4.34' -eq $repoConfig.Version) -Message 'QS version should live in src\settings\config.json Version.'
    $selectedProfileName = GetQuickSearchSelectedProfileName -Config $repoConfig
    $selectedProfilePath = ResolveQuickSearchProfilePath -ProfilesDirectory $repoProfilesPath -ProfileName $selectedProfileName
    Assert-True -Condition (Test-Path -LiteralPath $selectedProfilePath) -Message 'QS selected profile should resolve to an existing profile file.'
    Assert-True -Condition ($repoConfig.AllowedFileExtNames -contains '.txt') -Message 'QS config should include an index file extension whitelist.'
    Assert-True -Condition ($repoConfig.AllowedFileExtNames -contains '.html') -Message 'QS config should include HTML files in the index whitelist.'
    Assert-True -Condition (Test-Path -LiteralPath $repoSampleIndexPath) -Message 'QS should ship an index sample file under src\data.'
    $sampleIndex = Get-Content -LiteralPath $repoSampleIndexPath -Raw | ConvertFrom-Json
    Assert-True -Condition (2 -eq $sampleIndex.schemaVersion) -Message 'Index sample should use schemaVersion 2.'
    $sampleIndexMatches = @(SearchFileIndex -IndexFilePath $repoSampleIndexPath -Keyword 'runbook')
    Assert-True -Condition ($sampleIndexMatches -contains 'D:\Example\Orcas_Main\team\runbook.md') -Message 'Index sample should be searchable.'

    $profileFiles = @(GetQuickSearchProfileFiles -ProfilesDirectory $repoProfilesPath)
    $profileFileNames = @($profileFiles | ForEach-Object { $_.Name })
    Assert-True -Condition ($profileFileNames -contains 'default.profile.json') -Message 'Profile discovery should include default.profile.json.'
    Assert-True -Condition ($profileFileNames -contains 'nate.profile.json') -Message 'Profile discovery should include nate.profile.json.'
    Assert-True -Condition ('default.profile.json' -eq (GetQuickSearchDefaultProfileName)) -Message 'Default profile name should be default.profile.json.'
    Assert-True -Condition ('default.profile.json' -eq (GetQuickSearchSelectedProfileName -Config ([PSCustomObject]@{}))) -Message 'Missing profile setting should select the default profile.'
    Assert-True -Condition ($repoDefaultProfilePath -eq (ResolveQuickSearchProfilePath -ProfilesDirectory $repoProfilesPath -ProfileName 'missing.profile.json')) -Message 'Missing selected profile should resolve to default.profile.json.'
    $nateConfig = [PSCustomObject]@{ DriveLetter = 'Z'; Path = ':\Old\Docs\'; TeamPath = ':\Old\Team\'; Types = @('ALL') }
    $nateProfileState = UseQuickSearchProfile -Config $nateConfig -ProfilesDirectory $repoProfilesPath -ProfileName 'nate.profile.json'
    Assert-True -Condition ($nateProfileState.Applied) -Message 'UseQuickSearchProfile should apply an existing profile.'
    Assert-True -Condition ('nate.profile.json' -eq $nateProfileState.Name) -Message 'Applied profile state should report the selected profile name.'
    Assert-True -Condition ('D' -eq $nateConfig.DriveLetter) -Message 'Profile should override DriveLetter.'
    Assert-True -Condition (':\Orcas_Main\TSG-SOP\' -eq $nateConfig.Path) -Message 'Profile DocPath should override config Path.'
    Assert-True -Condition (':\Orcas_Main\Team\nasco\' -eq $nateConfig.TeamPath) -Message 'Profile should override TeamPath.'
    Assert-True -Condition ($nateConfig.Types -contains 'TEAM') -Message 'Profile should override search Types.'
    Assert-True -Condition ('nate.profile.json' -eq $nateConfig.ProfileName) -Message 'Profile apply should persist the selected profile name in config.'

    $quickSearchScriptPaths = @(Get-ChildItem -LiteralPath (Join-Path -Path $repoRoot -ChildPath 'src') -Recurse -File -Filter 'QuickSearch*.ps1' | ForEach-Object { $_.FullName })
    Assert-True -Condition ($quickSearchScriptPaths.Count -ge 4) -Message 'Expected QuickSearch runtime source scripts and archived tools.'
    foreach ($quickSearchScriptPath in $quickSearchScriptPaths) {
        $quickSearchScriptContent = Get-Content -LiteralPath $quickSearchScriptPath -Raw
        [scriptblock]::Create($quickSearchScriptContent) | Out-Null
    }

    $mainScriptContent = Get-Content -LiteralPath $scriptPath -Raw
    Assert-True -Condition ($mainScriptContent -match 'if\s*\(\s*\$env:QS_PAUSE_ON_EXIT\s+-eq\s+''1''\s*\)\s*\{\s*Pause\s*\}') -Message 'QuickSearch.ps1 should only pause on exit when QS_PAUSE_ON_EXIT=1.'
    Assert-True -Condition ($mainScriptContent -match 'Live Content Scan \(Slow\)') -Message 'Content-search radio label should clarify that content search is a live scan.'
    Assert-True -Condition ($mainScriptContent -match 'Scanning file content live') -Message 'Content-search progress message should clarify that content search scans live files.'
    Assert-True -Condition ($mainScriptContent -match 'InitializeQuickSearchKeywordPlaceholder') -Message 'Keyword textbox should initialize placeholder behavior.'
    Assert-True -Condition ($mainScriptContent -match 'GetQuickSearchKeywordText') -Message 'Search should read the user keyword without treating placeholder text as input.'
    Assert-True -Condition ($mainScriptContent -match '\$highlightPreviewKeyword\s*=\s*-not \[string\]::IsNullOrWhiteSpace\(\$SearchState\.Keyword\)') -Message 'Preview keyword highlighting should use the active search keyword, not only live content scan state.'
    $supportScriptContent = Get-Content -LiteralPath $supportScriptPath -Raw
    Assert-True -Condition ($supportScriptContent -match 'Add_Enter') -Message 'Keyword placeholder should clear when the textbox receives focus.'
    Assert-True -Condition ($supportScriptContent -match 'Add_Leave') -Message 'Keyword placeholder should restore when the textbox loses focus empty.'
    $asyncScriptContent = Get-Content -LiteralPath $asyncScriptPath -Raw
    Assert-True -Condition ($asyncScriptContent -match '\$messageLabel\.Text\s*=\s*\$Message') -Message 'Background search dialog body should show only the search message.'
    Assert-True -Condition ($asyncScriptContent -notmatch 'Elapsed:') -Message 'Elapsed time should not be duplicated in the search dialog body.'
    Assert-True -Condition ($mainScriptContent -match '-Config \$config') -Message 'UI background searches should pass runtime config for live content scan filtering.'

    $indexScriptPath = Join-Path -Path $repoRoot -ChildPath 'src\QuickSearch.Index.ps1'
    $indexScriptContent = Get-Content -LiteralPath $indexScriptPath -Raw
    Assert-True -Condition ($indexScriptContent -notmatch '\$content\s*=\s*Get-Content\s+-LiteralPath\s+\$FilePath\s+-Raw') -Message 'Top-word indexing should not read an entire target file into memory.'
    Assert-True -Condition ($indexScriptContent -notmatch '\$words\s*=\s*\$content\s+-split') -Message 'Top-word indexing should not materialize all split words at once.'

    $launcherContent = Get-Content -LiteralPath $launcherPath -Raw
    Assert-True -Condition ($launcherContent -match 'QuickSearch\.vbs') -Message 'QuickSearch.bat should delegate UI launch to the no-console VBS launcher.'
    Assert-True -Condition ($launcherContent -match 'wscript\.exe') -Message 'QuickSearch.bat should launch the VBS entry point through Windows Script Host.'
    Assert-True -Condition ($launcherContent -notmatch 'QuickSearch_UI\.ps1') -Message 'QuickSearch.bat should not reference the removed QuickSearch_UI.ps1 script.'
    Assert-True -Condition (Test-Path -LiteralPath $hiddenLauncherPath) -Message 'QuickSearch.vbs should exist as the no-console launcher.'
    $hiddenLauncherContent = Get-Content -LiteralPath $hiddenLauncherPath -Raw
    Assert-True -Condition ($hiddenLauncherContent -match 'QuickSearch\.ps1') -Message 'QuickSearch.vbs should launch the current QuickSearch.ps1 entry point.'
    Assert-True -Condition ($hiddenLauncherContent -match 'PowerShell\.exe') -Message 'QuickSearch.vbs should launch PowerShell.'
    Assert-True -Condition ($hiddenLauncherContent -match '-WindowStyle\s+Hidden') -Message 'QuickSearch.vbs should hide the PowerShell console window.'
    Assert-True -Condition ($hiddenLauncherContent -match 'shell\.Run\s+command,\s*0,\s*False') -Message 'QuickSearch.vbs should run PowerShell hidden without waiting.'
    Assert-True -Condition ($hiddenLauncherContent -notmatch 'QuickSearch_UI\.ps1') -Message 'QuickSearch.vbs should not reference the removed QuickSearch_UI.ps1 script.'

    New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path -Path $fixtureRoot -ChildPath 'skip-folder') -Force | Out-Null

    $parsedValues = ConvertDelimitedTextToArray "one, two; three`nfour"
    Assert-True -Condition (4 -eq $parsedValues.Count) -Message 'ConvertDelimitedTextToArray should parse comma, semicolon, and newline separated values.'
    Assert-True -Condition ('one, two, three, four' -eq (ConvertArrayToDelimitedText $parsedValues)) -Message 'ConvertArrayToDelimitedText should format settings values.'

    $settingsConfig = [PSCustomObject]@{}
    SetConfigValue -Config $settingsConfig -Name 'TeamPath' -Value ':\Orcas_Main\team\'
    SetConfigValue -Config $settingsConfig -Name 'Version' -Value '9.8.7'
    SetConfigValue -Config $settingsConfig -Name 'TagCount' -Value 4
    SetConfigValue -Config $settingsConfig -Name 'MaxTagFileSizeMB' -Value 2
    SetConfigValue -Config $settingsConfig -Name 'AllowedFileExtNames' -Value @('.txt', '.md')
    SetConfigValue -Config $settingsConfig -Name 'IgnoredFileExtNames' -Value @('.tmp')
    $settingsConfigPath = Join-Path -Path (Join-Path -Path $testRoot -ChildPath 'settings') -ChildPath 'config.json'
    SaveConfig -Config $settingsConfig -ConfigPath $settingsConfigPath
    $savedSettings = Get-Content -LiteralPath $settingsConfigPath -Raw | ConvertFrom-Json
    Assert-True -Condition ('D:\Orcas_Main\team\' -eq (ResolveConfiguredPath -DriveLetter 'D' -PathTemplate (GetTeamPathTemplate $savedSettings))) -Message 'Saved TEAM path template should resolve with the selected drive.'
    Assert-True -Condition ('9.8.7' -eq $savedSettings.Version) -Message 'SaveConfig should persist Version.'
    Assert-True -Condition (4 -eq $savedSettings.TagCount) -Message 'SaveConfig should persist TagCount.'
    Assert-True -Condition (2 -eq $savedSettings.MaxTagFileSizeMB) -Message 'SaveConfig should persist MaxTagFileSizeMB.'
    Assert-True -Condition ($savedSettings.AllowedFileExtNames -contains '.md') -Message 'SaveConfig should persist AllowedFileExtNames.'
    Assert-True -Condition ($savedSettings.IgnoredFileExtNames -contains '.tmp') -Message 'SaveConfig should persist array settings.'

    $testRepoRoot = Join-Path -Path $testRoot -ChildPath 'repo'
    $testAdcRoot = Join-Path -Path $testRepoRoot -ChildPath '.adc'
    $testConfigRoot = Join-Path -Path $testRepoRoot -ChildPath 'src\settings'
    New-Item -ItemType Directory -Path $testAdcRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $testConfigRoot -Force | Out-Null
    $testConfigPath = Join-Path -Path $testConfigRoot -ChildPath 'config.json'
    Set-Content -LiteralPath $testConfigPath -Value '{"Version":"2.4.15"}' -NoNewline
    Set-Content -LiteralPath (Join-Path -Path $testAdcRoot -ChildPath 'index.md') -Value "---`nversion: `"9.9.9`"`n---" -NoNewline
    Assert-True -Condition ('2.4.15' -eq (GetQuickSearchProjectVersion -RepoRoot $testRepoRoot)) -Message 'Project version should be read from settings config Version.'
    Assert-True -Condition ('2.4.16' -eq (GetQuickSearchProjectVersion -Config ([PSCustomObject]@{ Version = '2.4.16' }) -RepoRoot $testRepoRoot)) -Message 'Provided config Version should override file and ADC metadata.'
    Assert-True -Condition ('v2.4.15' -eq (ConvertVersionToTitleSuffix -Version '2.4.15')) -Message 'Title version suffix should use unpadded vX.Y.Z formatting.'
    Assert-True -Condition ('v2.4.15' -eq (ConvertVersionToTitleSuffix -Version '2.04.015')) -Message 'Title version suffix should omit leading zero padding.'
    Assert-True -Condition ('1.4.16' -eq (GetNextQuickSearchVersion -Version '1.4.15')) -Message 'Version increments should advance the patch segment first.'
    Assert-True -Condition ('1.5.0' -eq (GetNextQuickSearchVersion -Version '1.4.999')) -Message 'Version increments should carry to the minor segment after patch 999.'
    Assert-True -Condition ('QuickSearch v2.4.15' -eq (GetQuickSearchWindowTitle -BaseTitle 'QuickSearch' -Version '2.4.15')) -Message 'Window title should append the unpadded project version.'
    Assert-True -Condition ('QuickSearch v2.4.15' -eq (GetQuickSearchWindowTitle -BaseTitle 'QuickSearch v1.03.000' -Version '2.04.015')) -Message 'Window title should replace an existing version suffix and omit leading zero padding.'
    Assert-True -Condition (-not (TestExistingLiteralPath '')) -Message 'Empty result selections should not be treated as valid paths.'

    Assert-True -Condition (TestMarkdownFile 'notes.md') -Message 'TestMarkdownFile should detect .md files.'
    Assert-True -Condition (TestMarkdownFile 'notes.markdown') -Message 'TestMarkdownFile should detect .markdown files.'
    Assert-True -Condition (-not (TestMarkdownFile 'notes.txt')) -Message 'TestMarkdownFile should not treat .txt as Markdown.'
    Assert-True -Condition (TestHtmlFile 'page.html') -Message 'TestHtmlFile should detect .html files.'
    Assert-True -Condition (TestHtmlFile 'page.htm') -Message 'TestHtmlFile should detect .htm files.'
    Assert-True -Condition (-not (TestHtmlFile 'page.md')) -Message 'TestHtmlFile should not treat Markdown as HTML.'
    Assert-True -Condition (TestMarkdownHtmlContent '<span>inline html</span>') -Message 'Markdown preview should detect inline HTML tags.'
    Assert-True -Condition (-not (TestMarkdownHtmlContent 'plain markdown text')) -Message 'Plain Markdown should not be forced into HTML preview mode.'

    $markdownRtf = ConvertMarkdownToRtf "# Heading`n`n- **bold** item`n> quote`n`n``code``"
    Assert-True -Condition ($markdownRtf.StartsWith('{\rtf1')) -Message 'Markdown renderer should return RTF.'
    Assert-True -Condition ($markdownRtf.Contains('\fs36 Heading')) -Message 'Markdown headings should render with heading font size.'
    Assert-True -Condition ($markdownRtf.Contains('\bullet\tab')) -Message 'Markdown unordered lists should render as bullets.'
    Assert-True -Condition ($markdownRtf.Contains('{\b bold}')) -Message 'Markdown bold text should render as RTF bold.'
    Assert-True -Condition ($markdownRtf.Contains('\i quote\i0')) -Message 'Markdown block quotes should render as italic text.'
    Assert-True -Condition ($markdownRtf.Contains('{\f1\cf2 code}')) -Message 'Markdown inline code should render with the code font.'
    $markdownHtml = ConvertMarkdownToHtml "# Heading`n<div>alpha <strong>HTML</strong></div>"
    Assert-True -Condition ($markdownHtml.Contains('<h1>Heading</h1>')) -Message 'Markdown HTML renderer should render headings.'
    Assert-True -Condition ($markdownHtml.Contains('<div>alpha <strong>HTML</strong></div>')) -Message 'Markdown HTML renderer should preserve safe HTML blocks.'
    $highlightedHtml = ConvertHtmlToPreviewDocument -Html '<html><head></head><body><p>alpha beta</p><a href="javascript:alert(1)" onclick="bad()">alpha</a><script>bad()</script></body></html>' -Keyword 'alpha'
    Assert-True -Condition ($highlightedHtml.Contains('<mark class="qs-highlight">alpha</mark> beta')) -Message 'HTML preview should highlight active search keywords.'
    Assert-True -Condition ($highlightedHtml.Contains('.qs-highlight{background:#fff27d;color:#111;font-weight:700;}')) -Message 'HTML preview highlights should be bold.'
    Assert-True -Condition ($highlightedHtml -notmatch '<script') -Message 'HTML preview should strip script tags.'
    Assert-True -Condition ($highlightedHtml -notmatch 'onclick') -Message 'HTML preview should strip inline event handlers.'
    Assert-True -Condition ($highlightedHtml -notmatch 'javascript:') -Message 'HTML preview should neutralize javascript URLs.'

    Add-Type -AssemblyName System.Windows.Forms
    $placeholderTextBox = New-Object System.Windows.Forms.TextBox
    InitializeQuickSearchKeywordPlaceholder -TextBox $placeholderTextBox -Placeholder 'keyword'
    Assert-True -Condition ('keyword' -eq $placeholderTextBox.Text) -Message 'Keyword placeholder should be visible initially.'
    Assert-True -Condition ('' -eq (GetQuickSearchKeywordText -TextBox $placeholderTextBox)) -Message 'Keyword placeholder should not be treated as a search keyword.'
    ClearQuickSearchKeywordPlaceholder -TextBox $placeholderTextBox
    Assert-True -Condition ([string]::IsNullOrEmpty($placeholderTextBox.Text)) -Message 'Keyword placeholder should clear on focus.'
    SetQuickSearchKeywordPlaceholder -TextBox $placeholderTextBox
    Assert-True -Condition ('keyword' -eq $placeholderTextBox.Text) -Message 'Keyword placeholder should return when the textbox is left empty.'
    ClearQuickSearchKeywordPlaceholder -TextBox $placeholderTextBox
    $placeholderTextBox.Text = 'alpha'
    SetQuickSearchKeywordPlaceholder -TextBox $placeholderTextBox
    Assert-True -Condition ('alpha' -eq (GetQuickSearchKeywordText -TextBox $placeholderTextBox)) -Message 'Entered keyword should be preserved when focus leaves.'
    $previewForm = New-Object System.Windows.Forms.Form
    $previewForm.ClientSize = New-Object System.Drawing.Size(1000, 500)
    $previewListBox = New-Object System.Windows.Forms.ListBox
    $previewRichTextBox = New-Object System.Windows.Forms.RichTextBox
    $previewBrowser = New-Object System.Windows.Forms.WebBrowser
    $previewToggleButton = New-Object System.Windows.Forms.Button
    $previewHost = NewQuickSearchPreviewHost -TextBox $previewRichTextBox -Browser $previewBrowser
    SetQuickSearchPreviewPanelState -Form $previewForm -ResultsListBox $previewListBox -PreviewHost $previewHost -PreviewButton $previewToggleButton -Expanded $false
    $collapsedListWidth = $previewListBox.Width
    Assert-True -Condition (-not $previewRichTextBox.Visible) -Message 'Preview pane should be hidden when collapsed.'
    Assert-True -Condition (-not $previewBrowser.Visible) -Message 'HTML preview pane should be hidden when collapsed.'
    Assert-True -Condition ('Show Preview' -eq $previewToggleButton.Text) -Message 'Preview toggle should offer to show preview when collapsed.'
    Assert-True -Condition ($collapsedListWidth -gt 900) -Message 'Results list should use nearly the full width when preview is collapsed.'

    SetQuickSearchPreviewPanelState -Form $previewForm -ResultsListBox $previewListBox -PreviewHost $previewHost -PreviewButton $previewToggleButton -Expanded $true
    Assert-True -Condition $previewRichTextBox.Visible -Message 'Preview pane should be visible when expanded.'
    Assert-True -Condition ('Hide Preview' -eq $previewToggleButton.Text) -Message 'Preview toggle should offer to hide preview when expanded.'
    Assert-True -Condition ($previewListBox.Width -lt $collapsedListWidth) -Message 'Results list should narrow when preview is expanded.'
    Assert-True -Condition ($previewRichTextBox.Width -gt 300) -Message 'Preview pane should have readable width when expanded.'
    SetQuickSearchPreviewContent -PreviewHost $previewHost -FilePath 'match.txt' -Content 'alpha beta ALPHA' -Keyword 'alpha' -HighlightKeyword
    Assert-True -Condition ('Text' -eq $previewHost.ActiveView) -Message 'Plain text preview should use the RichTextBox view.'
    Assert-True -Condition $previewRichTextBox.Text.Contains('alpha beta ALPHA') -Message 'Text preview should load selected file content.'
    $expectedHighlightColor = [System.Drawing.Color]::FromArgb(255, 242, 125)
    $previewRichTextBox.Select(0, 5)
    Assert-True -Condition ($expectedHighlightColor.ToArgb() -eq $previewRichTextBox.SelectionBackColor.ToArgb()) -Message 'Text preview should highlight the active search keyword.'
    $highlightFontStyle = [int]$previewRichTextBox.SelectionFont.Style
    Assert-True -Condition (0 -ne ($highlightFontStyle -band ([int][System.Drawing.FontStyle]::Bold))) -Message 'Text preview highlight should make the active search keyword bold.'
    SetQuickSearchPreviewContent -PreviewHost $previewHost -FilePath 'page.html' -Content '<p>alpha beta</p>' -Keyword 'alpha' -HighlightKeyword
    Assert-True -Condition ('Html' -eq $previewHost.ActiveView) -Message 'HTML preview should use the browser view.'
    Assert-True -Condition $previewBrowser.Visible -Message 'HTML preview should show the browser when expanded.'

    $largeTextPath = Join-Path -Path $testRoot -ChildPath 'large-streaming.txt'
    $largeWriter = [System.IO.StreamWriter]::new($largeTextPath, $false, [System.Text.Encoding]::UTF8)
    try {
        for ($lineNumber = 0; $lineNumber -lt 500; $lineNumber++) {
            $largeWriter.WriteLine('streaming streaming streaming memorysafe alpha')
        }
    }
    finally {
        $largeWriter.Dispose()
    }
    $largeTagCounts = GetTopWords -FilePath $largeTextPath -Count 2
    Assert-True -Condition (1500 -eq $largeTagCounts.streaming) -Message 'Streaming top-word extraction should count repeated words across buffered reads.'

    $longTokenPath = Join-Path -Path $testRoot -ChildPath 'long-token.txt'
    $longTokenText = 'x' * 200000
    Set-Content -LiteralPath $longTokenPath -Value "alpha alpha $longTokenText beta beta beta" -NoNewline
    $longTokenTopWords = GetTopWords -FilePath $longTokenPath -Count 5
    Assert-True -Condition (2 -eq $longTokenTopWords.alpha) -Message 'Streaming top-word extraction should count words before a long delimiterless token.'
    Assert-True -Condition (3 -eq $longTokenTopWords.beta) -Message 'Streaming top-word extraction should count words after a long delimiterless token.'
    Assert-True -Condition (0 -eq @($longTokenTopWords.Keys | Where-Object { $_.Length -gt 64 }).Count) -Message 'Streaming top-word extraction should not keep oversized delimiterless tokens.'

    $samplePath = Join-Path -Path $fixtureRoot -ChildPath 'sample.txt'
    Set-Content -LiteralPath $samplePath -Value 'alpha alpha beta gamma delta 123 z9' -NoNewline
    Set-Content -LiteralPath (Join-Path -Path $fixtureRoot -ChildPath 'large.txt') -Value ('oversized ' * 140000) -NoNewline
    Set-Content -LiteralPath (Join-Path -Path $fixtureRoot -ChildPath 'ignored.txt') -Value 'ignored ignored ignored' -NoNewline
    Set-Content -LiteralPath (Join-Path -Path $fixtureRoot -ChildPath 'image.png') -Value 'png png png' -NoNewline
    Set-Content -LiteralPath (Join-Path -Path $fixtureRoot -ChildPath 'skip-folder\hidden.txt') -Value 'hidden hidden hidden' -NoNewline

    $config = [PSCustomObject]@{
        TagCount = 3
        MaxTagFileSizeMB = 0
        IgnoredFilenames = @('ignored.txt')
        IgnoredFileExtNames = @('.png')
        Ignored = @('skip-folder')
    }

    $statusPath = Join-Path -Path $testRoot -ChildPath 'index-status.json'
    $created = CreateFileIndex -Root $fixtureRoot -Config $config -IndexFilePath $indexPath -StatusFilePath $statusPath
    Assert-True -Condition $created -Message 'CreateFileIndex should return true.'
    Assert-True -Condition (Test-Path -LiteralPath $indexPath) -Message 'Index file should be created.'
    Assert-True -Condition (Test-Path -LiteralPath $statusPath) -Message 'Index status file should be created.'
    $statusData = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
    Assert-True -Condition ('Completed' -eq $statusData.stage) -Message 'Index status should finish as Completed.'
    Assert-True -Condition (5 -eq $statusData.processed) -Message 'Index status should count all scanned files.'
    Assert-True -Condition (2 -eq $statusData.indexed) -Message 'Index status should count indexed files.'
    Assert-True -Condition (3 -eq $statusData.skipped) -Message 'Index status should count skipped files.'
    Assert-True -Condition ($null -ne $statusData.PSObject.Properties['reused']) -Message 'Index status should include reused file count.'

    $limitedIndexPath = Join-Path -Path (Join-Path -Path $testRoot -ChildPath 'limited-data') -ChildPath 'index.json'
    $limitedConfig = [PSCustomObject]@{
        TagCount = 3
        MaxTagFileSizeMB = 1
        IgnoredFilenames = @('ignored.txt')
        IgnoredFileExtNames = @('.png')
        Ignored = @('skip-folder')
    }
    $created = CreateFileIndex -Root $fixtureRoot -Config $limitedConfig -IndexFilePath $limitedIndexPath
    Assert-True -Condition $created -Message 'CreateFileIndex should allow a max tag file size policy.'
    $limitedIndex = Get-Content -LiteralPath $limitedIndexPath -Raw | ConvertFrom-Json
    $largeDocument = @($limitedIndex.documents | Where-Object { $_.name -eq 'large.txt' })[0]
    Assert-True -Condition ($null -ne $largeDocument) -Message 'Large files should still be indexed by name/path.'
    Assert-True -Condition (0 -eq @($largeDocument.tags).Count) -Message 'Large files over the limit should skip generated tag extraction.'
    Assert-True -Condition ($limitedIndex.terms.large -contains $largeDocument.id) -Message 'Large files should remain searchable by filename terms.'

    $whitelistRoot = Join-Path -Path $testRoot -ChildPath 'whitelist-team'
    $whitelistIndexPath = Join-Path -Path (Join-Path -Path $testRoot -ChildPath 'whitelist-data') -ChildPath 'index.json'
    New-Item -ItemType Directory -Path $whitelistRoot -Force | Out-Null
    $allowedTextPath = Join-Path -Path $whitelistRoot -ChildPath 'allowed.txt'
    $allowedMarkdownPath = Join-Path -Path $whitelistRoot -ChildPath 'allowed-md.md'
    $blockedLogPath = Join-Path -Path $whitelistRoot -ChildPath 'blocked.log'
    Set-Content -LiteralPath $allowedTextPath -Value 'allowlist alpha alpha' -NoNewline
    Set-Content -LiteralPath $allowedMarkdownPath -Value 'allowlist markdown beta' -NoNewline
    Set-Content -LiteralPath $blockedLogPath -Value 'blocked blocked blocked' -NoNewline
    $whitelistConfig = [PSCustomObject]@{
        TagCount = 3
        MaxTagFileSizeMB = 0
        AllowedFileExtNames = @('txt', '.md')
        IgnoredFilenames = @()
        IgnoredFileExtNames = @()
        Ignored = @()
    }
    $created = CreateFileIndex -Root $whitelistRoot -Config $whitelistConfig -IndexFilePath $whitelistIndexPath
    Assert-True -Condition $created -Message 'CreateFileIndex should allow extension whitelist indexing.'
    $whitelistIndex = Get-Content -LiteralPath $whitelistIndexPath -Raw | ConvertFrom-Json
    Assert-True -Condition (2 -eq @($whitelistIndex.documents).Count) -Message 'Extension whitelist should index only allowed extensions.'
    Assert-True -Condition (0 -eq @($whitelistIndex.documents | Where-Object { $_.name -eq 'blocked.log' }).Count) -Message 'Extension whitelist should skip blocked extensions.'
    $blockedMatches = @(SearchFileIndex -IndexFilePath $whitelistIndexPath -Keyword 'blocked')
    Assert-True -Condition (0 -eq $blockedMatches.Count) -Message 'Blocked extension files should not be searchable.'
    $liveBlockedMatches = @(SearchFiles -Root $whitelistRoot -Keyword 'blocked' -SearchContent $true -Config $whitelistConfig)
    Assert-True -Condition (0 -eq $liveBlockedMatches.Count) -Message 'Live content scan should skip files excluded by the extension whitelist.'
    $liveAllowedMatches = @(SearchFiles -Root $whitelistRoot -Keyword 'allowlist' -SearchContent $true -Config $whitelistConfig)
    Assert-True -Condition ($liveAllowedMatches -contains $allowedTextPath) -Message 'Live content scan should keep allowed text files.'
    Assert-True -Condition ($liveAllowedMatches -contains $allowedMarkdownPath) -Message 'Live content scan should keep allowed Markdown files.'

    $backgroundIndexPath = Join-Path -Path (Join-Path -Path $testRoot -ChildPath 'background-data') -ChildPath 'index.json'
    $backgroundCreated = InvokeFileIndexWithProcessingDialog -Owner $null -Title 'Background Smoke Test' -Message 'Indexing in progress, please wait...' -Root $fixtureRoot -Config $config -IndexFilePath $backgroundIndexPath
    Assert-True -Condition $backgroundCreated -Message 'Background indexing helper should return true.'
    Assert-True -Condition (Test-Path -LiteralPath $backgroundIndexPath) -Message 'Background indexing helper should create the index file.'

    $backgroundFilenameSearch = InvokeQuickSearchWithProcessingDialog -Owner $null -Title 'Search Smoke Test' -Message 'Searching filenames...' -Root $fixtureRoot -Keyword 'sample' -SearchContent $false -UseIndex $false -IndexFilePath '' -Config $config
    Assert-True -Condition $backgroundFilenameSearch.Completed -Message 'Background filename search should complete.'
    Assert-True -Condition (-not $backgroundFilenameSearch.Canceled) -Message 'Background filename search should not be canceled.'
    Assert-True -Condition ($backgroundFilenameSearch.Results -contains $samplePath) -Message 'Background filename search should find sample.txt.'
    $backgroundContentSearch = InvokeQuickSearchWithProcessingDialog -Owner $null -Title 'Content Search Smoke Test' -Message 'Searching content...' -Root $fixtureRoot -Keyword 'gamma' -SearchContent $true -UseIndex $false -IndexFilePath '' -Config $config
    Assert-True -Condition $backgroundContentSearch.Completed -Message 'Background content search should complete.'
    Assert-True -Condition ($backgroundContentSearch.Results -contains $samplePath) -Message 'Background content search should find matching file content.'
    $backgroundIndexSearch = InvokeQuickSearchWithProcessingDialog -Owner $null -Title 'Index Search Smoke Test' -Message 'Searching index...' -Root $fixtureRoot -Keyword 'alpha' -SearchContent $false -UseIndex $true -IndexFilePath $indexPath -Config $config
    Assert-True -Condition $backgroundIndexSearch.Completed -Message 'Background index search should complete.'
    Assert-True -Condition ($backgroundIndexSearch.Results -contains $samplePath) -Message 'Background index search should find indexed tags.'

    $indexItems = @(Get-Content -LiteralPath $indexPath -Raw | ConvertFrom-Json)
    Assert-True -Condition (2 -eq $indexItems.schemaVersion) -Message 'Index should use schemaVersion 2.'
    Assert-True -Condition (2 -eq @($indexItems.documents).Count) -Message "Expected two indexed documents, found $(@($indexItems.documents).Count)."
    $sampleDocument = @($indexItems.documents | Where-Object { $_.name -eq 'sample.txt' })[0]
    Assert-True -Condition ($null -ne $sampleDocument) -Message 'Indexed documents should include sample.txt.'
    Assert-True -Condition ($sampleDocument.tags -contains 'alpha') -Message 'Generated tags should include alpha.'
    Assert-True -Condition (2 -eq $sampleDocument.tagCounts.alpha) -Message 'alpha tag count should be 2.'
    Assert-True -Condition ($indexItems.terms.alpha -contains $sampleDocument.id) -Message 'Inverted term index should map alpha to the sample document id.'
    Assert-True -Condition ($indexItems.terms.sample -contains $sampleDocument.id) -Message 'Inverted term index should map filename words to the sample document id.'

    $tagMatches = @(SearchFileIndex -IndexFilePath $indexPath -Keyword 'alpha')
    Assert-True -Condition ($tagMatches -contains $samplePath) -Message 'Tag search should find sample.txt.'

    $nameMatches = @(SearchFileIndex -IndexFilePath $indexPath -Keyword 'sample')
    Assert-True -Condition ($nameMatches -contains $samplePath) -Message 'Filename search should find sample.txt.'

    $partialTagMatches = @(SearchFileIndex -IndexFilePath $indexPath -Keyword 'alp')
    Assert-True -Condition ($partialTagMatches -contains $samplePath) -Message 'Partial tag search should still find sample.txt.'

    $ignoredMatches = @(SearchFileIndex -IndexFilePath $indexPath -Keyword 'ignored')
    Assert-True -Condition (0 -eq $ignoredMatches.Count) -Message 'Ignored file should not be searchable.'

    $legacyIndex = @(
        [PSCustomObject]@{
            name = 'legacy.txt'
            path = $samplePath
            sizeInBytes = 1
            lastModified = '2026-06-16T00:00:00.0000000Z'
            tags = @('legacytag')
            tagCounts = [ordered]@{ legacytag = 1 }
        }
    )
    $legacyIndex | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $legacyIndexPath
    $legacyMatches = @(SearchFileIndex -IndexFilePath $legacyIndexPath -Keyword 'legacytag')
    Assert-True -Condition ($legacyMatches -contains $samplePath) -Message 'Legacy schema tag search should remain supported.'

    $sampleFile = Get-Item -LiteralPath $samplePath
    $cachedIndex = [PSCustomObject]@{
        schemaVersion = 2
        root = $fixtureRoot
        createdUtc = [System.DateTime]::UtcNow.ToString('o')
        documents = @(
            [PSCustomObject]@{
                id = 99
                name = $sampleFile.Name
                path = $sampleFile.FullName
                sizeInBytes = $sampleFile.Length
                lastModified = $sampleFile.LastWriteTime.ToString('o')
                lastWriteUtc = $sampleFile.LastWriteTimeUtc.ToString('o')
                tags = @('cachedword')
                tagCounts = [ordered]@{ cachedword = 7 }
            }
        )
        terms = [ordered]@{ cachedword = @(99) }
    }
    $cachedIndex | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $indexPath
    $created = CreateFileIndex -Root $fixtureRoot -Config $config -IndexFilePath $indexPath
    Assert-True -Condition $created -Message 'CreateFileIndex should rebuild from a reusable schema v2 cache.'
    $rebuiltIndex = Get-Content -LiteralPath $indexPath -Raw | ConvertFrom-Json
    Assert-True -Condition ($true -eq $rebuiltIndex.complete) -Message 'Completed index should be marked complete.'
    Assert-True -Condition (-not (Test-Path -LiteralPath (GetFileIndexTempPath -IndexFilePath $indexPath))) -Message 'Completed index should remove the temporary checkpoint file.'
    $rebuiltSampleDocument = @($rebuiltIndex.documents | Where-Object { $_.name -eq 'sample.txt' })[0]
    Assert-True -Condition ($rebuiltSampleDocument.tags -contains 'cachedword') -Message 'Unchanged files should reuse cached tag metadata.'
    Assert-True -Condition ($rebuiltIndex.terms.cachedword -contains $rebuiltSampleDocument.id) -Message 'Rebuilt inverted terms should use the new document id for reused metadata.'

    $resumeRoot = Join-Path -Path $testRoot -ChildPath 'resume-team'
    $resumeIndexPath = Join-Path -Path (Join-Path -Path $testRoot -ChildPath 'resume-data') -ChildPath 'index.json'
    New-Item -ItemType Directory -Path $resumeRoot -Force | Out-Null
    $resumeUnchangedPath = Join-Path -Path $resumeRoot -ChildPath 'resume-unchanged.txt'
    $resumeChangedPath = Join-Path -Path $resumeRoot -ChildPath 'resume-changed.txt'
    Set-Content -LiteralPath $resumeUnchangedPath -Value 'unchanged live words' -NoNewline
    Set-Content -LiteralPath $resumeChangedPath -Value 'changed fresh fresh' -NoNewline
    $resumeUnchangedFile = Get-Item -LiteralPath $resumeUnchangedPath
    $resumeChangedFile = Get-Item -LiteralPath $resumeChangedPath
    $staleChangedTimestamp = $resumeChangedFile.LastWriteTimeUtc.AddMinutes(-10)
    $partialTerms = [ordered]@{}
    $partialDocuments = New-Object System.Collections.ArrayList
    $partialUnchanged = [PSCustomObject]@{
        id = 1
        name = $resumeUnchangedFile.Name
        path = $resumeUnchangedFile.FullName
        sizeInBytes = $resumeUnchangedFile.Length
        lastModified = $resumeUnchangedFile.LastWriteTime.ToString('o')
        lastWriteUtc = $resumeUnchangedFile.LastWriteTimeUtc.ToString('o')
        tags = @('resumecached')
        tagCounts = [ordered]@{ resumecached = 5 }
    }
    $partialChanged = [PSCustomObject]@{
        id = 2
        name = $resumeChangedFile.Name
        path = $resumeChangedFile.FullName
        sizeInBytes = $resumeChangedFile.Length
        lastModified = $staleChangedTimestamp.ToLocalTime().ToString('o')
        lastWriteUtc = $staleChangedTimestamp.ToString('o')
        tags = @('stale')
        tagCounts = [ordered]@{ stale = 9 }
    }
    [void]$partialDocuments.Add($partialUnchanged)
    [void]$partialDocuments.Add($partialChanged)
    AddFileIndexDocumentTerms -Terms $partialTerms -Document $partialUnchanged
    AddFileIndexDocumentTerms -Terms $partialTerms -Document $partialChanged
    WriteFileIndexCheckpoint -IndexFilePath $resumeIndexPath -Root $resumeRoot -Documents $partialDocuments -Terms $partialTerms -Processed 2 -Total 2 -Skipped 0
    Assert-True -Condition (Test-Path -LiteralPath (GetFileIndexTempPath -IndexFilePath $resumeIndexPath)) -Message 'Checkpoint should write a resumable temporary index file.'
    $created = CreateFileIndex -Root $resumeRoot -Config ([PSCustomObject]@{ TagCount = 3; MaxTagFileSizeMB = 0; IgnoredFilenames = @(); IgnoredFileExtNames = @(); Ignored = @() }) -IndexFilePath $resumeIndexPath
    Assert-True -Condition $created -Message 'CreateFileIndex should resume from a temporary checkpoint.'
    $resumeIndex = Get-Content -LiteralPath $resumeIndexPath -Raw | ConvertFrom-Json
    Assert-True -Condition ($true -eq $resumeIndex.complete) -Message 'Resumed index should be marked complete.'
    Assert-True -Condition (-not (Test-Path -LiteralPath (GetFileIndexTempPath -IndexFilePath $resumeIndexPath))) -Message 'Resumed index should replace and remove the temporary checkpoint file.'
    $resumedUnchangedDocument = @($resumeIndex.documents | Where-Object { $_.name -eq 'resume-unchanged.txt' })[0]
    $resumedChangedDocument = @($resumeIndex.documents | Where-Object { $_.name -eq 'resume-changed.txt' })[0]
    Assert-True -Condition ($resumedUnchangedDocument.tags -contains 'resumecached') -Message 'Resume should reuse unchanged document tag metadata from the temporary checkpoint.'
    Assert-True -Condition (-not ($resumedChangedDocument.tags -contains 'stale')) -Message 'Resume should not reuse stale metadata when file timestamps changed.'
    Assert-True -Condition ($resumedChangedDocument.tags -contains 'fresh') -Message 'Resume should re-index changed files.'

    Write-Host 'QS index smoke test OK' -ForegroundColor Green
}
finally {
    if ($null -eq $previousSkipAutorun) {
        Remove-Item Env:\QS_SKIP_AUTORUN -ErrorAction SilentlyContinue
    }
    else {
        $env:QS_SKIP_AUTORUN = $previousSkipAutorun
    }

    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}