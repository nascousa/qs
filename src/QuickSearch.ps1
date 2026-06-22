<#
.SYNOPSIS
Runs the QuickSearch desktop search UI.

.DESCRIPTION
A Windows Forms utility for searching mapped drive files with content preview and integrated tag indexing.

.PARAMETER InputPath
Specifies a settings/config.json file to customize according to your needs.

.PARAMETER OutputPath
None

.INPUTS
None. You cannot pipe objects to QuickSearch.ps1.

.OUTPUTS
None. QuickSearch.ps1 does not generate pipeline output.

.EXAMPLE
PS> .\QuickSearch.ps1

#>


$SupportScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'QuickSearch.Support.ps1'
. $SupportScriptPath


Function Run()
{
    Write-Host "`n[ New Search ]`n" -ForegroundColor Cyan

    GUI

    Write-Host "`n[ Search Completed ]`n" -ForegroundColor Green
    if ($env:QS_PAUSE_ON_EXIT -eq '1') {
        Pause
    }
}

<#
.SYNOPSIS
    Randering script with a GUI
#>
Function GUI()
{
    Add-Type -assembly System.Windows.Forms

    $ConfigPath = Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath 'settings') -ChildPath 'config.json'
    $IndexFilePath = Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath 'data') -ChildPath 'index.json'
    $ProfilesDirectory = GetQuickSearchProfilesDirectory -ScriptRoot $PSScriptRoot
    $config = ReadConfig $ConfigPath
    $profileState = UseQuickSearchProfile -Config $config -ProfilesDirectory $ProfilesDirectory
    Write-Host "ConfigPath: $ConfigPath"
    Write-Host "ProfilePath: $($profileState.Path)"

    $main_form = New-Object System.Windows.Forms.Form
    $title = $config.Title
    if ([string]::IsNullOrWhiteSpace($title)) {
        $title = $config.QSTitle
    }
    if ([string]::IsNullOrWhiteSpace($title)) {
        $title = 'QuickSearch'
    }
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $projectVersion = GetQuickSearchProjectVersion -Config $config -ConfigPath $ConfigPath -RepoRoot $repoRoot
    $main_form.Text = GetQuickSearchWindowTitle -BaseTitle $title -Version $projectVersion
    $main_form.Width = $($config.Width)
    $main_form.Height = $($config.Height)
    $main_form.AutoSize = $false
    $main_form.FormBorderStyle = "FixedDialog"
    $main_form.AutoScaleMode = 'None'
    # $main_form.StartPosition = "CenterScreen"
    $main_form.MaximizeBox = $false
    $search_results = @()
    $ResultState = [PSCustomObject]@{
        AllItems = @()
        SortMode = 'NameAsc'
    }


    # --------------------------------------------------------------------------------
    # Label_DeriveLetter
    $Label_DeriveLetter = New-Object System.Windows.Forms.Label
    $Label_DeriveLetter.Text = 'Drive'
    $Label_DeriveLetter.Location = New-Object System.Drawing.Point(10, 10)
    $Label_DeriveLetter.Width = 35
    $main_form.Controls.Add($Label_DeriveLetter)

    # ComboBox_DriveLetter
    $ComboBox_DriveLetter = New-Object System.Windows.Forms.ComboBox
    $ComboBox_DriveLetter.Location = New-Object System.Drawing.Point(45, 10)
    $ComboBox_DriveLetter.Width = 40
    @("A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z") | ForEach-Object {
        [void]$ComboBox_DriveLetter.Items.Add($_)
    }
    $main_form.Controls.Add($ComboBox_DriveLetter)
    # --------------------------------------------------------------------------------


    # --------------------------------------------------------------------------------
    # Label_Type
    $Label_Type = New-Object System.Windows.Forms.Label
    $Label_Type.Text = 'Type'
    $Label_Type.Location = New-Object System.Drawing.Point(90, 10)
    $Label_Type.Width = 30
    $main_form.Controls.Add($Label_Type)

    # ComboBox_Type
    $ComboBox_Type = New-Object System.Windows.Forms.ComboBox
    $ComboBox_Type.Location = New-Object System.Drawing.Point(120, 10)
    $ComboBox_Type.Width = 70
    $main_form.Controls.Add($ComboBox_Type)
    SetQuickSearchProfileControls -Config $config -DriveComboBox $ComboBox_DriveLetter -TypeComboBox $ComboBox_Type
    # --------------------------------------------------------------------------------


    # --------------------------------------------------------------------------------
    # RadioButton_SearchMethod1
    $RadioButton_SearchMethod1 = New-Object System.Windows.Forms.RadioButton
    $RadioButton_SearchMethod1.Text = 'Filename/Tags (Quick)'
    $RadioButton_SearchMethod1.Location = New-Object System.Drawing.Point(195, 10)
    $RadioButton_SearchMethod1.Width = 145
    $RadioButton_SearchMethod1.Checked = $true
    $main_form.Controls.Add($RadioButton_SearchMethod1)
    
    # RadioButton_SearchMethod2
    $RadioButton_SearchMethod2 = New-Object System.Windows.Forms.RadioButton
    $RadioButton_SearchMethod2.Text = 'Content (Slow)'
    $RadioButton_SearchMethod2.Location = New-Object System.Drawing.Point(345, 10)
    $RadioButton_SearchMethod2.Width = 115
    $RadioButton_SearchMethod2.Checked = $false
    $main_form.Controls.Add($RadioButton_SearchMethod2)
        
    # TextBox_Keyword
    $TextBox_Keyword = New-Object System.Windows.Forms.TextBox
    $TextBox_Keyword.Location = New-Object System.Drawing.Point(670, 10)
    $TextBox_Keyword.Width = 240
    InitializeQuickSearchKeywordPlaceholder -TextBox $TextBox_Keyword -Placeholder 'keyword'
    $main_form.Controls.Add($TextBox_Keyword)

    # Label_LiveScanScope
    $Label_LiveScanScope = New-Object System.Windows.Forms.Label
    $Label_LiveScanScope.Text = 'Scope'
    $Label_LiveScanScope.Location = New-Object System.Drawing.Point(505, 10)
    $Label_LiveScanScope.Width = 40
    $main_form.Controls.Add($Label_LiveScanScope)

    # ComboBox_LiveScanScope
    $ComboBox_LiveScanScope = New-Object System.Windows.Forms.ComboBox
    $ComboBox_LiveScanScope.Location = New-Object System.Drawing.Point(545, 10)
    $ComboBox_LiveScanScope.Width = 115
    $ComboBox_LiveScanScope.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    [void]$ComboBox_LiveScanScope.Items.Add('Configured Types')
    [void]$ComboBox_LiveScanScope.Items.Add('All')
    $configuredLiveScope = [string](GetQuickSearchSearchConfigValue -Config $config -Name 'LiveContentScanScope' -DefaultValue 'Configured Types')
    if ($ComboBox_LiveScanScope.Items.Contains($configuredLiveScope)) {
        $ComboBox_LiveScanScope.SelectedItem = $configuredLiveScope
    }
    else {
        $ComboBox_LiveScanScope.SelectedItem = 'Configured Types'
    }
    $ComboBox_LiveScanScope.Enabled = $false
    $main_form.Controls.Add($ComboBox_LiveScanScope)
    
    # Button_Search
    $Button_Search = New-Object System.Windows.Forms.Button
    $Button_Search.Text = 'Search'
    $Button_Search.Location = New-Object System.Drawing.Point(920, 10)
    $Button_Search.Width = 75
    $Button_Search.Height = 20
    $main_form.Controls.Add($Button_Search)
    $main_form.AcceptButton = $Button_Search
    # --------------------------------------------------------------------------------


    # --------------------------------------------------------------------------------

    # Button_Index
    $Button_Index = New-Object System.Windows.Forms.Button
    $Button_Index.Text = 'Index'
    $Button_Index.Location = New-Object System.Drawing.Point(1005, 10)
    $Button_Index.Width = 75
    $Button_Index.Height = 20
    $main_form.Controls.Add($Button_Index)
    # --------------------------------------------------------------------------------


    # --------------------------------------------------------------------------------
    # Button_PreviewToggle
    $Button_PreviewToggle = New-Object System.Windows.Forms.Button
    $Button_PreviewToggle.Text = 'Show Preview'
    $Button_PreviewToggle.Location = New-Object System.Drawing.Point(1090, 10)
    $Button_PreviewToggle.Width = 105
    $Button_PreviewToggle.Height = 20
    $main_form.Controls.Add($Button_PreviewToggle)
    # --------------------------------------------------------------------------------


    # --------------------------------------------------------------------------------
    # Button_Settings
    $Button_Settings = New-Object System.Windows.Forms.Button
    $Button_Settings.Text = 'Settings'
    $Button_Settings.Location = New-Object System.Drawing.Point(1205, 10)
    $Button_Settings.Width = 75
    $Button_Settings.Height = 20
    $main_form.Controls.Add($Button_Settings)
    # --------------------------------------------------------------------------------


    # --------------------------------------------------------------------------------
    # Button_About
    $Button_About = New-Object System.Windows.Forms.Button
    $Button_About.Text = 'About'
    $Button_About.Location = New-Object System.Drawing.Point(1290, 10)
    $Button_About.Width = 55
    $Button_About.Height = 20
    $main_form.Controls.Add($Button_About)
    # --------------------------------------------------------------------------------


    # --------------------------------------------------------------------------------
    # Label_Status
    $Label_Status = New-Object System.Windows.Forms.Label
    $Label_Status.Text = 'Status'
    $Label_Status.Location = New-Object System.Drawing.Point($($config.Width - 152), 10)
    $Label_Status.AutoSize = $true
    $main_form.Controls.Add($Label_Status)

    # TextBox_Status
    $TextBox_Status = New-Object System.Windows.Forms.TextBox
    $TextBox_Status.Text = 'none'
    $TextBox_Status.Location = New-Object System.Drawing.Point($($config.Width - 110), 10)
    $TextBox_Status.Width = 85
    $TextBox_Status.AutoSize = $true
    $TextBox_Status.ReadOnly = $true
    $main_form.Controls.Add($TextBox_Status)
    # --------------------------------------------------------------------------------


    # --------------------------------------------------------------------------------
    # Result filter controls
    $Label_ResultFilter = New-Object System.Windows.Forms.Label
    $Label_ResultFilter.Text = 'Filter'
    $Label_ResultFilter.Visible = $false
    $main_form.Controls.Add($Label_ResultFilter)

    $TextBox_ResultFilter = New-Object System.Windows.Forms.TextBox
    $TextBox_ResultFilter.Visible = $false
    $main_form.Controls.Add($TextBox_ResultFilter)

    $Button_ClearResultFilter = New-Object System.Windows.Forms.Button
    $Button_ClearResultFilter.Text = 'Clear'
    $Button_ClearResultFilter.Visible = $false
    $main_form.Controls.Add($Button_ClearResultFilter)

    $Panel_ResultSort = New-Object System.Windows.Forms.Panel
    $Panel_ResultSort.Visible = $false
    $main_form.Controls.Add($Panel_ResultSort)

    $Label_ResultSort = New-Object System.Windows.Forms.Label
    $Label_ResultSort.Text = 'Sort'
    $Label_ResultSort.Visible = $false
    $Panel_ResultSort.Controls.Add($Label_ResultSort)

    $RadioButton_SortNameAsc = New-Object System.Windows.Forms.RadioButton
    $RadioButton_SortNameAsc.Text = 'Name A-Z'
    $RadioButton_SortNameAsc.Checked = $true
    $RadioButton_SortNameAsc.Visible = $false
    $Panel_ResultSort.Controls.Add($RadioButton_SortNameAsc)

    $RadioButton_SortNameDesc = New-Object System.Windows.Forms.RadioButton
    $RadioButton_SortNameDesc.Text = 'Name Z-A'
    $RadioButton_SortNameDesc.Visible = $false
    $Panel_ResultSort.Controls.Add($RadioButton_SortNameDesc)

    $RadioButton_SortModified = New-Object System.Windows.Forms.RadioButton
    $RadioButton_SortModified.Text = 'Modified'
    $RadioButton_SortModified.Visible = $false
    $Panel_ResultSort.Controls.Add($RadioButton_SortModified)

    $RadioButton_SortCreated = New-Object System.Windows.Forms.RadioButton
    $RadioButton_SortCreated.Text = 'Created'
    $RadioButton_SortCreated.Visible = $false
    $Panel_ResultSort.Controls.Add($RadioButton_SortCreated)

    $ResultSortButtons = @($RadioButton_SortNameAsc, $RadioButton_SortNameDesc, $RadioButton_SortModified, $RadioButton_SortCreated)
    # --------------------------------------------------------------------------------


    # --------------------------------------------------------------------------------
    # ListBox_Results
    $ListBox_Results = New-Object System.Windows.Forms.ListBox
    $ListBox_Results.Text = 'none'
    $ListBox_Results.Location = New-Object System.Drawing.Point(10, 40)
    $ListBox_Results.Size = New-Object System.Drawing.Size(565, $($config.Height - 110))
    $ListBox_Results.Width = $($config.Width / 2 - 20)
    $ListBox_Results.AutoSize = $false
    $ListBox_Results.Items.AddRange($search_results)
    $ListBox_Results.ScrollAlwaysVisible = $true
    $ListBox_Results.HorizontalScrollbar = $false
    $ListBox_Results.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
    $ListBox_Results.Items.Clear()
    $main_form.Controls.Add($ListBox_Results)

    $ResultListToolTip = New-Object System.Windows.Forms.ToolTip
    $ResultListToolTip.AutoPopDelay = 15000
    $ResultListToolTip.InitialDelay = 500
    $ResultListToolTip.ReshowDelay = 100
    $ResultHoverState = [PSCustomObject]@{ LastToolTipPath = '' }

    # RichTextBox_TargetFileContent
    $RichTextBox_TargetFileContent = New-Object System.Windows.Forms.RichTextBox
    $RichTextBox_TargetFileContent.Text = 'None'
    $RichTextBox_TargetFileContent.Location = New-Object System.Drawing.Point($($config.Width / 2), 40)
    $RichTextBox_TargetFileContent.Width = $($config.Width / 2 - 25)
    $RichTextBox_TargetFileContent.Height = $($config.Height - 115)
    $RichTextBox_TargetFileContent.AutoSize = $true
    $RichTextBox_TargetFileContent.ReadOnly = $true
    $RichTextBox_TargetFileContent.MultiLine = $true
    $RichTextBox_TargetFileContent.ScrollBars = "Vertical"
    $main_form.Controls.Add($RichTextBox_TargetFileContent)

    $WebBrowser_TargetFileContent = New-Object System.Windows.Forms.WebBrowser
    $WebBrowser_TargetFileContent.ScriptErrorsSuppressed = $true
    $WebBrowser_TargetFileContent.AllowWebBrowserDrop = $false
    $WebBrowser_TargetFileContent.IsWebBrowserContextMenuEnabled = $true
    $WebBrowser_TargetFileContent.WebBrowserShortcutsEnabled = $true
    $main_form.Controls.Add($WebBrowser_TargetFileContent)

    $TextBox_PreviewSearch = New-Object System.Windows.Forms.TextBox
    $TextBox_PreviewSearch.Visible = $false
    InitializeQuickSearchKeywordPlaceholder -TextBox $TextBox_PreviewSearch -Placeholder 'preview search'
    $main_form.Controls.Add($TextBox_PreviewSearch)

    $Button_PreviewSearch = New-Object System.Windows.Forms.Button
    $Button_PreviewSearch.Text = 'Find'
    $Button_PreviewSearch.Image = NewQuickSearchFindButtonIcon
    $Button_PreviewSearch.TextImageRelation = [System.Windows.Forms.TextImageRelation]::ImageBeforeText
    $Button_PreviewSearch.ImageAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $Button_PreviewSearch.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
    $Button_PreviewSearch.Padding = New-Object System.Windows.Forms.Padding(4, 0, 4, 0)
    $Button_PreviewSearch.Visible = $false
    $main_form.Controls.Add($Button_PreviewSearch)

    $PreviewSearchToolTip = New-Object System.Windows.Forms.ToolTip
    $PreviewSearchToolTip.SetToolTip($Button_PreviewSearch, 'Find in preview')
    $PreviewSearchToolTip.SetToolTip($TextBox_PreviewSearch, 'Search preview')
    $PreviewHost = NewQuickSearchPreviewHost -TextBox $RichTextBox_TargetFileContent -Browser $WebBrowser_TargetFileContent -SearchTextBox $TextBox_PreviewSearch -SearchButton $Button_PreviewSearch
    $PreviewState = [PSCustomObject]@{
        Expanded = $false
        FilePath = ''
        Content = ''
        ActiveKeyword = ''
    }
    $SearchState = [PSCustomObject]@{
        Keyword = ''
        ContentSearch = $false
    }
    $updateLiveScanScopeState = {
        $ComboBox_LiveScanScope.Enabled = $RadioButton_SearchMethod2.Checked
    }
    $RadioButton_SearchMethod1.Add_CheckedChanged($updateLiveScanScopeState)
    $RadioButton_SearchMethod2.Add_CheckedChanged($updateLiveScanScopeState)
    & $updateLiveScanScopeState
    SetQuickSearchPreviewPanelState -Form $main_form -ResultsListBox $ListBox_Results -PreviewHost $PreviewHost -PreviewButton $Button_PreviewToggle -Expanded $PreviewState.Expanded -FilterLabel $Label_ResultFilter -FilterTextBox $TextBox_ResultFilter -FilterButton $Button_ClearResultFilter -SortPanel $Panel_ResultSort -SortLabel $Label_ResultSort -SortButtons $ResultSortButtons
    # --------------------------------------------------------------------------------


    # --------------------------------------------------------------------------------
    # TextBox_TargetFilePath
    $TextBox_TargetFilePath = New-Object System.Windows.Forms.TextBox
    $TextBox_TargetFilePath.Text = 'Double click on the filename above to open it!'
    $TextBox_TargetFilePath.Location = New-Object System.Drawing.Point(10, $($config.Height - 70))
    $TextBox_TargetFilePath.Width = $($config.Width - 100)
    $TextBox_TargetFilePath.AutoSize = $false
    $TextBox_TargetFilePath.ReadOnly = $true
    $main_form.Controls.Add($TextBox_TargetFilePath)

    # Button_OpenTargetFile
    $Button_OpenTargetFile = New-Object System.Windows.Forms.Button
    $Button_OpenTargetFile.Text = 'Open'
    $Button_OpenTargetFile.Location = New-Object System.Drawing.Point($($config.Width - 85), $($config.Height - 70))
    $Button_OpenTargetFile.Width = 60
    $Button_OpenTargetFile.Height = 20
    $main_form.Controls.Add($Button_OpenTargetFile)
    # --------------------------------------------------------------------------------


    $applyResultFilter = {
        $sortedItems = @(SortQuickSearchResultItems -Items $ResultState.AllItems -SortMode $ResultState.SortMode)
        $filteredItems = @(SelectQuickSearchResultItems -Items $sortedItems -FilterText $TextBox_ResultFilter.Text)

        $ListBox_Results.BeginUpdate()
        try {
            $ListBox_Results.Items.Clear()
            if ($filteredItems.Count -gt 0) {
                $ListBox_Results.Items.AddRange([object[]]$filteredItems)
            }
            elseif (@($ResultState.AllItems).Count -gt 0) {
                [void]$ListBox_Results.Items.Add('No results match the filter.')
            }
        }
        finally {
            $ListBox_Results.EndUpdate()
        }

        if (@($ResultState.AllItems).Count -gt 0) {
            if ([string]::IsNullOrWhiteSpace($TextBox_ResultFilter.Text)) {
                $TextBox_Status.Text = "Results: $(@($ResultState.AllItems).Count)"
            }
            else {
                $TextBox_Status.Text = "Filtered: $($filteredItems.Count)/$(@($ResultState.AllItems).Count)"
            }
        }
    }

    $TextBox_ResultFilter.Add_TextChanged({ & $applyResultFilter })
    $Button_ClearResultFilter.Add_Click({ $TextBox_ResultFilter.Clear() })
    $updateResultSortMode = {
        if ($RadioButton_SortNameDesc.Checked) { $ResultState.SortMode = 'NameDesc' }
        elseif ($RadioButton_SortModified.Checked) { $ResultState.SortMode = 'Modified' }
        elseif ($RadioButton_SortCreated.Checked) { $ResultState.SortMode = 'Created' }
        else { $ResultState.SortMode = 'NameAsc' }

        & $applyResultFilter
    }
    foreach ($sortButton in $ResultSortButtons) {
        $sortButton.Add_CheckedChanged($updateResultSortMode)
    }


    # --------------------------------------------------------------------------------
    # Button_Search Add_Click event handler
    # --------------------------------------------------------------------------------
    $Button_Search.Add_Click({
        $ResultState.AllItems = @()
        $ListBox_Results.Items.Clear()
        $TextBox_ResultFilter.Clear()
        $TextBox_TargetFilePath.Text = "Searching..."
        $TextBox_Status.Text = "Searching..."
        $search_results = @()
        $SearchType = 0
        $SearchMethod = 0

        $keyword = GetQuickSearchKeywordText -TextBox $TextBox_Keyword
        if ([string]::IsNullOrWhiteSpace($keyword)) {
            [void]$ListBox_Results.Items.Add('Enter a keyword first.')
            $TextBox_Status.Text = 'No keyword'
            $TextBox_TargetFilePath.Text = 'No keyword'
            $SearchState.Keyword = ''
            $SearchState.ContentSearch = $false
            return
        }

        $SearchState.Keyword = $keyword

        $selectedType = $ComboBox_Type.Text
        if ($selectedType -eq "TEAM") {
            $teamPathTemplate = GetTeamPathTemplate $config
            $path = ResolveConfiguredPath -DriveLetter $ComboBox_DriveLetter.Text -PathTemplate $teamPathTemplate
            $SearchType = 1 # TEAM
        }
        else {
            $basePath = ResolveConfiguredPath -DriveLetter $ComboBox_DriveLetter.Text -PathTemplate (GetDocPathTemplate $config)
            if ($selectedType -eq "ALL") {
                $path = $basePath
            }
            else {
                $path = Join-Path -Path $basePath -ChildPath $selectedType
            }
            $SearchType = 0 # TSG/SOP/CASE
        }

        Write-Host "$path"

        if($RadioButton_SearchMethod1.Checked){
            $SearchMethod = 0
        }else{
            $SearchMethod = 1
        }
        $SearchState.ContentSearch = (1 -eq $SearchMethod)

        if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path)) {
            [void]$ListBox_Results.Items.Add("Path not found: $path")
            $TextBox_Status.Text = 'Path not found'
            $TextBox_TargetFilePath.Text = 'Path not found'
            return
        }

        $useIndex = (1 -eq $SearchType -and 0 -eq $SearchMethod)
        $searchContent = (1 -eq $SearchMethod)
        $IndexFile = $IndexFilePath

        Write-Host "SearchType: $SearchType`n" -ForegroundColor Cyan
        Write-Host "SearchMethod: $SearchMethod`n" -ForegroundColor Cyan

        if ($useIndex) {
            Write-Host "IndexFile: $IndexFile"
            if (-not (Test-Path -LiteralPath $IndexFile)) {
                [void]$ListBox_Results.Items.Add('Team index not found. Open Index and run Re-Index Team Folder first.')
                $TextBox_Status.Text = 'Index not found'
                $TextBox_TargetFilePath.Text = 'Index not found'
                return
            }
        }

        $searchMessage = 'Searching filenames, please wait...'
        if ($useIndex) {
            $searchMessage = 'Searching TEAM index, please wait...'
        }
        elseif ($searchContent) {
            $searchMessage = 'Scanning file content live, this may take a while...'
        }

        $Button_Search.Enabled = $false
        try {
            $searchResult = InvokeQuickSearchWithProcessingDialog -Owner $main_form -Title 'Search' -Message $searchMessage -Root $path -Keyword $keyword -SearchContent $searchContent -UseIndex $useIndex -IndexFilePath $IndexFile -Config $config -SelectedType $selectedType -ScanScope $ComboBox_LiveScanScope.Text
            if ($searchResult.Canceled) {
                [void]$ListBox_Results.Items.Add('Search canceled.')
                $TextBox_Status.Text = 'Canceled'
                $TextBox_TargetFilePath.Text = 'Canceled'
                return
            }
            if ($searchResult.Failed) {
                [void]$ListBox_Results.Items.Add("Search failed: $($searchResult.ErrorMessage)")
                $TextBox_Status.Text = 'Failed'
                $TextBox_TargetFilePath.Text = 'Failed'
                return
            }
            $search_results = @($searchResult.Results)
        }
        finally {
            $Button_Search.Enabled = $true
        }

        $ListBox_Results.BeginUpdate()
        try {
            if(@($search_results).Count -gt 0){
                $resultItems = [object[]]@($search_results | ForEach-Object { NewQuickSearchResultItem -Path ([string]$_) })
                $ResultState.AllItems = @($resultItems)
                Write-Host "Search Results: $($resultItems.Count)`n" -ForegroundColor Green
            }else{
                [void]$ListBox_Results.Items.Add('Keyword cannot be found!')
                Write-Host "Search Results: none!`n" -ForegroundColor Red
            }
        }
        finally {
            $ListBox_Results.EndUpdate()
        }

        if (@($ResultState.AllItems).Count -gt 0) {
            & $applyResultFilter
        }

        $TextBox_Status.Text = "Completed"
        $TextBox_TargetFilePath.Text = "Completed"

    })



    # --------------------------------------------------------------------------------
    # Button_Index Add_Click event handler
    # --------------------------------------------------------------------------------
    $Button_Index.Add_Click({
        ShowIndexSettings -Owner $main_form -Config $config -ConfigPath $ConfigPath -IndexFilePath $IndexFilePath -DriveLetter $ComboBox_DriveLetter.Text -ProfilesDirectory $ProfilesDirectory
    })


    # --------------------------------------------------------------------------------
    # Button_Settings Add_Click event handler
    # --------------------------------------------------------------------------------
    $Button_Settings.Add_Click({
        $profileResult = ShowQuickSearchProfileSettings -Owner $main_form -Config $config -ConfigPath $ConfigPath -ProfilesDirectory $ProfilesDirectory
        if ($null -ne $profileResult -and $profileResult.Applied) {
            SetQuickSearchProfileControls -Config $config -DriveComboBox $ComboBox_DriveLetter -TypeComboBox $ComboBox_Type
            $ResultState.AllItems = @()
            $TextBox_ResultFilter.Clear()
            $ListBox_Results.Items.Clear()
            $TextBox_Status.Text = 'Profile applied'
            $TextBox_TargetFilePath.Text = "Profile: $($profileResult.Name)"
        }
    })


    # --------------------------------------------------------------------------------
    # Button_About Add_Click event handler
    # --------------------------------------------------------------------------------
    $Button_About.Add_Click({
        ShowQuickSearchAbout -Owner $main_form -Config $config
    })


    # --------------------------------------------------------------------------------
    # Button_PreviewToggle Add_Click event handler
    # --------------------------------------------------------------------------------
    $Button_PreviewToggle.Add_Click({
        $PreviewState.Expanded = -not $PreviewState.Expanded
        SetQuickSearchPreviewPanelState -Form $main_form -ResultsListBox $ListBox_Results -PreviewHost $PreviewHost -PreviewButton $Button_PreviewToggle -Expanded $PreviewState.Expanded -FilterLabel $Label_ResultFilter -FilterTextBox $TextBox_ResultFilter -FilterButton $Button_ClearResultFilter -SortPanel $Panel_ResultSort -SortLabel $Label_ResultSort -SortButtons $ResultSortButtons
    })

    $searchPreviewContent = {
        if ([string]::IsNullOrWhiteSpace($PreviewState.FilePath) -or [string]::IsNullOrEmpty($PreviewState.Content)) {
            $TextBox_Status.Text = 'No preview'
            return
        }

        $previewKeyword = GetQuickSearchKeywordText -TextBox $TextBox_PreviewSearch
        if ([string]::IsNullOrWhiteSpace($previewKeyword)) {
            $previewKeyword = $SearchState.Keyword
        }

        $PreviewState.ActiveKeyword = $previewKeyword
        $highlightPreviewKeyword = -not [string]::IsNullOrWhiteSpace($previewKeyword)
        SetQuickSearchPreviewContent -PreviewHost $PreviewHost -FilePath $PreviewState.FilePath -Content $PreviewState.Content -Keyword $previewKeyword -HighlightKeyword:$highlightPreviewKeyword
        if ($highlightPreviewKeyword) {
            $TextBox_Status.Text = 'Preview searched'
        }
        else {
            $TextBox_Status.Text = 'Preview loaded'
        }
    }
    $Button_PreviewSearch.Add_Click($searchPreviewContent)
    $TextBox_PreviewSearch.Add_KeyDown({
        param($sender, $eventArgs)
        if ($eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
            & $searchPreviewContent
            $eventArgs.SuppressKeyPress = $true
        }
    })
    

    # --------------------------------------------------------------------------------
    # Button_OpenTargetFile Add_Click event handler
    # --------------------------------------------------------------------------------
    $Button_OpenTargetFile.Add_Click({
        $SelectedItemPath = GetQuickSearchResultItemPath -Item $ListBox_Results.SelectedItem

        if(TestExistingLiteralPath $SelectedItemPath){
            Start-Process -FilePath $SelectedItemPath
            Write-Host $SelectedItemPath
        }
    })


    # --------------------------------------------------------------------------------
    # ListBox_Results Add_Click event handler
    # --------------------------------------------------------------------------------
    $ListBox_Results.Add_Click({
        $SelectedItemPath = GetQuickSearchResultItemPath -Item $ListBox_Results.SelectedItem
        if(TestExistingLiteralPath $SelectedItemPath)
        {
            $TextBox_TargetFilePath.Text = $SelectedItemPath
            $TargetFileContent = Get-Content -LiteralPath $TextBox_TargetFilePath.Text -Raw
            $PreviewState.FilePath = $SelectedItemPath
            $PreviewState.Content = $TargetFileContent
            $PreviewState.ActiveKeyword = $SearchState.Keyword
            $TextBox_PreviewSearch.Text = ''
            SetQuickSearchKeywordPlaceholder -TextBox $TextBox_PreviewSearch
            $PreviewState.Expanded = $true
            SetQuickSearchPreviewPanelState -Form $main_form -ResultsListBox $ListBox_Results -PreviewHost $PreviewHost -PreviewButton $Button_PreviewToggle -Expanded $PreviewState.Expanded -FilterLabel $Label_ResultFilter -FilterTextBox $TextBox_ResultFilter -FilterButton $Button_ClearResultFilter -SortPanel $Panel_ResultSort -SortLabel $Label_ResultSort -SortButtons $ResultSortButtons
            $highlightPreviewKeyword = -not [string]::IsNullOrWhiteSpace($SearchState.Keyword)
            SetQuickSearchPreviewContent -PreviewHost $PreviewHost -FilePath $TextBox_TargetFilePath.Text -Content $TargetFileContent -Keyword $SearchState.Keyword -HighlightKeyword:$highlightPreviewKeyword
        }
    })


    # --------------------------------------------------------------------------------
    # ListBox_Results Add_DoubleClick event handler
    # --------------------------------------------------------------------------------
    $ListBox_Results.Add_DoubleClick({
        $SelectedItemPath = GetQuickSearchResultItemPath -Item $ListBox_Results.SelectedItem

        if(TestExistingLiteralPath $SelectedItemPath){
            Start-Process -FilePath $SelectedItemPath
            Write-Host $SelectedItemPath
        }
    })


    # --------------------------------------------------------------------------------
    # ListBox_Results Add_MouseMove event handler
    # --------------------------------------------------------------------------------
    $ListBox_Results.Add_MouseMove({
        param(
            [System.Object]$listBoxSender,
            [System.Windows.Forms.MouseEventArgs]$eventArgs
        )

        $hoverIndex = $listBoxSender.IndexFromPoint($eventArgs.Location)
        if ($hoverIndex -lt 0 -or $hoverIndex -ge $listBoxSender.Items.Count) {
            if (-not [string]::IsNullOrEmpty($ResultHoverState.LastToolTipPath)) {
                $ResultListToolTip.SetToolTip($ListBox_Results, '')
                $ResultHoverState.LastToolTipPath = ''
            }
            return
        }

        $hoverPath = GetQuickSearchResultItemPath -Item $listBoxSender.Items[$hoverIndex]
        if ((TestExistingLiteralPath $hoverPath) -and $hoverPath -ne $ResultHoverState.LastToolTipPath) {
            $ResultListToolTip.SetToolTip($ListBox_Results, $hoverPath)
            $ResultHoverState.LastToolTipPath = $hoverPath
        }
        elseif (-not (TestExistingLiteralPath $hoverPath) -and -not [string]::IsNullOrEmpty($ResultHoverState.LastToolTipPath)) {
            $ResultListToolTip.SetToolTip($ListBox_Results, '')
            $ResultHoverState.LastToolTipPath = ''
        }
    })

    $ListBox_Results.Add_MouseLeave({
        $ResultListToolTip.SetToolTip($ListBox_Results, '')
        $ResultHoverState.LastToolTipPath = ''
    })


    # --------------------------------------------------------------------------------
    # ListBox_Results Add_DrawItem event handler
    # --------------------------------------------------------------------------------
    $ListBox_Results.Add_DrawItem({
        param(
            [System.Object]$listBoxSender,
            [System.Windows.Forms.DrawItemEventArgs]$e
        )

        if($e.Index -lt 0){
            return
        }

        if($e.Index %2 -eq 0){
            $e.Graphics.FillRectangle([System.Drawing.Brushes]::LightGray, $e.Bounds)
        }else{
            $e.Graphics.FillRectangle([System.Drawing.Brushes]::White, $e.Bounds)
        }

        $font = [System.Drawing.SystemFonts]::DefaultFont
        $drawBounds = New-Object System.Drawing.Rectangle(($e.Bounds.X + 2), $e.Bounds.Y, ([Math]::Max(1, $e.Bounds.Width - 4)), $e.Bounds.Height)
        $ItemText = GetQuickSearchResultItemDisplayTextForWidth -Item $ListBox_Results.Items[$e.Index] -Graphics $e.Graphics -Font $font -MaxWidth $drawBounds.Width
        
        if($e.State -band [System.Windows.Forms.DrawItemState]::Selected){
            $font = [System.Drawing.Font]::new($font, [System.Drawing.FontStyle]::Bold)
            $ItemText = GetQuickSearchResultItemDisplayTextForWidth -Item $ListBox_Results.Items[$e.Index] -Graphics $e.Graphics -Font $font -MaxWidth $drawBounds.Width
            DrawQuickSearchHighlightedListText -Graphics $e.Graphics -Bounds $drawBounds -Text $ItemText -Keyword $SearchState.Keyword -Font $font -TextBrush ([System.Drawing.Brushes]::DarkBlue)
        }else{
            DrawQuickSearchHighlightedListText -Graphics $e.Graphics -Bounds $drawBounds -Text $ItemText -Keyword $SearchState.Keyword -Font $ListBox_Results.Font -TextBrush ([System.Drawing.Brushes]::Black)
        }
    })

    
    # --------------------------------------------------------------------------------
    # main_form Add_FormClosing event handler
    # --------------------------------------------------------------------------------
    $main_form.Add_FormClosing({
        if($_.CloseReason -eq 'UserClosing'){
            $main_form.Close()
        }
    })
    # --------------------------------------------------------------------------------

    
    # Display window
    $main_form.ShowDialog() | Out-Null
}

if ($env:QS_SKIP_AUTORUN -ne '1') {
    Run
}
