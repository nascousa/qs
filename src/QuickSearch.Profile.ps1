<#
.SYNOPSIS
Handles selectable QuickSearch runtime profiles.
#>

Function GetQuickSearchDefaultProfileName {
    return 'default.profile.json'
}


Function GetQuickSearchProfilesDirectory {
    param(
        [string]$ScriptRoot = $PSScriptRoot
    )

    return (Join-Path -Path $ScriptRoot -ChildPath 'profiles')
}


Function GetQuickSearchProfilePropertyValue {
    param(
        [object]$Source,
        [string]$Name
    )

    if ($null -eq $Source) { return $null }
    $property = $Source.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}


Function SetQuickSearchProfileObjectValue {
    param(
        [object]$Target,
        [string]$Name,
        [object]$Value
    )

    $property = $Target.PSObject.Properties[$Name]
    if ($null -ne $property) {
        $property.Value = $Value
    }
    else {
        Add-Member -InputObject $Target -NotePropertyName $Name -NotePropertyValue $Value -Force
    }
}


Function GetQuickSearchProfileFiles {
    param(
        [string]$ProfilesDirectory
    )

    if ([string]::IsNullOrWhiteSpace($ProfilesDirectory)) {
        $ProfilesDirectory = GetQuickSearchProfilesDirectory
    }
    if (-not (Test-Path -LiteralPath $ProfilesDirectory -PathType Container)) {
        return @()
    }

    $profileFiles = @(Get-ChildItem -LiteralPath $ProfilesDirectory -File -Filter '*.profile.json' -ErrorAction SilentlyContinue | Sort-Object Name)
    $legacyProfilePath = Join-Path -Path $ProfilesDirectory -ChildPath 'profile.json'
    if (Test-Path -LiteralPath $legacyProfilePath -PathType Leaf) {
        $profileFiles += @(Get-Item -LiteralPath $legacyProfilePath)
    }

    return @($profileFiles)
}


Function GetQuickSearchSelectedProfileName {
    param(
        [object]$Config
    )

    foreach ($propertyName in @('ProfileName', 'SelectedProfileName', 'ProfilePath')) {
        $value = GetQuickSearchProfilePropertyValue -Source $Config -Name $propertyName
        if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
            $fileName = [System.IO.Path]::GetFileName(([string]$value).Trim())
            if (-not [string]::IsNullOrWhiteSpace($fileName)) {
                return $fileName
            }
        }
    }

    return (GetQuickSearchDefaultProfileName)
}


Function ResolveQuickSearchProfilePath {
    param(
        [string]$ProfilesDirectory,
        [string]$ProfileName
    )

    if ([string]::IsNullOrWhiteSpace($ProfilesDirectory)) {
        $ProfilesDirectory = GetQuickSearchProfilesDirectory
    }
    if ([string]::IsNullOrWhiteSpace($ProfileName)) {
        $ProfileName = GetQuickSearchDefaultProfileName
    }

    $profileFileName = [System.IO.Path]::GetFileName($ProfileName.Trim())
    $candidatePath = Join-Path -Path $ProfilesDirectory -ChildPath $profileFileName
    if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
        return $candidatePath
    }

    $defaultPath = Join-Path -Path $ProfilesDirectory -ChildPath (GetQuickSearchDefaultProfileName)
    if (Test-Path -LiteralPath $defaultPath -PathType Leaf) {
        return $defaultPath
    }

    $legacyPath = Join-Path -Path $ProfilesDirectory -ChildPath 'profile.json'
    if (Test-Path -LiteralPath $legacyPath -PathType Leaf) {
        return $legacyPath
    }

    $firstProfile = @(GetQuickSearchProfileFiles -ProfilesDirectory $ProfilesDirectory | Select-Object -First 1)
    if ($firstProfile.Count -gt 0) {
        return $firstProfile[0].FullName
    }

    return $candidatePath
}


Function ReadQuickSearchProfile {
    param(
        [string]$ProfilePath
    )

    if (-not (Test-Path -LiteralPath $ProfilePath -PathType Leaf)) {
        throw "QS profile not found: $ProfilePath"
    }

    return (Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json)
}


Function CopyQuickSearchProfileConfigValue {
    param(
        [object]$Profile,
        [string]$ProfileName,
        [object]$Config,
        [string]$ConfigName
    )

    $value = GetQuickSearchProfilePropertyValue -Source $Profile -Name $ProfileName
    if ($null -eq $value) { return }
    if ($value -is [string] -and [string]::IsNullOrWhiteSpace($value)) { return }

    SetQuickSearchProfileObjectValue -Target $Config -Name $ConfigName -Value $value
}


