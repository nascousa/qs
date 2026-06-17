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


$IndexScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'QuickSearch.Index.ps1'
. $IndexScriptPath
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

Function ShowTagManagerSettings {
    param(
        [System.Windows.Forms.Form]$Owner,
        [object]$Config,
        [string]$ConfigPath,
        [string]$IndexFilePath,
        [string]$DriveLetter
    )

    $settingsForm = New-Object System.Windows.Forms.Form
    $settingsForm.Text = 'TagManager Settings'
    $settingsForm.ClientSize = New-Object System.Drawing.Size(660, 390)
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

    $Label_TeamPath = New-Object System.Windows.Forms.Label
    $Label_TeamPath.Text = 'TEAM path template'
    $Label_TeamPath.Location = New-Object System.Drawing.Point($labelLeft, 20)
    $Label_TeamPath.Width = $labelWidth
    $settingsForm.Controls.Add($Label_TeamPath)

    $TextBox_TeamPath = New-Object System.Windows.Forms.TextBox
    $TextBox_TeamPath.Text = GetTeamPathTemplate $Config
    $TextBox_TeamPath.Location = New-Object System.Drawing.Point($inputLeft, 18)
    $TextBox_TeamPath.Width = $inputWidth
    $settingsForm.Controls.Add($TextBox_TeamPath)

    $Label_ResolvedPath = New-Object System.Windows.Forms.Label
    $Label_ResolvedPath.Text = 'Resolved path'
    $Label_ResolvedPath.Location = New-Object System.Drawing.Point($labelLeft, 55)
    $Label_ResolvedPath.Width = $labelWidth
    $settingsForm.Controls.Add($Label_ResolvedPath)

    $TextBox_ResolvedPath = New-Object System.Windows.Forms.TextBox
    $TextBox_ResolvedPath.Text = ResolveConfiguredPath -DriveLetter $DriveLetter -PathTemplate $TextBox_TeamPath.Text
    $TextBox_ResolvedPath.Location = New-Object System.Drawing.Point($inputLeft, 53)
    $TextBox_ResolvedPath.Width = $inputWidth
    $TextBox_ResolvedPath.ReadOnly = $true
    $settingsForm.Controls.Add($TextBox_ResolvedPath)

    $Label_TagCount = New-Object System.Windows.Forms.Label
    $Label_TagCount.Text = 'Top words per file'
    $Label_TagCount.Location = New-Object System.Drawing.Point($labelLeft, 90)
    $Label_TagCount.Width = $labelWidth
    $settingsForm.Controls.Add($Label_TagCount)

    $NumericUpDown_TagCount = New-Object System.Windows.Forms.NumericUpDown
    $NumericUpDown_TagCount.Location = New-Object System.Drawing.Point($inputLeft, 88)
    $NumericUpDown_TagCount.Width = 80
    $NumericUpDown_TagCount.Minimum = 1
    $NumericUpDown_TagCount.Maximum = 100
    $NumericUpDown_TagCount.Value = [Math]::Min(100, [Math]::Max(1, [int]$Config.TagCount))
    $settingsForm.Controls.Add($NumericUpDown_TagCount)

    $Label_IgnoredFilenames = New-Object System.Windows.Forms.Label
    $Label_IgnoredFilenames.Text = 'Ignored filenames'
    $Label_IgnoredFilenames.Location = New-Object System.Drawing.Point($labelLeft, 125)
    $Label_IgnoredFilenames.Width = $labelWidth
    $settingsForm.Controls.Add($Label_IgnoredFilenames)

    $TextBox_IgnoredFilenames = New-Object System.Windows.Forms.TextBox
    $TextBox_IgnoredFilenames.Text = ConvertArrayToDelimitedText @($Config.IgnoredFilenames)
    $TextBox_IgnoredFilenames.Location = New-Object System.Drawing.Point($inputLeft, 123)
    $TextBox_IgnoredFilenames.Width = $inputWidth
    $settingsForm.Controls.Add($TextBox_IgnoredFilenames)

    $Label_IgnoredExtensions = New-Object System.Windows.Forms.Label
    $Label_IgnoredExtensions.Text = 'Ignored extensions'
    $Label_IgnoredExtensions.Location = New-Object System.Drawing.Point($labelLeft, 160)
    $Label_IgnoredExtensions.Width = $labelWidth
    $settingsForm.Controls.Add($Label_IgnoredExtensions)

    $TextBox_IgnoredExtensions = New-Object System.Windows.Forms.TextBox
    $TextBox_IgnoredExtensions.Text = ConvertArrayToDelimitedText @($Config.IgnoredFileExtNames)
    $TextBox_IgnoredExtensions.Location = New-Object System.Drawing.Point($inputLeft, 158)
    $TextBox_IgnoredExtensions.Width = $inputWidth
    $settingsForm.Controls.Add($TextBox_IgnoredExtensions)

    $Label_AllowedExtensions = New-Object System.Windows.Forms.Label
    $Label_AllowedExtensions.Text = 'Allowed extensions'
    $Label_AllowedExtensions.Location = New-Object System.Drawing.Point($labelLeft, 195)
    $Label_AllowedExtensions.Width = $labelWidth
    $settingsForm.Controls.Add($Label_AllowedExtensions)

    $TextBox_AllowedExtensions = New-Object System.Windows.Forms.TextBox
    $TextBox_AllowedExtensions.Text = ConvertArrayToDelimitedText @($Config.AllowedFileExtNames)
    $TextBox_AllowedExtensions.Location = New-Object System.Drawing.Point($inputLeft, 193)
    $TextBox_AllowedExtensions.Width = $inputWidth
    $settingsForm.Controls.Add($TextBox_AllowedExtensions)

    $Label_IgnoredFolders = New-Object System.Windows.Forms.Label
    $Label_IgnoredFolders.Text = 'Ignored folders'
    $Label_IgnoredFolders.Location = New-Object System.Drawing.Point($labelLeft, 230)
    $Label_IgnoredFolders.Width = $labelWidth
    $settingsForm.Controls.Add($Label_IgnoredFolders)

    $TextBox_IgnoredFolders = New-Object System.Windows.Forms.TextBox
    $TextBox_IgnoredFolders.Text = ConvertArrayToDelimitedText @($Config.Ignored)
    $TextBox_IgnoredFolders.Location = New-Object System.Drawing.Point($inputLeft, 228)
    $TextBox_IgnoredFolders.Width = $inputWidth
    $settingsForm.Controls.Add($TextBox_IgnoredFolders)

    $Label_Status = New-Object System.Windows.Forms.Label
    $Label_Status.Text = 'Ready'
    $Label_Status.Location = New-Object System.Drawing.Point($labelLeft, 270)
    $Label_Status.Width = 620
    $settingsForm.Controls.Add($Label_Status)

    $Button_Save = New-Object System.Windows.Forms.Button
    $Button_Save.Text = 'Save'
    $Button_Save.Location = New-Object System.Drawing.Point(260, 325)
    $Button_Save.Width = 80
    $settingsForm.Controls.Add($Button_Save)

    $Button_RebuildIndex = New-Object System.Windows.Forms.Button
    $Button_RebuildIndex.Text = 'Rebuild Index'
    $Button_RebuildIndex.Location = New-Object System.Drawing.Point(350, 325)
    $Button_RebuildIndex.Width = 110
    $settingsForm.Controls.Add($Button_RebuildIndex)

    $Button_Close = New-Object System.Windows.Forms.Button
    $Button_Close.Text = 'Close'
    $Button_Close.Location = New-Object System.Drawing.Point(470, 325)
    $Button_Close.Width = 80
    $settingsForm.Controls.Add($Button_Close)

    $saveSettings = {
        SetConfigValue -Config $Config -Name 'TeamPath' -Value $TextBox_TeamPath.Text.Trim()
        SetConfigValue -Config $Config -Name 'TagCount' -Value ([int]$NumericUpDown_TagCount.Value)
        SetConfigValue -Config $Config -Name 'IgnoredFilenames' -Value @(ConvertDelimitedTextToArray $TextBox_IgnoredFilenames.Text)
        SetConfigValue -Config $Config -Name 'AllowedFileExtNames' -Value @(ConvertDelimitedTextToArray $TextBox_AllowedExtensions.Text)
        SetConfigValue -Config $Config -Name 'IgnoredFileExtNames' -Value @(ConvertDelimitedTextToArray $TextBox_IgnoredExtensions.Text)
        SetConfigValue -Config $Config -Name 'Ignored' -Value @(ConvertDelimitedTextToArray $TextBox_IgnoredFolders.Text)
        SaveConfig -Config $Config -ConfigPath $ConfigPath
        $TextBox_ResolvedPath.Text = ResolveConfiguredPath -DriveLetter $DriveLetter -PathTemplate $Config.TeamPath
        $Label_Status.Text = "Saved to $ConfigPath"
    }

    $TextBox_TeamPath.Add_TextChanged({
        $TextBox_ResolvedPath.Text = ResolveConfiguredPath -DriveLetter $DriveLetter -PathTemplate $TextBox_TeamPath.Text
    })

    $Button_Save.Add_Click($saveSettings)

    $Button_RebuildIndex.Add_Click({
        & $saveSettings
        $teamRoot = ResolveConfiguredPath -DriveLetter $DriveLetter -PathTemplate $Config.TeamPath
        if ([string]::IsNullOrWhiteSpace($teamRoot) -or -not (Test-Path -LiteralPath $teamRoot)) {
            $Label_Status.Text = "TEAM path not found: $teamRoot"
            [System.Windows.Forms.MessageBox]::Show("TEAM path cannot be found: $teamRoot", 'Path Not Found') | Out-Null
            return
        }

        $Label_Status.Text = 'Rebuilding index...'
        $Button_Save.Enabled = $false
        $Button_RebuildIndex.Enabled = $false
        try {
            $created = InvokeFileIndexWithProcessingDialog -Owner $settingsForm -Title 'Rebuilding Index' -Message 'Indexing in progress, please wait...' -Root $teamRoot -Config $Config -IndexFilePath $IndexFilePath
        }
        finally {
            $Button_Save.Enabled = $true
            $Button_RebuildIndex.Enabled = $true
        }
        if ($created) {
            $Label_Status.Text = "Index rebuilt: $IndexFilePath"
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
