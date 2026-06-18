<#
.SYNOPSIS
Keeps long QuickSearch background actions responsive in the Windows Forms UI.
#>

Function ShowProcessingDialog {
    param(
        [System.Windows.Forms.Form]$Owner,
        [string]$Title = 'Processing',
        [string]$Message = 'Indexing in progress, this may take up to 10 minutes, please wait...'
    )

    $processingForm = New-Object System.Windows.Forms.Form
    $processingForm.Text = $Title
    $processingForm.ClientSize = New-Object System.Drawing.Size(420, 125)
    $processingForm.FormBorderStyle = 'FixedDialog'
    $processingForm.StartPosition = 'CenterParent'
    $processingForm.MaximizeBox = $false
    $processingForm.MinimizeBox = $false
    $processingForm.ControlBox = $false

    $Label_Message = New-Object System.Windows.Forms.Label
    $Label_Message.Text = $Message
    $Label_Message.Location = New-Object System.Drawing.Point(20, 20)
    $Label_Message.Width = 380
    $Label_Message.Height = 35
    $processingForm.Controls.Add($Label_Message)

    $ProgressBar_Indexing = New-Object System.Windows.Forms.ProgressBar
    $ProgressBar_Indexing.Location = New-Object System.Drawing.Point(20, 70)
    $ProgressBar_Indexing.Width = 380
    $ProgressBar_Indexing.Height = 22
    $ProgressBar_Indexing.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
    $processingForm.Controls.Add($ProgressBar_Indexing)

    SetQuickSearchDialogCenter -Dialog $processingForm -Owner $Owner
    if ($null -ne $Owner) {
        [void]$processingForm.Show($Owner)
    }
    else {
        [void]$processingForm.Show()
    }

    $processingForm.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
    return $processingForm
}


Function CloseProcessingDialog {
    param(
        [System.Windows.Forms.Form]$Dialog
    )

    if ($null -ne $Dialog -and -not $Dialog.IsDisposed) {
        $Dialog.Close()
        $Dialog.Dispose()
        [System.Windows.Forms.Application]::DoEvents()
    }
}