Function ApplyQuickSearchProfile {
    param(
        [object]$Config,
        [object]$Profile,
        [string]$ProfileName
    )

    CopyQuickSearchProfileConfigValue -Profile $Profile -ProfileName 'DriveLetter' -Config $Config -ConfigName 'DriveLetter'
    CopyQuickSearchProfileConfigValue -Profile $Profile -ProfileName 'DocPath' -Config $Config -ConfigName 'Path'
    CopyQuickSearchProfileConfigValue -Profile $Profile -ProfileName 'Path' -Config $Config -ConfigName 'Path'
    foreach ($name in @('TeamPath', 'Types', 'Ignored', 'IgnoredFilenames', 'AllowedFileExtNames', 'IgnoredFileExtNames', 'TagCount', 'MaxTagFileSizeMB', 'MaxSearchResults', 'MaxContentScanFileSizeMB', 'LiveContentScanScope', 'UseRipgrep', 'UseRipgrepForLiveContentScan')) {
        CopyQuickSearchProfileConfigValue -Profile $Profile -ProfileName $name -Config $Config -ConfigName $name
    }
    if (-not [string]::IsNullOrWhiteSpace($ProfileName)) {
        SetQuickSearchProfileObjectValue -Target $Config -Name 'ProfileName' -Value ([System.IO.Path]::GetFileName($ProfileName))
    }

    return $Config
}


Function UseQuickSearchProfile {
    param(
        [object]$Config,
        [string]$ProfilesDirectory,
        [string]$ProfileName
    )

    if ([string]::IsNullOrWhiteSpace($ProfileName)) {
        $ProfileName = GetQuickSearchSelectedProfileName -Config $Config
    }

    $profilePath = ResolveQuickSearchProfilePath -ProfilesDirectory $ProfilesDirectory -ProfileName $ProfileName
    $profileApplied = $false
    $resolvedName = [System.IO.Path]::GetFileName($profilePath)
    $profile = $null
    if (Test-Path -LiteralPath $profilePath -PathType Leaf) {
        $profile = ReadQuickSearchProfile -ProfilePath $profilePath
        ApplyQuickSearchProfile -Config $Config -Profile $profile -ProfileName $resolvedName | Out-Null
        $profileApplied = $true
    }

    return [PSCustomObject]@{
        Name = $resolvedName
        Path = $profilePath
        Applied = $profileApplied
        Profile = $profile
    }
}


Function GetQuickSearchProfileSummary {
    param(
        [object]$Profile,
        [string]$ProfilePath
    )

    $docPath = GetQuickSearchProfilePropertyValue -Source $Profile -Name 'DocPath'
    if ([string]::IsNullOrWhiteSpace([string]$docPath)) {
        $docPath = GetQuickSearchProfilePropertyValue -Source $Profile -Name 'Path'
    }

    $lines = @(
        "Profile file: $([System.IO.Path]::GetFileName($ProfilePath))",
        "Drive: $(GetQuickSearchProfilePropertyValue -Source $Profile -Name 'DriveLetter')",
        "Document path: $docPath",
        "TEAM path: $(GetQuickSearchProfilePropertyValue -Source $Profile -Name 'TeamPath')",
        "Types: $(@(GetQuickSearchProfilePropertyValue -Source $Profile -Name 'Types') -join ', ')",
        "Ignored folders: $(@(GetQuickSearchProfilePropertyValue -Source $Profile -Name 'Ignored') -join ', ')"
    )

    return ($lines -join [Environment]::NewLine)
}


Function SetQuickSearchProfileControls {
    param(
        [object]$Config,
        [object]$DriveComboBox,
        [object]$TypeComboBox
    )

    if ($null -ne $DriveComboBox) {
        $driveLetter = [string](GetQuickSearchProfilePropertyValue -Source $Config -Name 'DriveLetter')
        if ([string]::IsNullOrWhiteSpace($driveLetter)) { $driveLetter = 'D' }
        $driveLetter = $driveLetter.Substring(0, 1).ToUpperInvariant()
        $driveIndex = $DriveComboBox.Items.IndexOf($driveLetter)
        if ($driveIndex -ge 0) {
            $DriveComboBox.SelectedIndex = $driveIndex
        }
        elseif ($DriveComboBox.Items.Count -gt 0) {
            $DriveComboBox.SelectedIndex = [Math]::Min(3, $DriveComboBox.Items.Count - 1)
        }
    }

    if ($null -ne $TypeComboBox) {
        $previousType = [string]$TypeComboBox.Text
        $types = @(GetQuickSearchProfilePropertyValue -Source $Config -Name 'Types')
        if ($types.Count -eq 0) { $types = @('ALL', 'TSG', 'SOP', 'CASE', 'TEAM') }

        $TypeComboBox.BeginUpdate()
        try {
            $TypeComboBox.Items.Clear()
            foreach ($type in $types) {
                if (-not [string]::IsNullOrWhiteSpace([string]$type)) {
                    [void]$TypeComboBox.Items.Add([string]$type)
                }
            }
        }
        finally {
            $TypeComboBox.EndUpdate()
        }

        if (-not [string]::IsNullOrWhiteSpace($previousType) -and $TypeComboBox.Items.Contains($previousType)) {
            $TypeComboBox.SelectedItem = $previousType
        }
        elseif ($TypeComboBox.Items.Contains('ALL')) {
            $TypeComboBox.SelectedItem = 'ALL'
        }
        elseif ($TypeComboBox.Items.Count -gt 0) {
            $TypeComboBox.SelectedIndex = 0
        }
    }
}


