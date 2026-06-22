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

function Get-TestFileIndexDocuments {
    param([string]$Path)

    if ($null -ne (Get-Command -Name TestFileIndexShardsAvailable -CommandType Function -ErrorAction SilentlyContinue) -and (TestFileIndexShardsAvailable -IndexFilePath $Path)) {
        return @(GetFileIndexShardedDocuments -IndexFilePath $Path)
    }

    $index = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($index.schemaVersion -eq 2) {
        return @($index.documents)
    }

    return @($index)
}

function Get-TestFileIndexTermProperties {
    param([string]$Path)

    if ($null -ne (Get-Command -Name TestFileIndexShardsAvailable -CommandType Function -ErrorAction SilentlyContinue) -and (TestFileIndexShardsAvailable -IndexFilePath $Path)) {
        $manifest = ReadFileIndexShardManifest -IndexFilePath $Path
        return @(GetFileIndexShardedTermProperties -IndexFilePath $Path -Manifest $manifest)
    }

    $index = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    return @(GetFileIndexTermProperties -Terms $index.terms)
}

function Test-TestFileIndexTermContainsDocumentId {
    param(
        [string]$Path,
        [string]$Term,
        [int]$DocumentId
    )

    foreach ($property in @(Get-TestFileIndexTermProperties -Path $Path)) {
        if ($property.Name -eq $Term -and @($property.Value) -contains $DocumentId) {
            return $true
        }
    }

    return $false
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
$repoShardScriptPath = Join-Path -Path $repoRoot -ChildPath 'src\QuickSearch.IndexShard.ps1'
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
    $repoDefaultProfile = Get-Content -LiteralPath $repoDefaultProfilePath -Raw | ConvertFrom-Json
    $repoNateProfile = Get-Content -LiteralPath $repoNateProfilePath -Raw | ConvertFrom-Json
    Assert-True -Condition ('1.4.54' -eq $repoConfig.Version) -Message 'QS version should live in src\settings\config.json Version.'
    Assert-True -Condition (-not [string]::IsNullOrWhiteSpace([string]$repoConfig.DocPath)) -Message 'QS config should define DocPath for document searches.'
    Assert-True -Condition (-not [string]::IsNullOrWhiteSpace([string]$repoConfig.TeamPath)) -Message 'QS config should define TeamPath for TEAM searches.'
    Assert-True -Condition ($repoConfig.DocPath -eq (GetDocPathTemplate $repoConfig)) -Message 'QS should prefer config DocPath over legacy Path.'
    Assert-True -Condition ($repoConfig.TeamPath -eq (GetTeamPathTemplate $repoConfig)) -Message 'QS should read TEAM searches from config TeamPath.'
    Assert-True -Condition (200 -eq $repoConfig.MaxSearchResults) -Message 'QS config should bound default search result count.'
    Assert-True -Condition (10 -eq $repoConfig.MaxContentScanFileSizeMB) -Message 'QS config should bound default live content scan file size.'
    Assert-True -Condition ('Configured Types' -eq $repoConfig.LiveContentScanScope) -Message 'QS config should default ALL live scans to configured type roots.'
    Assert-True -Condition ($true -eq $repoConfig.UseRipgrep) -Message 'QS config should allow optional ripgrep acceleration by default.'
    Assert-True -Condition ($repoConfig.Ignored -contains 'node_modules') -Message 'QS config should ignore common dependency folders by default.'
    Assert-True -Condition ($repoConfig.Ignored -contains 'archive') -Message 'QS config should ignore common archive folders by default.'
    Assert-True -Condition ($repoConfig.IgnoredFileExtNames -contains '.zip') -Message 'QS config should ignore archive files by default.'
    Assert-True -Condition ($repoConfig.IgnoredFileExtNames -contains '.pdf') -Message 'QS config should ignore binary document formats by default.'
    Assert-True -Condition ($null -eq $repoDefaultProfile.PSObject.Properties['Ignored']) -Message 'Default profile should not duplicate global ignored folders from config.'
    Assert-True -Condition ($null -eq $repoNateProfile.PSObject.Properties['Ignored']) -Message 'Nate profile should not duplicate global ignored folders from config.'
    $selectedProfileName = GetQuickSearchSelectedProfileName -Config $repoConfig
    $selectedProfilePath = ResolveQuickSearchProfilePath -ProfilesDirectory $repoProfilesPath -ProfileName $selectedProfileName
    Assert-True -Condition (Test-Path -LiteralPath $selectedProfilePath) -Message 'QS selected profile should resolve to an existing profile file.'
    $selectedProfile = Get-Content -LiteralPath $selectedProfilePath -Raw | ConvertFrom-Json
    Assert-True -Condition ($repoConfig.DocPath -eq $selectedProfile.DocPath) -Message 'Selected profile DocPath should match config so restarts preserve saved Index paths.'
    Assert-True -Condition ($repoConfig.TeamPath -eq $selectedProfile.TeamPath) -Message 'Selected profile TeamPath should match config so restarts preserve saved Index paths.'
    Assert-True -Condition ($repoConfig.AllowedFileExtNames -contains '.txt') -Message 'QS config should include an index file extension whitelist.'
    Assert-True -Condition ($repoConfig.AllowedFileExtNames -contains '.html') -Message 'QS config should include HTML files in the index whitelist.'
    Assert-True -Condition (Test-Path -LiteralPath $repoSampleIndexPath) -Message 'QS should ship an index sample file under src\data.'
    $sampleIndex = Get-Content -LiteralPath $repoSampleIndexPath -Raw | ConvertFrom-Json
    Assert-True -Condition (2 -eq $sampleIndex.schemaVersion) -Message 'Index sample should use schemaVersion 2.'
    $sampleIndexMatches = @(SearchFileIndex -IndexFilePath $repoSampleIndexPath -Keyword 'runbook')
    Assert-True -Condition ($sampleIndexMatches -contains 'D:\Example\Orcas_Main\team\runbook.md') -Message 'Index sample should be searchable.'
    $sampleIndexSummary = GetQuickSearchIndexSummaryText -IndexFilePath $repoSampleIndexPath
    Assert-True -Condition ($sampleIndexSummary -match 'Files indexed: 2') -Message 'Index summary should report indexed file count.'
    Assert-True -Condition ($sampleIndexSummary -match 'Unique generated tags: 6') -Message 'Index summary should report unique generated tag count.'
    Assert-True -Condition ($sampleIndexSummary -match 'Search terms: 7') -Message 'Index summary should report search term count.'
    Assert-True -Condition ($sampleIndexSummary -match 'Tag assignments: 6') -Message 'Index summary should report generated tag assignments.'
    Assert-True -Condition ($sampleIndexSummary -match 'Schema version: 2') -Message 'Index summary should report schema version.'
    $missingIndexSummary = GetQuickSearchIndexSummaryText -IndexFilePath (Join-Path -Path $testRoot -ChildPath 'missing-index.json')
    Assert-True -Condition ($missingIndexSummary -match 'Status: Missing') -Message 'Index summary should report missing index files.'

    $profileFiles = @(GetQuickSearchProfileFiles -ProfilesDirectory $repoProfilesPath)
    $profileFileNames = @($profileFiles | ForEach-Object { $_.Name })
    Assert-True -Condition ($profileFileNames -contains 'default.profile.json') -Message 'Profile discovery should include default.profile.json.'
    Assert-True -Condition ($profileFileNames -contains 'nate.profile.json') -Message 'Profile discovery should include nate.profile.json.'
    Assert-True -Condition ('default.profile.json' -eq (GetQuickSearchDefaultProfileName)) -Message 'Default profile name should be default.profile.json.'
    Assert-True -Condition ('default.profile.json' -eq (GetQuickSearchSelectedProfileName -Config ([PSCustomObject]@{}))) -Message 'Missing profile setting should select the default profile.'
    Assert-True -Condition ($repoDefaultProfilePath -eq (ResolveQuickSearchProfilePath -ProfilesDirectory $repoProfilesPath -ProfileName 'missing.profile.json')) -Message 'Missing selected profile should resolve to default.profile.json.'
    $nateConfig = [PSCustomObject]@{ DriveLetter = 'Z'; Path = ':\Old\Docs\'; TeamPath = ':\Old\Team\'; Types = @('ALL'); Ignored = @('node_modules', 'archive') }
    $nateProfileState = UseQuickSearchProfile -Config $nateConfig -ProfilesDirectory $repoProfilesPath -ProfileName 'nate.profile.json'
    Assert-True -Condition ($nateProfileState.Applied) -Message 'UseQuickSearchProfile should apply an existing profile.'
    Assert-True -Condition ('nate.profile.json' -eq $nateProfileState.Name) -Message 'Applied profile state should report the selected profile name.'
    Assert-True -Condition ('D' -eq $nateConfig.DriveLetter) -Message 'Profile should override DriveLetter.'
    Assert-True -Condition ($repoNateProfile.DocPath -eq $nateConfig.Path) -Message 'Profile DocPath should override config Path.'
    Assert-True -Condition ($repoNateProfile.TeamPath -eq $nateConfig.TeamPath) -Message 'Profile should override TeamPath.'
    Assert-True -Condition ($nateConfig.Types -contains 'TEAM') -Message 'Profile should override search Types.'
    Assert-True -Condition ($nateConfig.Ignored -contains 'node_modules') -Message 'Profile should preserve global ignored folders when the profile does not override them.'
    Assert-True -Condition ('nate.profile.json' -eq $nateConfig.ProfileName) -Message 'Profile apply should persist the selected profile name in config.'

    $quickSearchScriptPaths = @(Get-ChildItem -LiteralPath (Join-Path -Path $repoRoot -ChildPath 'src') -Recurse -File -Filter 'QuickSearch*.ps1' | ForEach-Object { $_.FullName })
    Assert-True -Condition ($quickSearchScriptPaths.Count -ge 4) -Message 'Expected QuickSearch runtime source scripts and archived tools.'
    foreach ($quickSearchScriptPath in $quickSearchScriptPaths) {
        $quickSearchScriptContent = Get-Content -LiteralPath $quickSearchScriptPath -Raw
        [scriptblock]::Create($quickSearchScriptContent) | Out-Null
    }

    $mainScriptContent = Get-Content -LiteralPath $scriptPath -Raw
    Assert-True -Condition ($mainScriptContent -match 'if\s*\(\s*\$env:QS_PAUSE_ON_EXIT\s+-eq\s+''1''\s*\)\s*\{\s*Pause\s*\}') -Message 'QuickSearch.ps1 should only pause on exit when QS_PAUSE_ON_EXIT=1.'
    Assert-True -Condition ($mainScriptContent -match 'Content \(Slow\)') -Message 'Content-search radio label should be concise.'
    Assert-True -Condition ($mainScriptContent -match 'Scanning file content live') -Message 'Content-search progress message should clarify that content search scans live files.'
    Assert-True -Condition ($mainScriptContent -match 'InitializeQuickSearchKeywordPlaceholder') -Message 'Keyword textbox should initialize placeholder behavior.'
    Assert-True -Condition ($mainScriptContent -match 'GetQuickSearchKeywordText') -Message 'Search should read the user keyword without treating placeholder text as input.'
    Assert-True -Condition ($mainScriptContent -match 'ComboBox_LiveScanScope') -Message 'UI should expose a Live Content Scan scope selector.'
    Assert-True -Condition ($mainScriptContent -match 'Configured Types') -Message 'UI should default Live Content Scan scope to configured type roots.'
    Assert-True -Condition ($mainScriptContent -match 'TextBox_ResultFilter') -Message 'UI should expose a result filter textbox.'
    Assert-True -Condition ($mainScriptContent -match 'Button_ClearResultFilter') -Message 'UI should expose a clear filter button.'
    Assert-True -Condition ($mainScriptContent -match 'Panel_ResultSort') -Message 'Result sort radio buttons should live in an isolated panel.'
    Assert-True -Condition ($mainScriptContent -match '\$ListBox_Results\.HorizontalScrollbar\s*=\s*\$false') -Message 'Result list should use ellipsis instead of horizontal scrolling for long paths.'
    Assert-True -Condition ($mainScriptContent -match 'ResultListToolTip') -Message 'Result list should expose a hover tooltip for full paths.'
    Assert-True -Condition ($mainScriptContent -match 'Add_MouseMove') -Message 'Result list should update the full-path tooltip on hover.'
    Assert-True -Condition ($mainScriptContent -match 'RadioButton_SortNameAsc') -Message 'UI should expose Name A-Z sort.'
    Assert-True -Condition ($mainScriptContent -match 'RadioButton_SortNameDesc') -Message 'UI should expose Name Z-A sort.'
    Assert-True -Condition ($mainScriptContent -match 'RadioButton_SortModified') -Message 'UI should expose modified-time sort.'
    Assert-True -Condition ($mainScriptContent -match 'RadioButton_SortCreated') -Message 'UI should expose created-time sort.'
    Assert-True -Condition ($mainScriptContent -notmatch 'RadioButton_SortAccessed') -Message 'UI should not expose accessed-time sort.'
    Assert-True -Condition ($mainScriptContent -match 'NewQuickSearchResultItem') -Message 'Search results should be wrapped with file metadata for display.'
    Assert-True -Condition ($mainScriptContent -match 'SelectQuickSearchResultItems') -Message 'Result list should support simple text filtering.'
    Assert-True -Condition ($mainScriptContent -match 'SortQuickSearchResultItems') -Message 'Result list should support simple radio-button sorting.'
    Assert-True -Condition ($mainScriptContent -match 'GetQuickSearchResultItemDisplayTextForWidth') -Message 'Result drawing should shorten long paths to fit the visible list width.'
    Assert-True -Condition ($mainScriptContent -match 'GetQuickSearchResultItemPath') -Message 'Open and preview actions should read the real path from result items.'
    Assert-True -Condition ($mainScriptContent -match 'Button_PreviewSearch') -Message 'Preview pane should expose an in-preview search button.'
    Assert-True -Condition ($mainScriptContent -match 'TextBox_PreviewSearch') -Message 'Preview pane should expose an in-preview search textbox.'
    Assert-True -Condition ($mainScriptContent -match '\$Button_PreviewSearch\.Text\s*=\s*''Find''') -Message 'Preview search button should use Find text.'
    Assert-True -Condition ($mainScriptContent -match 'NewQuickSearchFindButtonIcon') -Message 'Preview search button should include an embedded magnifying-glass image.'
    Assert-True -Condition ($mainScriptContent -match 'TextImageRelation\]::ImageBeforeText') -Message 'Preview search button should show the icon before Find text.'
    Assert-True -Condition ($mainScriptContent -match 'Button_About') -Message 'UI should expose an About button.'
    Assert-True -Condition ($mainScriptContent -match 'ShowQuickSearchAbout') -Message 'About button should open the About popup.'
    Assert-True -Condition ($mainScriptContent -match '\$Label_LiveScanScope\.Location\s*=\s*New-Object System\.Drawing\.Point\(505, 10\)') -Message 'Scope label should be moved 10px left in the top row.'
    Assert-True -Condition ($mainScriptContent -match '\$ComboBox_LiveScanScope\.Location\s*=\s*New-Object System\.Drawing\.Point\(545, 10\)') -Message 'Scope selector should be moved 10px left in the top row.'
    Assert-True -Condition ($mainScriptContent -match '\$TextBox_Keyword\.Location\s*=\s*New-Object System\.Drawing\.Point\(670, 10\)') -Message 'Keyword textbox should be moved 10px left in the top row.'
    Assert-True -Condition ($mainScriptContent -match '\$TextBox_Keyword\.Width\s*=\s*240') -Message 'Keyword textbox should stay widened for multi-keyword queries.'
    Assert-True -Condition ($mainScriptContent -match '\$Button_Search\.Location\s*=\s*New-Object System\.Drawing\.Point\(920, 10\)') -Message 'Search button should align with the widened keyword textbox.'
    Assert-True -Condition ($mainScriptContent -match '\$Button_Index\.Location\s*=\s*New-Object System\.Drawing\.Point\(1005, 10\)') -Message 'Index button should align with the shifted top-row action group.'
    Assert-True -Condition ($mainScriptContent -match '\$Button_PreviewToggle\.Location\s*=\s*New-Object System\.Drawing\.Point\(1090, 10\)') -Message 'Preview toggle should align with the shifted top-row action group.'
    Assert-True -Condition ($mainScriptContent -match '\$Button_Settings\.Location\s*=\s*New-Object System\.Drawing\.Point\(1205, 10\)') -Message 'Settings button should align with the shifted top-row action group.'
    Assert-True -Condition ($mainScriptContent -match '\$Button_About\.Location\s*=\s*New-Object System\.Drawing\.Point\(1290, 10\)') -Message 'About button should align with the shifted top-row action group.'
    Assert-True -Condition ($mainScriptContent -match '\$Button_About\.Width\s*=\s*55') -Message 'About button should leave room for the shifted Status controls.'
    Assert-True -Condition ($mainScriptContent -match '\$Label_Status\.Location\s*=\s*New-Object System\.Drawing\.Point\(\$\(\$config\.Width - 152\), 10\)') -Message 'Status label should be moved 10px left in the top row.'
    Assert-True -Condition ($mainScriptContent -match '\$TextBox_Status\.Location\s*=\s*New-Object System\.Drawing\.Point\(\$\(\$config\.Width - 110\), 10\)') -Message 'Status textbox should be moved 10px left in the top row.'
    Assert-True -Condition ($mainScriptContent -match '\$highlightPreviewKeyword\s*=\s*-not \[string\]::IsNullOrWhiteSpace\(\$SearchState\.Keyword\)') -Message 'Preview keyword highlighting should use the active search keyword, not only live content scan state.'
    $supportScriptContent = Get-Content -LiteralPath $supportScriptPath -Raw
    Assert-True -Condition ($supportScriptContent -match 'Author: Nate Scott \(NASCO\)') -Message 'About popup should include the author.'
    Assert-True -Condition ($supportScriptContent -match 'Email: nate\.scott@microsoft\.com') -Message 'About popup should include the contact email.'
    Assert-True -Condition ($supportScriptContent -match 'Basic use:') -Message 'About popup should include simple usage guidance.'
    Assert-True -Condition ($supportScriptContent -match 'Use Content \(Slow\)') -Message 'About popup should use the concise content-search label.'
    Assert-True -Condition ($supportScriptContent -match 'Function SetQuickSearchDialogCenter') -Message 'QS should define a shared dialog centering helper.'
    Assert-True -Condition ($supportScriptContent -match 'Function ShowQuickSearchMessageBox') -Message 'QS message boxes should use an owner-aware helper.'
    Assert-True -Condition ($supportScriptContent -match 'Function GetQuickSearchIndexSummaryText') -Message 'Index Settings should be able to summarize current index data.'
    Assert-True -Condition ($supportScriptContent -match 'Function GetQuickSearchIndexFileSummaryText') -Message 'Index Settings should open with a lightweight index file summary.'
    Assert-True -Condition ($supportScriptContent -match 'Click Refresh Data for full index counts') -Message 'Index Settings should defer full index counts until requested.'
    Assert-True -Condition ($supportScriptContent -match '\$Button_RefreshIndexData\.Text\s*=\s*''Refresh Data''') -Message 'Index Settings should expose an explicit full-data refresh button.'
    Assert-True -Condition ($supportScriptContent -match 'SaveQuickSearchProfilePathSettings') -Message 'Index Settings should save edited paths to the active profile.'
    Assert-True -Condition ($supportScriptContent -match 'Function NewQuickSearchResultItem') -Message 'Support helpers should create display-ready result items with file timestamps.'
    Assert-True -Condition ($supportScriptContent -match 'Function SelectQuickSearchResultItems') -Message 'Support helpers should filter result items.'
    Assert-True -Condition ($supportScriptContent -match 'Function TestQuickSearchFilterText') -Message 'Support helpers should evaluate result filter boolean syntax.'
    Assert-True -Condition ($supportScriptContent -match 'Filter syntax:') -Message 'About popup should explain result filter syntax.'
    Assert-True -Condition ($supportScriptContent -match 'access `and report') -Message 'About popup should explain backtick escape for literal operator words.'
    Assert-True -Condition ($supportScriptContent -match 'Function SortQuickSearchResultItems') -Message 'Support helpers should sort result items.'
    Assert-True -Condition ($supportScriptContent -match '\$Label_IndexData\.Text\s*=\s*''Index data''') -Message 'Index Settings should show an index data area.'
    Assert-True -Condition ($supportScriptContent -match '\$Button_RebuildIndex\.Location\s*=\s*New-Object System\.Drawing\.Point\(\$labelLeft, 465\)') -Message 'Re-Index button should be positioned at the lower-left of Index Settings.'
    Assert-True -Condition ($supportScriptContent -match '\$Button_Save\.Location\s*=\s*New-Object System\.Drawing\.Point\(470, 465\)') -Message 'Save button should be positioned at the lower-right of Index Settings.'
    Assert-True -Condition ($supportScriptContent -match '\$Button_Close\.Location\s*=\s*New-Object System\.Drawing\.Point\(560, 465\)') -Message 'Close button should be positioned at the lower-right of Index Settings.'
    Assert-True -Condition ($supportScriptContent -match 'Add_Enter') -Message 'Keyword placeholder should clear when the textbox receives focus.'
    Assert-True -Condition ($supportScriptContent -match 'Add_Leave') -Message 'Keyword placeholder should restore when the textbox loses focus empty.'
    $asyncScriptContent = Get-Content -LiteralPath $asyncScriptPath -Raw
    Assert-True -Condition ($asyncScriptContent -match 'SetQuickSearchDialogCenter -Dialog \$processingForm -Owner \$Owner') -Message 'Processing dialogs should center on the owning form before display.'
    Assert-True -Condition ($asyncScriptContent -match 'SetQuickSearchDialogCenter -Dialog \$processingDialog -Owner \$Owner') -Message 'Resized processing dialogs should recenter on the owning form.'
    Assert-True -Condition ($asyncScriptContent -match '\$messageLabel\.Text\s*=\s*\$Message') -Message 'Background search dialog body should show only the search message.'
    Assert-True -Condition ($asyncScriptContent -notmatch 'Elapsed:') -Message 'Elapsed time should not be duplicated in the search dialog body.'
    Assert-True -Condition ($mainScriptContent -match '-Config \$config') -Message 'UI background searches should pass runtime config for live content scan filtering.'
    Assert-True -Condition ($asyncScriptContent -match 'JobSelectedType') -Message 'Background search should receive the selected search type.'
    Assert-True -Condition ($asyncScriptContent -match 'JobScanScope') -Message 'Background search should receive the live scan scope.'

    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    $metadataResultPath = Join-Path -Path $testRoot -ChildPath 'metadata-result.txt'
    Set-Content -LiteralPath $metadataResultPath -Value 'metadata result content' -NoNewline
    $metadataResultItem = NewQuickSearchResultItem -Path $metadataResultPath
    Assert-True -Condition ($metadataResultItem.DisplayText.Contains($metadataResultPath)) -Message 'Result item display should include the file path.'
    Assert-True -Condition ($metadataResultItem.DisplayText.Contains('Modified:')) -Message 'Result item display should include last modified time.'
    Assert-True -Condition ($metadataResultItem.DisplayText.Contains('Created:')) -Message 'Result item display should include created time.'
    Assert-True -Condition (-not $metadataResultItem.DisplayText.Contains('Accessed:')) -Message 'Result item display should not include last accessed time.'
    Assert-True -Condition ($metadataResultItem.DisplayText.IndexOf('Modified:', [System.StringComparison]::Ordinal) -lt $metadataResultItem.DisplayText.IndexOf($metadataResultPath, [System.StringComparison]::Ordinal)) -Message 'Result item display should put timestamps before the path.'
    Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($metadataResultItem.MetadataText)) -Message 'Result item should keep date metadata separate from path for drawing.'
    Assert-True -Condition ($metadataResultPath -eq (GetQuickSearchResultItemPath -Item $metadataResultItem)) -Message 'Result item path helper should return the real file path.'
    Assert-True -Condition ($metadataResultItem.DisplayText -eq (GetQuickSearchResultItemDisplayText -Item $metadataResultItem)) -Message 'Result item display helper should return metadata display text.'
    $filteredMetadataResults = @(SelectQuickSearchResultItems -Items @($metadataResultItem) -FilterText 'metadata-result Modified')
    Assert-True -Condition (1 -eq $filteredMetadataResults.Count) -Message 'Result filter should match path and metadata text.'
    $noMetadataResults = @(SelectQuickSearchResultItems -Items @($metadataResultItem) -FilterText 'not-present')
    Assert-True -Condition (0 -eq $noMetadataResults.Count) -Message 'Result filter should remove nonmatching results.'
    $filterSyntaxItems = @(
        [PSCustomObject]@{ Name = 'access-report.txt'; Path = 'C:\access-report.txt'; DisplayText = 'access report'; MetadataText = 'Modified: 2024-01-01 00:00'; LastWriteTime = [datetime]'2024-01-01'; CreationTime = [datetime]'2024-01-01' },
        [PSCustomObject]@{ Name = 'access-and-report.txt'; Path = 'C:\access-and-report.txt'; DisplayText = 'access and report'; MetadataText = 'Modified: 2024-01-02 00:00'; LastWriteTime = [datetime]'2024-01-02'; CreationTime = [datetime]'2024-01-02' },
        [PSCustomObject]@{ Name = 'draft-access.txt'; Path = 'C:\draft-access.txt'; DisplayText = 'draft access'; MetadataText = 'Modified: 2024-01-03 00:00'; LastWriteTime = [datetime]'2024-01-03'; CreationTime = [datetime]'2024-01-03' }
    )
    Assert-True -Condition (2 -eq @(SelectQuickSearchResultItems -Items $filterSyntaxItems -FilterText 'access and report').Count) -Message 'Result filter should treat and as a boolean operator.'
    Assert-True -Condition (1 -eq @(SelectQuickSearchResultItems -Items $filterSyntaxItems -FilterText 'access `and report').Count) -Message 'Result filter should use backtick to search operator words literally.'
    Assert-True -Condition (3 -eq @(SelectQuickSearchResultItems -Items $filterSyntaxItems -FilterText 'report or draft').Count) -Message 'Result filter should support or clauses.'
    Assert-True -Condition (2 -eq @(SelectQuickSearchResultItems -Items $filterSyntaxItems -FilterText 'access not draft').Count) -Message 'Result filter should support not exclusion.'
    $sortSampleItems = @(
        [PSCustomObject]@{ Name = 'beta.txt'; Path = 'C:\beta.txt'; DisplayText = 'beta'; LastWriteTime = [datetime]'2024-01-01'; CreationTime = [datetime]'2024-01-03' },
        [PSCustomObject]@{ Name = 'alpha.txt'; Path = 'C:\alpha.txt'; DisplayText = 'alpha'; LastWriteTime = [datetime]'2024-01-05'; CreationTime = [datetime]'2024-01-01' }
    )
    Assert-True -Condition ('alpha.txt' -eq @(SortQuickSearchResultItems -Items $sortSampleItems -SortMode 'NameAsc')[0].Name) -Message 'Result sort should support Name A-Z.'
    Assert-True -Condition ('beta.txt' -eq @(SortQuickSearchResultItems -Items $sortSampleItems -SortMode 'NameDesc')[0].Name) -Message 'Result sort should support Name Z-A.'
    Assert-True -Condition ('alpha.txt' -eq @(SortQuickSearchResultItems -Items $sortSampleItems -SortMode 'Modified')[0].Name) -Message 'Result sort should support newest modified time first.'
    Assert-True -Condition ('beta.txt' -eq @(SortQuickSearchResultItems -Items $sortSampleItems -SortMode 'Created')[0].Name) -Message 'Result sort should support newest created time first.'

    $searchScriptPath = Join-Path -Path $repoRoot -ChildPath 'src\QuickSearch.Search.ps1'
    $searchScriptContent = Get-Content -LiteralPath $searchScriptPath -Raw
    Assert-True -Condition ($searchScriptContent -match 'MaxSearchResults') -Message 'Filesystem search should support a max result count.'
    Assert-True -Condition ($searchScriptContent -match 'MaxContentScanFileSizeMB') -Message 'Live content scan should support a max file size.'
    Assert-True -Condition ($searchScriptContent -match 'GetQuickSearchIndexCandidateFiles') -Message 'TEAM live content scan should be able to reuse index document candidates.'
    Assert-True -Condition ($searchScriptContent -match 'InvokeQuickSearchRipgrepSearch') -Message 'Live content scan should optionally use ripgrep.'
    Assert-True -Condition ($searchScriptContent -match 'TestQuickSearchDirectoryAllowed') -Message 'PowerShell live scan fallback should prune ignored directories.'

    $indexScriptPath = Join-Path -Path $repoRoot -ChildPath 'src\QuickSearch.Index.ps1'
    $indexScriptContent = Get-Content -LiteralPath $indexScriptPath -Raw
    $indexShardScriptContent = Get-Content -LiteralPath $repoShardScriptPath -Raw
    Assert-True -Condition ($indexScriptContent -notmatch '\$content\s*=\s*Get-Content\s+-LiteralPath\s+\$FilePath\s+-Raw') -Message 'Top-word indexing should not read an entire target file into memory.'
    Assert-True -Condition ($indexScriptContent -notmatch '\$words\s*=\s*\$content\s+-split') -Message 'Top-word indexing should not materialize all split words at once.'
    Assert-True -Condition ($indexScriptContent -match 'ReadCachedFileIndexData') -Message 'Index searches should read JSON through the reusable cached index data helper.'
    Assert-True -Condition ($indexScriptContent -match 'QuickSearchFileIndexCache') -Message 'Index searches should cache parsed index JSON within the current process.'
    Assert-True -Condition ($indexScriptContent -match 'LastWriteUtcTicks') -Message 'Index cache entries should be invalidated by file timestamp metadata.'
    Assert-True -Condition ($indexScriptContent -match 'WriteFileIndexShardsFromData') -Message 'Index rebuild should write sharded schema v3 output.'
    Assert-True -Condition ($indexShardScriptContent -match 'Function SearchShardedFileIndex') -Message 'Shard helper should provide sharded TEAM quick search.'
    Assert-True -Condition ($indexShardScriptContent -match 'schemaVersion = 3') -Message 'Shard helper should write schema v3 shard data.'

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
    SetConfigValue -Config $settingsConfig -Name 'DocPath' -Value ':\Orcas_Main\TSG-SOP\'
    SetConfigValue -Config $settingsConfig -Name 'TeamPath' -Value ':\Orcas_Main\team\'
    SetConfigValue -Config $settingsConfig -Name 'Version' -Value '9.8.7'
    SetConfigValue -Config $settingsConfig -Name 'TagCount' -Value 4
    SetConfigValue -Config $settingsConfig -Name 'MaxTagFileSizeMB' -Value 2
    SetConfigValue -Config $settingsConfig -Name 'AllowedFileExtNames' -Value @('.txt', '.md')
    SetConfigValue -Config $settingsConfig -Name 'IgnoredFileExtNames' -Value @('.tmp')
    $settingsConfigPath = Join-Path -Path (Join-Path -Path $testRoot -ChildPath 'settings') -ChildPath 'config.json'
    SaveConfig -Config $settingsConfig -ConfigPath $settingsConfigPath
    $savedSettings = Get-Content -LiteralPath $settingsConfigPath -Raw | ConvertFrom-Json
    Assert-True -Condition ('D:\Orcas_Main\TSG-SOP\' -eq (ResolveConfiguredPath -DriveLetter 'D' -PathTemplate (GetDocPathTemplate $savedSettings))) -Message 'Saved DocPath template should resolve with the selected drive.'
    Assert-True -Condition ('D:\Orcas_Main\team\' -eq (ResolveConfiguredPath -DriveLetter 'D' -PathTemplate (GetTeamPathTemplate $savedSettings))) -Message 'Saved TEAM path template should resolve with the selected drive.'
    Assert-True -Condition ('9.8.7' -eq $savedSettings.Version) -Message 'SaveConfig should persist Version.'
    Assert-True -Condition (4 -eq $savedSettings.TagCount) -Message 'SaveConfig should persist TagCount.'
    Assert-True -Condition (2 -eq $savedSettings.MaxTagFileSizeMB) -Message 'SaveConfig should persist MaxTagFileSizeMB.'
    Assert-True -Condition ($savedSettings.AllowedFileExtNames -contains '.md') -Message 'SaveConfig should persist AllowedFileExtNames.'
    Assert-True -Condition ($savedSettings.IgnoredFileExtNames -contains '.tmp') -Message 'SaveConfig should persist array settings.'

    $profileSaveRoot = Join-Path -Path $testRoot -ChildPath 'profile-save'
    New-Item -ItemType Directory -Path $profileSaveRoot -Force | Out-Null
    $profileSavePath = Join-Path -Path $profileSaveRoot -ChildPath 'active.profile.json'
    [PSCustomObject]@{
        DriveLetter = 'X'
        DocPath = ':\Before\Docs\'
        TeamPath = ':\Before\Team\'
        Types = @('ALL', 'TEAM')
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $profileSavePath
    $profileSaveConfig = [PSCustomObject]@{
        ProfileName = 'active.profile.json'
        DocPath = ':\After\Docs\'
        Path = ':\After\Docs\'
        TeamPath = ':\After\Team\'
    }
    $profileSaveResult = SaveQuickSearchProfilePathSettings -Config $profileSaveConfig -ProfilesDirectory $profileSaveRoot -DriveLetter 'Q'
    Assert-True -Condition ($null -ne $profileSaveResult) -Message 'Profile path settings save should return the saved profile state.'
    $savedProfile = Get-Content -LiteralPath $profileSavePath -Raw | ConvertFrom-Json
    Assert-True -Condition ('Q' -eq $savedProfile.DriveLetter) -Message 'Profile path settings save should persist the selected drive letter.'
    Assert-True -Condition (':\After\Docs\' -eq $savedProfile.DocPath) -Message 'Profile path settings save should persist DocPath.'
    Assert-True -Condition (':\After\Team\' -eq $savedProfile.TeamPath) -Message 'Profile path settings save should persist TeamPath.'

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
    $highlightedHtml = ConvertHtmlToPreviewDocument -Html '<html><head><title>alpha hidden title</title></head><body><p>alpha beta</p><a href="javascript:alert(1)" onclick="bad()">alpha</a><script>bad()</script></body></html>' -Keyword 'alpha'
    Assert-True -Condition ($highlightedHtml.Contains('<span id="qs-active-highlight" class="qs-highlight">alpha</span> beta')) -Message 'HTML preview should highlight active search keywords.'
    Assert-True -Condition ($highlightedHtml.Contains('<span class="qs-highlight">alpha</span>')) -Message 'HTML preview should highlight later active search keyword matches.'
    Assert-True -Condition (1 -eq ([regex]::Matches($highlightedHtml, 'id="qs-active-highlight"').Count)) -Message 'HTML preview should only mark one active search keyword for scrolling.'
    Assert-True -Condition ($highlightedHtml.Contains('<title>alpha hidden title</title>')) -Message 'HTML preview secondary search should not target hidden head/title text.'
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
    $resultFilterLabel = New-Object System.Windows.Forms.Label
    $resultFilterTextBox = New-Object System.Windows.Forms.TextBox
    $resultFilterButton = New-Object System.Windows.Forms.Button
    $resultSortPanel = New-Object System.Windows.Forms.Panel
    $resultSortLabel = New-Object System.Windows.Forms.Label
    $resultSortNameAsc = New-Object System.Windows.Forms.RadioButton
    $resultSortNameAsc.Text = 'Name A-Z'
    $resultSortNameDesc = New-Object System.Windows.Forms.RadioButton
    $resultSortNameDesc.Text = 'Name Z-A'
    $resultSortModified = New-Object System.Windows.Forms.RadioButton
    $resultSortModified.Text = 'Modified'
    $resultSortCreated = New-Object System.Windows.Forms.RadioButton
    $resultSortCreated.Text = 'Created'
    foreach ($resultSortControl in @($resultSortLabel, $resultSortNameAsc, $resultSortNameDesc, $resultSortModified, $resultSortCreated)) {
        $resultSortPanel.Controls.Add($resultSortControl)
    }
    $resultSortButtons = @($resultSortNameAsc, $resultSortNameDesc, $resultSortModified, $resultSortCreated)
    $previewSearchTextBox = New-Object System.Windows.Forms.TextBox
    $previewSearchButton = New-Object System.Windows.Forms.Button
    $previewHost = NewQuickSearchPreviewHost -TextBox $previewRichTextBox -Browser $previewBrowser -SearchTextBox $previewSearchTextBox -SearchButton $previewSearchButton
    $findIcon = NewQuickSearchFindButtonIcon
    try {
        Assert-True -Condition (16 -eq $findIcon.Width -and 16 -eq $findIcon.Height) -Message 'Preview Find button icon should be a compact embedded bitmap.'
    }
    finally {
        $findIcon.Dispose()
    }
    $ellipsisBitmap = New-Object System.Drawing.Bitmap(320, 30)
    $ellipsisGraphics = [System.Drawing.Graphics]::FromImage($ellipsisBitmap)
    try {
        $longPathDisplayItem = [PSCustomObject]@{
            MetadataText = 'Modified: 2024-01-01 00:00'
            Path = 'D:\very\long\folder\structure\that\does\not\fit\example-document.html'
            DisplayText = 'Modified: 2024-01-01 00:00    D:\very\long\folder\structure\that\does\not\fit\example-document.html'
        }
        $ellipsizedResultText = GetQuickSearchResultItemDisplayTextForWidth -Item $longPathDisplayItem -Graphics $ellipsisGraphics -Font ([System.Drawing.SystemFonts]::DefaultFont) -MaxWidth 260
        Assert-True -Condition ($ellipsizedResultText.StartsWith('Modified: 2024-01-01 00:00')) -Message 'Ellipsized result text should keep dates at the front.'
        Assert-True -Condition ($ellipsizedResultText.Contains('...')) -Message 'Ellipsized result text should shorten long paths with dots.'
    }
    finally {
        $ellipsisGraphics.Dispose()
        $ellipsisBitmap.Dispose()
    }
    SetQuickSearchPreviewPanelState -Form $previewForm -ResultsListBox $previewListBox -PreviewHost $previewHost -PreviewButton $previewToggleButton -Expanded $false -FilterLabel $resultFilterLabel -FilterTextBox $resultFilterTextBox -FilterButton $resultFilterButton -SortPanel $resultSortPanel -SortLabel $resultSortLabel -SortButtons $resultSortButtons
    $collapsedListWidth = $previewListBox.Width
    Assert-True -Condition (-not $previewRichTextBox.Visible) -Message 'Preview pane should be hidden when collapsed.'
    Assert-True -Condition (-not $previewBrowser.Visible) -Message 'HTML preview pane should be hidden when collapsed.'
    Assert-True -Condition $resultFilterLabel.Visible -Message 'Result filter label should be visible in the results pane.'
    Assert-True -Condition $resultFilterTextBox.Visible -Message 'Result filter textbox should be visible in the results pane.'
    Assert-True -Condition $resultFilterButton.Visible -Message 'Result filter clear button should be visible in the results pane.'
    Assert-True -Condition $resultSortPanel.Visible -Message 'Result sort panel should be visible in the results pane.'
    Assert-True -Condition $resultSortNameAsc.Visible -Message 'Result sort radio buttons should be visible in the results pane.'
    Assert-True -Condition ($previewListBox.Location.Y -gt ($resultSortPanel.Location.Y + $resultSortPanel.Height)) -Message 'Results list should sit below the result filter and sort controls.'
    Assert-True -Condition (-not $previewSearchTextBox.Visible) -Message 'Preview search textbox should be hidden when preview is collapsed.'
    Assert-True -Condition (-not $previewSearchButton.Visible) -Message 'Preview search button should be hidden when preview is collapsed.'
    Assert-True -Condition ('Show Preview' -eq $previewToggleButton.Text) -Message 'Preview toggle should offer to show preview when collapsed.'
    Assert-True -Condition ($collapsedListWidth -gt 900) -Message 'Results list should use nearly the full width when preview is collapsed.'

    SetQuickSearchPreviewPanelState -Form $previewForm -ResultsListBox $previewListBox -PreviewHost $previewHost -PreviewButton $previewToggleButton -Expanded $true -FilterLabel $resultFilterLabel -FilterTextBox $resultFilterTextBox -FilterButton $resultFilterButton -SortPanel $resultSortPanel -SortLabel $resultSortLabel -SortButtons $resultSortButtons
    Assert-True -Condition $previewRichTextBox.Visible -Message 'Preview pane should be visible when expanded.'
    Assert-True -Condition $previewSearchTextBox.Visible -Message 'Preview search textbox should be visible when preview is expanded.'
    Assert-True -Condition $previewSearchButton.Visible -Message 'Preview search button should be visible when preview is expanded.'
    Assert-True -Condition ($previewSearchButton.Width -ge 70) -Message 'Preview Find button should have room for icon and text.'
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
    $limitedDocuments = @(Get-TestFileIndexDocuments -Path $limitedIndexPath)
    $largeDocument = @($limitedDocuments | Where-Object { $_.name -eq 'large.txt' })[0]
    Assert-True -Condition ($null -ne $largeDocument) -Message 'Large files should still be indexed by name/path.'
    Assert-True -Condition (0 -eq @($largeDocument.tags).Count) -Message 'Large files over the limit should skip generated tag extraction.'
    Assert-True -Condition (Test-TestFileIndexTermContainsDocumentId -Path $limitedIndexPath -Term 'large' -DocumentId $largeDocument.id) -Message 'Large files should remain searchable by filename terms.'

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
    $whitelistDocuments = @(Get-TestFileIndexDocuments -Path $whitelistIndexPath)
    Assert-True -Condition (2 -eq $whitelistDocuments.Count) -Message 'Extension whitelist should index only allowed extensions.'
    Assert-True -Condition (0 -eq @($whitelistDocuments | Where-Object { $_.name -eq 'blocked.log' }).Count) -Message 'Extension whitelist should skip blocked extensions.'
    $blockedMatches = @(SearchFileIndex -IndexFilePath $whitelistIndexPath -Keyword 'blocked')
    Assert-True -Condition (0 -eq $blockedMatches.Count) -Message 'Blocked extension files should not be searchable.'
    $liveBlockedMatches = @(SearchFiles -Root $whitelistRoot -Keyword 'blocked' -SearchContent $true -Config $whitelistConfig)
    Assert-True -Condition (0 -eq $liveBlockedMatches.Count) -Message 'Live content scan should skip files excluded by the extension whitelist.'
    $liveAllowedMatches = @(SearchFiles -Root $whitelistRoot -Keyword 'allowlist' -SearchContent $true -Config $whitelistConfig)
    Assert-True -Condition ($liveAllowedMatches -contains $allowedTextPath) -Message 'Live content scan should keep allowed text files.'
    Assert-True -Condition ($liveAllowedMatches -contains $allowedMarkdownPath) -Message 'Live content scan should keep allowed Markdown files.'

    $searchLimitRoot = Join-Path -Path $testRoot -ChildPath 'search-limits'
    New-Item -ItemType Directory -Path $searchLimitRoot -Force | Out-Null
    $limitOnePath = Join-Path -Path $searchLimitRoot -ChildPath 'limit-one.txt'
    $limitTwoPath = Join-Path -Path $searchLimitRoot -ChildPath 'limit-two.txt'
    $limitThreePath = Join-Path -Path $searchLimitRoot -ChildPath 'limit-three.txt'
    Set-Content -LiteralPath $limitOnePath -Value 'limitneedle one' -NoNewline
    Set-Content -LiteralPath $limitTwoPath -Value 'limitneedle two' -NoNewline
    Set-Content -LiteralPath $limitThreePath -Value 'limitneedle three' -NoNewline
    $limitConfig = [PSCustomObject]@{
        MaxSearchResults = 2
        MaxContentScanFileSizeMB = 10
        UseRipgrep = $false
        AllowedFileExtNames = @('.txt')
        IgnoredFilenames = @()
        IgnoredFileExtNames = @()
        Ignored = @()
    }
    $limitedContentMatches = @(SearchFiles -Root $searchLimitRoot -Keyword 'limitneedle' -SearchContent $true -Config $limitConfig)
    Assert-True -Condition (2 -eq $limitedContentMatches.Count) -Message 'Live content scan should stop at MaxSearchResults.'
    $limitedFilenameMatches = @(SearchFiles -Root $searchLimitRoot -Keyword 'limit' -SearchContent $false -Config $limitConfig)
    Assert-True -Condition (2 -eq $limitedFilenameMatches.Count) -Message 'Filename search should stop at MaxSearchResults.'

    $largeContentPath = Join-Path -Path $searchLimitRoot -ChildPath 'large-content.txt'
    Set-Content -LiteralPath $largeContentPath -Value ('largeonly ' * 140000) -NoNewline
    $sizeLimitConfig = [PSCustomObject]@{
        MaxSearchResults = 10
        MaxContentScanFileSizeMB = 1
        UseRipgrep = $false
        AllowedFileExtNames = @('.txt')
        IgnoredFilenames = @()
        IgnoredFileExtNames = @()
        Ignored = @()
    }
    $largeContentMatches = @(SearchFiles -Root $searchLimitRoot -Keyword 'largeonly' -SearchContent $true -Config $sizeLimitConfig)
    Assert-True -Condition (0 -eq $largeContentMatches.Count) -Message 'Live content scan should skip files larger than MaxContentScanFileSizeMB.'

    $ignoredTraversalRoot = Join-Path -Path $testRoot -ChildPath 'ignored-traversal'
    $ignoredNodeModules = Join-Path -Path $ignoredTraversalRoot -ChildPath 'node_modules'
    New-Item -ItemType Directory -Path $ignoredNodeModules -Force | Out-Null
    Set-Content -LiteralPath (Join-Path -Path $ignoredNodeModules -ChildPath 'ignored-hit.txt') -Value 'ignoredneedle' -NoNewline
    $ignoredTraversalConfig = [PSCustomObject]@{
        MaxSearchResults = 10
        MaxContentScanFileSizeMB = 10
        UseRipgrep = $false
        AllowedFileExtNames = @('.txt')
        IgnoredFilenames = @()
        IgnoredFileExtNames = @()
        Ignored = @('node_modules')
    }
    $ignoredTraversalMatches = @(SearchFiles -Root $ignoredTraversalRoot -Keyword 'ignoredneedle' -SearchContent $true -Config $ignoredTraversalConfig)
    Assert-True -Condition (0 -eq $ignoredTraversalMatches.Count) -Message 'PowerShell live scan fallback should not enter ignored folders.'

    $scopeRoot = Join-Path -Path $testRoot -ChildPath 'scope-root'
    $scopeTsgPath = Join-Path -Path $scopeRoot -ChildPath 'TSG'
    $scopeSopPath = Join-Path -Path $scopeRoot -ChildPath 'SOP'
    $scopeOtherPath = Join-Path -Path $scopeRoot -ChildPath 'MISC'
    New-Item -ItemType Directory -Path $scopeTsgPath, $scopeSopPath, $scopeOtherPath -Force | Out-Null
    $scopeTsgFile = Join-Path -Path $scopeTsgPath -ChildPath 'scope-tsg.txt'
    $scopeSopFile = Join-Path -Path $scopeSopPath -ChildPath 'scope-sop.txt'
    $scopeOtherFile = Join-Path -Path $scopeOtherPath -ChildPath 'scope-other.txt'
    Set-Content -LiteralPath $scopeTsgFile -Value 'scopehit tsg' -NoNewline
    Set-Content -LiteralPath $scopeSopFile -Value 'scopehit sop' -NoNewline
    Set-Content -LiteralPath $scopeOtherFile -Value 'scopehit other' -NoNewline
    $scopeConfig = [PSCustomObject]@{
        Types = @('ALL', 'TSG', 'SOP', 'TEAM')
        MaxSearchResults = 10
        MaxContentScanFileSizeMB = 10
        UseRipgrep = $false
        AllowedFileExtNames = @('.txt')
        IgnoredFilenames = @()
        IgnoredFileExtNames = @()
        Ignored = @()
        LiveContentScanScope = 'Configured Types'
    }
    $configuredScopeMatches = @(SearchFiles -Root $scopeRoot -Keyword 'scopehit' -SearchContent $true -Config $scopeConfig -SelectedType 'ALL' -ScanScope 'Configured Types')
    Assert-True -Condition ($configuredScopeMatches -contains $scopeTsgFile) -Message 'Configured Types live scan should include configured TSG root.'
    Assert-True -Condition ($configuredScopeMatches -contains $scopeSopFile) -Message 'Configured Types live scan should include configured SOP root.'
    Assert-True -Condition (-not ($configuredScopeMatches -contains $scopeOtherFile)) -Message 'Configured Types live scan should not scan unrelated ALL subfolders.'
    $allScopeMatches = @(SearchFiles -Root $scopeRoot -Keyword 'scopehit' -SearchContent $true -Config $scopeConfig -SelectedType 'ALL' -ScanScope 'All')
    Assert-True -Condition ($allScopeMatches -contains $scopeOtherFile) -Message 'All live scan scope should include unrelated ALL subfolders when explicitly selected.'

    $teamCandidateRoot = Join-Path -Path $testRoot -ChildPath 'team-candidates'
    $teamCandidateData = Join-Path -Path $testRoot -ChildPath 'team-candidate-data'
    New-Item -ItemType Directory -Path $teamCandidateRoot, $teamCandidateData -Force | Out-Null
    $teamIndexedPath = Join-Path -Path $teamCandidateRoot -ChildPath 'indexed.txt'
    $teamUnindexedPath = Join-Path -Path $teamCandidateRoot -ChildPath 'unindexed.txt'
    Set-Content -LiteralPath $teamIndexedPath -Value 'teamcandidate indexed' -NoNewline
    Set-Content -LiteralPath $teamUnindexedPath -Value 'teamcandidate unindexed' -NoNewline
    $teamCandidateIndexPath = Join-Path -Path $teamCandidateData -ChildPath 'index.json'
    $teamCandidateIndex = [PSCustomObject]@{
        schemaVersion = 2
        root = $teamCandidateRoot
        createdUtc = [System.DateTime]::UtcNow.ToString('o')
        documents = @(
            [PSCustomObject]@{
                id = 1
                name = 'indexed.txt'
                path = $teamIndexedPath
                sizeInBytes = (Get-Item -LiteralPath $teamIndexedPath).Length
                lastModified = (Get-Item -LiteralPath $teamIndexedPath).LastWriteTime.ToString('o')
                lastWriteUtc = (Get-Item -LiteralPath $teamIndexedPath).LastWriteTimeUtc.ToString('o')
                tags = @()
                tagCounts = [ordered]@{}
            }
        )
        terms = [ordered]@{ indexed = @(1) }
    }
    $teamCandidateIndex | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $teamCandidateIndexPath
    $teamCandidateConfig = [PSCustomObject]@{
        MaxSearchResults = 10
        MaxContentScanFileSizeMB = 10
        UseRipgrep = $false
        AllowedFileExtNames = @('.txt')
        IgnoredFilenames = @()
        IgnoredFileExtNames = @()
        Ignored = @()
    }
    $teamCandidateMatches = @(SearchFiles -Root $teamCandidateRoot -Keyword 'teamcandidate' -SearchContent $true -Config $teamCandidateConfig -SelectedType 'TEAM' -IndexFilePath $teamCandidateIndexPath)
    Assert-True -Condition ($teamCandidateMatches -contains $teamIndexedPath) -Message 'TEAM live content scan should search indexed candidate files.'
    Assert-True -Condition (-not ($teamCandidateMatches -contains $teamUnindexedPath)) -Message 'TEAM live content scan should avoid full enumeration when an index exists.'
    $teamFallbackMatches = @(SearchFiles -Root $teamCandidateRoot -Keyword 'teamcandidate' -SearchContent $true -Config $teamCandidateConfig -SelectedType 'TEAM' -IndexFilePath (Join-Path -Path $teamCandidateData -ChildPath 'missing-index.json'))
    Assert-True -Condition ($teamFallbackMatches -contains $teamIndexedPath) -Message 'TEAM live content scan should fall back to filesystem scan when the index is missing.'
    Assert-True -Condition ($teamFallbackMatches -contains $teamUnindexedPath) -Message 'TEAM live content fallback should scan non-indexed files when the index is missing.'

    $disabledRipgrepResult = InvokeQuickSearchRipgrepSearch -Roots @($teamCandidateRoot) -Keyword 'teamcandidate' -Config ([PSCustomObject]@{ UseRipgrep = $false }) -MaxResults 10
    Assert-True -Condition ($null -eq $disabledRipgrepResult) -Message 'Ripgrep acceleration should be optional and disabled by config.'

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

    $indexManifest = Get-Content -LiteralPath $indexPath -Raw | ConvertFrom-Json
    Assert-True -Condition (3 -eq $indexManifest.schemaVersion) -Message 'Index should use sharded schemaVersion 3.'
    Assert-True -Condition (TestFileIndexShardsAvailable -IndexFilePath $indexPath) -Message 'Index shard directory should be available for schema v3 indexes.'
    Assert-True -Condition (Test-Path -LiteralPath (GetFileIndexShardRootPath -IndexFilePath $indexPath -Manifest $indexManifest) -PathType Container) -Message 'Schema v3 index should write a shard directory.'
    $indexDocuments = @(Get-TestFileIndexDocuments -Path $indexPath)
    Assert-True -Condition (2 -eq $indexDocuments.Count) -Message "Expected two indexed documents, found $($indexDocuments.Count)."
    $sampleDocument = @($indexDocuments | Where-Object { $_.name -eq 'sample.txt' })[0]
    Assert-True -Condition ($null -ne $sampleDocument) -Message 'Indexed documents should include sample.txt.'
    Assert-True -Condition ($sampleDocument.tags -contains 'alpha') -Message 'Generated tags should include alpha.'
    Assert-True -Condition (2 -eq $sampleDocument.tagCounts.alpha) -Message 'alpha tag count should be 2.'
    Assert-True -Condition (Test-TestFileIndexTermContainsDocumentId -Path $indexPath -Term 'alpha' -DocumentId $sampleDocument.id) -Message 'Inverted term index should map alpha to the sample document id.'
    Assert-True -Condition (Test-TestFileIndexTermContainsDocumentId -Path $indexPath -Term 'sample' -DocumentId $sampleDocument.id) -Message 'Inverted term index should map filename words to the sample document id.'

    $tagMatches = @(SearchFileIndex -IndexFilePath $indexPath -Keyword 'alpha')
    Assert-True -Condition ($tagMatches -contains $samplePath) -Message 'Tag search should find sample.txt.'

    $nameMatches = @(SearchFileIndex -IndexFilePath $indexPath -Keyword 'sample')
    Assert-True -Condition ($nameMatches -contains $samplePath) -Message 'Filename search should find sample.txt.'

    $partialTagMatches = @(SearchFileIndex -IndexFilePath $indexPath -Keyword 'alp')
    Assert-True -Condition ($partialTagMatches -contains $samplePath) -Message 'Partial tag search should still find sample.txt.'

    $limitedIndexMatches = @(SearchFileIndex -IndexFilePath $indexPath -Keyword 'txt' -MaxResults 1)
    Assert-True -Condition (1 -eq $limitedIndexMatches.Count) -Message 'Index search should honor MaxResults while materializing matches.'

    $cacheSearchIndexPath = Join-Path -Path $testRoot -ChildPath 'cache-search-index.json'
    $firstCacheIndex = [PSCustomObject]@{
        schemaVersion = 2
        root = $fixtureRoot
        createdUtc = [System.DateTime]::UtcNow.ToString('o')
        documents = @(
            [PSCustomObject]@{
                id = 1
                name = 'cache-first.txt'
                path = $samplePath
                sizeInBytes = 1
                lastModified = [System.DateTime]::UtcNow.ToString('o')
                lastWriteUtc = [System.DateTime]::UtcNow.ToString('o')
                tags = @('cachefirst')
                tagCounts = [ordered]@{ cachefirst = 1 }
            }
        )
        terms = [ordered]@{ cachefirst = @(1) }
    }
    $firstCacheIndex | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $cacheSearchIndexPath
    $firstCacheMatches = @(SearchFileIndex -IndexFilePath $cacheSearchIndexPath -Keyword 'cachefirst')
    Assert-True -Condition ($firstCacheMatches -contains $samplePath) -Message 'Cached index search should find the first index version.'

    $secondCacheIndex = [PSCustomObject]@{
        schemaVersion = 2
        root = $fixtureRoot
        createdUtc = [System.DateTime]::UtcNow.ToString('o')
        documents = @(
            [PSCustomObject]@{
                id = 2
                name = 'cache-second-updated.txt'
                path = $largeTextPath
                sizeInBytes = 2
                lastModified = [System.DateTime]::UtcNow.ToString('o')
                lastWriteUtc = [System.DateTime]::UtcNow.ToString('o')
                tags = @('cachesecondupdated')
                tagCounts = [ordered]@{ cachesecondupdated = 2 }
            }
        )
        terms = [ordered]@{ cachesecondupdated = @(2) }
    }
    $secondCacheIndex | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $cacheSearchIndexPath
    $staleCacheMatches = @(SearchFileIndex -IndexFilePath $cacheSearchIndexPath -Keyword 'cachefirst')
    Assert-True -Condition (0 -eq $staleCacheMatches.Count) -Message 'Index cache should invalidate after the index file changes.'
    $freshCacheMatches = @(SearchFileIndex -IndexFilePath $cacheSearchIndexPath -Keyword 'cachesecondupdated')
    Assert-True -Condition ($freshCacheMatches -contains $largeTextPath) -Message 'Index cache should return fresh data after invalidation.'

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
    $rebuiltDocuments = @(Get-TestFileIndexDocuments -Path $indexPath)
    $rebuiltSampleDocument = @($rebuiltDocuments | Where-Object { $_.name -eq 'sample.txt' })[0]
    Assert-True -Condition ($rebuiltSampleDocument.tags -contains 'cachedword') -Message 'Unchanged files should reuse cached tag metadata.'
    Assert-True -Condition (Test-TestFileIndexTermContainsDocumentId -Path $indexPath -Term 'cachedword' -DocumentId $rebuiltSampleDocument.id) -Message 'Rebuilt inverted terms should use the new document id for reused metadata.'

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
    $resumedDocuments = @(Get-TestFileIndexDocuments -Path $resumeIndexPath)
    $resumedUnchangedDocument = @($resumedDocuments | Where-Object { $_.name -eq 'resume-unchanged.txt' })[0]
    $resumedChangedDocument = @($resumedDocuments | Where-Object { $_.name -eq 'resume-changed.txt' })[0]
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