Function InvokeFileIndexWithProcessingDialog {
    param(
        [System.Windows.Forms.Form]$Owner,
        [string]$Title,
        [string]$Message,
        [string]$Root,
        [object]$Config,
        [string]$IndexFilePath
    )

    $indexScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'QuickSearch.Index.ps1'
    $configJson = '{}'
    if ($null -ne $Config) {
        $configJson = $Config | ConvertTo-Json -Depth 20
    }

    $processingDialog = ShowProcessingDialog -Owner $Owner -Title $Title -Message $Message
    $indexJob = $null
    $startedUtc = [System.DateTime]::UtcNow
    $statusFilePath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "qs-index-status-$([System.Guid]::NewGuid().ToString('N')).json"
    $cancelState = [PSCustomObject]@{ Requested = $false }
    $messageLabel = @($processingDialog.Controls | Where-Object { $_ -is [System.Windows.Forms.Label] })[0]
    $progressBar = @($processingDialog.Controls | Where-Object { $_ -is [System.Windows.Forms.ProgressBar] })[0]
    if ($null -ne $processingDialog -and -not $processingDialog.IsDisposed) {
        $processingDialog.ClientSize = New-Object System.Drawing.Size(420, 178)
        SetQuickSearchDialogCenter -Dialog $processingDialog -Owner $Owner
    }
    if ($null -ne $messageLabel) {
        $messageLabel.Height = 58
    }
    if ($null -ne $progressBar) {
        $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
        $progressBar.Location = New-Object System.Drawing.Point(20, 88)
        $progressBar.Minimum = 0
        $progressBar.Maximum = 100
        $progressBar.Value = 0
    }
    $Button_CancelIndex = New-Object System.Windows.Forms.Button
    $Button_CancelIndex.Text = 'Cancel'
    $Button_CancelIndex.Location = New-Object System.Drawing.Point(170, 130)
    $Button_CancelIndex.Width = 80
    $Button_CancelIndex.Add_Click({
        $cancelState.Requested = $true
        $Button_CancelIndex.Enabled = $false
        if ($null -ne $messageLabel) { $messageLabel.Text = 'Canceling index...' }
    })
    if ($null -ne $processingDialog -and -not $processingDialog.IsDisposed) {
        $processingDialog.Controls.Add($Button_CancelIndex)
    }

    try {
        $indexJob = Start-Job -ScriptBlock {
            param(
                [string]$JobIndexScriptPath,
                [string]$JobRoot,
                [string]$JobConfigJson,
                [string]$JobIndexFilePath,
                [string]$JobStatusFilePath
            )

            $ErrorActionPreference = 'Stop'
            . $JobIndexScriptPath
            $jobConfig = $JobConfigJson | ConvertFrom-Json
            $created = CreateFileIndex -Root $JobRoot -Config $jobConfig -IndexFilePath $JobIndexFilePath -StatusFilePath $JobStatusFilePath
            return [bool]$created
        } -ArgumentList $indexScriptPath, $Root, $configJson, $IndexFilePath, $statusFilePath

        while ($indexJob.State -in @('NotStarted', 'Running')) {
            if ($cancelState.Requested) {
                Stop-Job -Job $indexJob -ErrorAction SilentlyContinue
                return $false
            }

            if ($null -ne $processingDialog -and -not $processingDialog.IsDisposed) {
                $elapsed = [System.DateTime]::UtcNow - $startedUtc
                $processingDialog.Text = ('{0} ({1:mm\:ss})' -f $Title, $elapsed)
                if (Test-Path -LiteralPath $statusFilePath) {
                    try {
                        $status = Get-Content -LiteralPath $statusFilePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                        if ($null -ne $messageLabel) {
                            if ([int]$status.total -gt 0) {
                                $currentFile = [string]$status.currentFile
                                if ($currentFile.Length -gt 52) { $currentFile = '...' + $currentFile.Substring($currentFile.Length - 49) }
                                $reused = 0
                                if ($null -ne $status.PSObject.Properties['reused']) { $reused = [int]$status.reused }
                                $messageLabel.Text = ('{0}: {1}/{2} files, {3} indexed, {4} reused, {5} skipped' -f $status.stage, $status.processed, $status.total, $status.indexed, $reused, $status.skipped)
                                if (-not [string]::IsNullOrWhiteSpace($currentFile)) { $messageLabel.Text = $messageLabel.Text + "`n" + $currentFile }
                            }
                            else {
                                $messageLabel.Text = [string]$status.stage
                            }
                        }
                        if ($null -ne $progressBar -and [int]$status.total -gt 0) {
                            $progressBar.Value = [Math]::Min(100, [Math]::Max(0, [int](100 * [int]$status.processed / [Math]::Max(1, [int]$status.total))))
                        }
                    }
                    catch {
                    }
                }
                $processingDialog.Refresh()
            }

            [System.Windows.Forms.Application]::DoEvents()
            [System.Threading.Thread]::Sleep(150)
        }

        $created = $false
        foreach ($jobOutput in @(Receive-Job -Job $indexJob -ErrorAction Stop)) {
            if ($jobOutput -is [bool]) {
                $created = [bool]$jobOutput
            }
        }

        return $created
    }
    catch {
        Write-Host "Indexing failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
    finally {
        if ($null -ne $indexJob) {
            Remove-Job -Job $indexJob -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $statusFilePath -Force -ErrorAction SilentlyContinue
        CloseProcessingDialog -Dialog $processingDialog
    }
}


Function InvokeQuickSearchWithProcessingDialog {
    param(
        [System.Windows.Forms.Form]$Owner,
        [string]$Title = 'Search',
        [string]$Message = 'Searching in progress, please wait...',
        [string]$Root,
        [string]$Keyword,
        [bool]$SearchContent,
        [bool]$UseIndex,
        [string]$IndexFilePath,
        [object]$Config = $null,
        [string]$SelectedType = '',
        [string]$ScanScope = ''
    )

    $indexScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'QuickSearch.Index.ps1'
    $searchScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'QuickSearch.Search.ps1'
    $processingDialog = ShowProcessingDialog -Owner $Owner -Title $Title -Message $Message
    $searchJob = $null
    $startedUtc = [System.DateTime]::UtcNow
    $cancelState = [PSCustomObject]@{ Requested = $false }
    $messageLabel = @($processingDialog.Controls | Where-Object { $_ -is [System.Windows.Forms.Label] })[0]

    if ($null -ne $processingDialog -and -not $processingDialog.IsDisposed) {
        $processingDialog.ClientSize = New-Object System.Drawing.Size(420, 165)
        SetQuickSearchDialogCenter -Dialog $processingDialog -Owner $Owner
    }
    if ($null -ne $messageLabel) {
        $messageLabel.Height = 58
    }

    $Button_CancelSearch = New-Object System.Windows.Forms.Button
    $Button_CancelSearch.Text = 'Cancel'
    $Button_CancelSearch.Location = New-Object System.Drawing.Point(170, 118)
    $Button_CancelSearch.Width = 80
    $Button_CancelSearch.Add_Click({
        $cancelState.Requested = $true
        $Button_CancelSearch.Enabled = $false
        if ($null -ne $messageLabel) { $messageLabel.Text = 'Canceling search...' }
    })
    if ($null -ne $processingDialog -and -not $processingDialog.IsDisposed) {
        $processingDialog.Controls.Add($Button_CancelSearch)
    }

    try {
        if ($UseIndex) {
            $maxResults = GetQuickSearchMaxSearchResults -Config $Config
            $results = @(SearchFileIndex -IndexFilePath $IndexFilePath -Keyword $Keyword -MaxResults $maxResults)
            return [PSCustomObject]@{ Completed = $true; Canceled = $false; Failed = $false; Results = $results; ErrorMessage = '' }
        }

        $searchJob = Start-Job -ScriptBlock {
            param(
                [string]$JobIndexScriptPath,
                [string]$JobSearchScriptPath,
                [string]$JobRoot,
                [string]$JobKeyword,
                [bool]$JobSearchContent,
                [bool]$JobUseIndex,
                [string]$JobIndexFilePath,
                [object]$JobConfig,
                [string]$JobSelectedType,
                [string]$JobScanScope
            )

            $ErrorActionPreference = 'Stop'
            . $JobIndexScriptPath
            . $JobSearchScriptPath

            if ($JobUseIndex) {
                $maxResults = GetQuickSearchMaxSearchResults -Config $JobConfig
                return @(SearchFileIndex -IndexFilePath $JobIndexFilePath -Keyword $JobKeyword -MaxResults $maxResults)
            }

            return @(SearchFiles -Root $JobRoot -Keyword $JobKeyword -SearchContent $JobSearchContent -Config $JobConfig -SelectedType $JobSelectedType -IndexFilePath $JobIndexFilePath -ScanScope $JobScanScope)
        } -ArgumentList $indexScriptPath, $searchScriptPath, $Root, $Keyword, $SearchContent, $UseIndex, $IndexFilePath, $Config, $SelectedType, $ScanScope

        while ($searchJob.State -in @('NotStarted', 'Running')) {
            if ($cancelState.Requested) {
                Stop-Job -Job $searchJob -ErrorAction SilentlyContinue
                return [PSCustomObject]@{ Completed = $false; Canceled = $true; Failed = $false; Results = @(); ErrorMessage = '' }
            }

            if ($null -ne $processingDialog -and -not $processingDialog.IsDisposed) {
                $elapsed = [System.DateTime]::UtcNow - $startedUtc
                $processingDialog.Text = ('{0} ({1:mm\:ss})' -f $Title, $elapsed)
                if ($null -ne $messageLabel) {
                    $messageLabel.Text = $Message
                }
                $processingDialog.Refresh()
            }

            [System.Windows.Forms.Application]::DoEvents()
            [System.Threading.Thread]::Sleep(150)
        }

        $results = @(Receive-Job -Job $searchJob -ErrorAction Stop | ForEach-Object { [string]$_ })
        return [PSCustomObject]@{ Completed = $true; Canceled = $false; Failed = $false; Results = $results; ErrorMessage = '' }
    }
    catch {
        Write-Host "Search failed: $($_.Exception.Message)" -ForegroundColor Red
        return [PSCustomObject]@{ Completed = $false; Canceled = $false; Failed = $true; Results = @(); ErrorMessage = $_.Exception.Message }
    }
    finally {
        if ($null -ne $searchJob) {
            Remove-Job -Job $searchJob -Force -ErrorAction SilentlyContinue
        }
        CloseProcessingDialog -Dialog $processingDialog
    }
}