Function ShowQuickSearchProfileSettings {
    param(
        [System.Windows.Forms.Form]$Owner,
        [object]$Config,
        [string]$ConfigPath,
        [string]$ProfilesDirectory
    )

    $profileFiles = @(GetQuickSearchProfileFiles -ProfilesDirectory $ProfilesDirectory)
    if ($profileFiles.Count -eq 0) {
        ShowQuickSearchMessageBox -Owner $Owner -Message 'No profile files were found under src\profiles.' -Title 'Profile Settings'
        return $null
    }

    $settingsForm = New-Object System.Windows.Forms.Form
    $settingsForm.Text = 'Profile Settings'
    $settingsForm.ClientSize = New-Object System.Drawing.Size(520, 230)
    $settingsForm.FormBorderStyle = 'FixedDialog'
    $settingsForm.StartPosition = 'CenterParent'
    $settingsForm.MaximizeBox = $false
    $settingsForm.MinimizeBox = $false

    $Label_Profile = New-Object System.Windows.Forms.Label
    $Label_Profile.Text = 'Profile'
    $Label_Profile.Location = New-Object System.Drawing.Point(18, 22)
    $Label_Profile.Width = 80
    $settingsForm.Controls.Add($Label_Profile)

    $ComboBox_Profile = New-Object System.Windows.Forms.ComboBox
    $ComboBox_Profile.Location = New-Object System.Drawing.Point(105, 18)
    $ComboBox_Profile.Width = 385
    $ComboBox_Profile.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    foreach ($profileFile in $profileFiles) { [void]$ComboBox_Profile.Items.Add($profileFile.Name) }
    $settingsForm.Controls.Add($ComboBox_Profile)

    $TextBox_ProfileSummary = New-Object System.Windows.Forms.TextBox
    $TextBox_ProfileSummary.Location = New-Object System.Drawing.Point(20, 55)
    $TextBox_ProfileSummary.Width = 470
    $TextBox_ProfileSummary.Height = 115
    $TextBox_ProfileSummary.Multiline = $true
    $TextBox_ProfileSummary.ReadOnly = $true
    $settingsForm.Controls.Add($TextBox_ProfileSummary)

    $Button_Apply = New-Object System.Windows.Forms.Button
    $Button_Apply.Text = 'Apply'
    $Button_Apply.Location = New-Object System.Drawing.Point(320, 185)
    $Button_Apply.Width = 80
    $settingsForm.Controls.Add($Button_Apply)

    $Button_Close = New-Object System.Windows.Forms.Button
    $Button_Close.Text = 'Close'
    $Button_Close.Location = New-Object System.Drawing.Point(410, 185)
    $Button_Close.Width = 80
    $Button_Close.Add_Click({ $settingsForm.Close() })
    $settingsForm.Controls.Add($Button_Close)

    $refreshProfileSummary = {
        $selectedName = [string]$ComboBox_Profile.SelectedItem
        $selectedPath = ResolveQuickSearchProfilePath -ProfilesDirectory $ProfilesDirectory -ProfileName $selectedName
        try {
            $selectedProfile = ReadQuickSearchProfile -ProfilePath $selectedPath
            $TextBox_ProfileSummary.Text = GetQuickSearchProfileSummary -Profile $selectedProfile -ProfilePath $selectedPath
        }
        catch {
            $TextBox_ProfileSummary.Text = "Unable to read profile: $selectedPath"
        }
    }

    $ComboBox_Profile.Add_SelectedIndexChanged($refreshProfileSummary)
    $Button_Apply.Add_Click({
        $selectedName = [string]$ComboBox_Profile.SelectedItem
        $profileState = UseQuickSearchProfile -Config $Config -ProfilesDirectory $ProfilesDirectory -ProfileName $selectedName
        if (-not $profileState.Applied) {
            ShowQuickSearchMessageBox -Owner $settingsForm -Message "Unable to apply profile: $selectedName" -Title 'Profile Settings'
            return
        }
        if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
            SaveConfig -Config $Config -ConfigPath $ConfigPath
        }
        $settingsForm.Tag = $profileState
        $settingsForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $settingsForm.Close()
    })

    $selectedProfileName = GetQuickSearchSelectedProfileName -Config $Config
    $selectedIndex = $ComboBox_Profile.Items.IndexOf($selectedProfileName)
    if ($selectedIndex -lt 0) { $selectedIndex = $ComboBox_Profile.Items.IndexOf((GetQuickSearchDefaultProfileName)) }
    if ($selectedIndex -lt 0) { $selectedIndex = 0 }
    $ComboBox_Profile.SelectedIndex = $selectedIndex

    SetQuickSearchDialogCenter -Dialog $settingsForm -Owner $Owner
    [void]$settingsForm.ShowDialog($Owner)
    return $settingsForm.Tag
}