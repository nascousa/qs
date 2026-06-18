<#
.SYNOPSIS
Parses and evaluates QuickSearch keyword queries.
#>

Function NewQuickSearchBooleanQueryGroup {
    return [PSCustomObject]@{
        Includes = New-Object System.Collections.ArrayList
        Excludes = New-Object System.Collections.ArrayList
    }
}


Function AddQuickSearchBooleanQueryGroup {
    param(
        [System.Collections.ArrayList]$Groups,
        [object]$Group
    )

    if ($null -eq $Group) { return }
    if ($Group.Includes.Count -eq 0 -and $Group.Excludes.Count -eq 0) { return }
    [void]$Groups.Add($Group)
}


Function GetQuickSearchBooleanQueryTokens {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    return @($Text -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}


Function ConvertToQuickSearchBooleanQuery {
    param([string]$Text)

    $groups = New-Object System.Collections.ArrayList
    $currentGroup = NewQuickSearchBooleanQueryGroup
    $pendingNot = $false

    foreach ($tokenValue in @(GetQuickSearchBooleanQueryTokens -Text $Text)) {
        $token = ([string]$tokenValue).Trim()
        if ([string]::IsNullOrWhiteSpace($token)) { continue }

        if ($token.Equals('or', [System.StringComparison]::OrdinalIgnoreCase)) {
            AddQuickSearchBooleanQueryGroup -Groups $groups -Group $currentGroup
            $currentGroup = NewQuickSearchBooleanQueryGroup
            $pendingNot = $false
            continue
        }

        if ($token.Equals('and', [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        if ($token.Equals('not', [System.StringComparison]::OrdinalIgnoreCase)) {
            $pendingNot = -not $pendingNot
            continue
        }

        if ($pendingNot) {
            [void]$currentGroup.Excludes.Add($token)
        }
        else {
            [void]$currentGroup.Includes.Add($token)
        }
        $pendingNot = $false
    }

    AddQuickSearchBooleanQueryGroup -Groups $groups -Group $currentGroup

    return [PSCustomObject]@{
        Raw = [string]$Text
        Groups = @($groups)
    }
}


Function TestQuickSearchBooleanQueryHasTerms {
    param([object]$Query)

    return ($null -ne $Query -and @($Query.Groups).Count -gt 0)
}


Function AddQuickSearchQueryTermSetValue {
    param(
        [System.Collections.ArrayList]$Terms,
        [hashtable]$Seen,
        [string]$Term
    )

    if ([string]::IsNullOrWhiteSpace($Term)) { return }
    $key = $Term.ToLowerInvariant()
    if ($Seen.ContainsKey($key)) { return }
    $Seen[$key] = $true
    [void]$Terms.Add($Term)
}


Function GetQuickSearchBooleanQueryTerms {
    param([object]$Query)

    $terms = New-Object System.Collections.ArrayList
    $seen = @{}
    foreach ($group in @($Query.Groups)) {
        foreach ($term in @($group.Includes)) { AddQuickSearchQueryTermSetValue -Terms $terms -Seen $seen -Term ([string]$term) }
        foreach ($term in @($group.Excludes)) { AddQuickSearchQueryTermSetValue -Terms $terms -Seen $seen -Term ([string]$term) }
    }

    return @($terms | ForEach-Object { [string]$_ })
}


Function GetQuickSearchBooleanQueryPositiveTerms {
    param([object]$Query)

    $terms = New-Object System.Collections.ArrayList
    $seen = @{}
    foreach ($group in @($Query.Groups)) {
        foreach ($term in @($group.Includes)) { AddQuickSearchQueryTermSetValue -Terms $terms -Seen $seen -Term ([string]$term) }
    }

    return @($terms | ForEach-Object { [string]$_ })
}


Function TestQuickSearchBooleanQueryHasExcludes {
    param([object]$Query)

    foreach ($group in @($Query.Groups)) {
        if (@($group.Excludes).Count -gt 0) { return $true }
    }

    return $false
}


Function GetQuickSearchBooleanQueryHighlightTerm {
    param([object]$Query)

    $positiveTerms = @(GetQuickSearchBooleanQueryPositiveTerms -Query $Query)
    if ($positiveTerms.Count -gt 0) { return [string]$positiveTerms[0] }

    $allTerms = @(GetQuickSearchBooleanQueryTerms -Query $Query)
    if ($allTerms.Count -gt 0) { return [string]$allTerms[0] }
    return ''
}


Function TestQuickSearchTextContainsTerm {
    param(
        [string]$Text,
        [string]$Term
    )

    if ([string]::IsNullOrWhiteSpace($Term)) { return $false }
    return ([string]$Text).IndexOf($Term, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
}


Function TestQuickSearchBooleanQueryText {
    param(
        [object]$Query,
        [string]$Text
    )

    if (-not (TestQuickSearchBooleanQueryHasTerms -Query $Query)) { return $false }

    foreach ($group in @($Query.Groups)) {
        $groupMatches = $true
        foreach ($term in @($group.Includes)) {
            if (-not (TestQuickSearchTextContainsTerm -Text $Text -Term ([string]$term))) {
                $groupMatches = $false
                break
            }
        }

        if (-not $groupMatches) { continue }

        foreach ($term in @($group.Excludes)) {
            if (TestQuickSearchTextContainsTerm -Text $Text -Term ([string]$term)) {
                $groupMatches = $false
                break
            }
        }

        if ($groupMatches) { return $true }
    }

    return $false
}


Function TestQuickSearchBooleanQueryPresence {
    param(
        [object]$Query,
        [hashtable]$Presence
    )

    if (-not (TestQuickSearchBooleanQueryHasTerms -Query $Query)) { return $false }

    foreach ($group in @($Query.Groups)) {
        $groupMatches = $true
        foreach ($term in @($group.Includes)) {
            $key = ([string]$term).ToLowerInvariant()
            if (-not $Presence.ContainsKey($key) -or -not $Presence[$key]) {
                $groupMatches = $false
                break
            }
        }

        if (-not $groupMatches) { continue }

        foreach ($term in @($group.Excludes)) {
            $key = ([string]$term).ToLowerInvariant()
            if ($Presence.ContainsKey($key) -and $Presence[$key]) {
                $groupMatches = $false
                break
            }
        }

        if ($groupMatches) { return $true }
    }

    return $false
}


Function GetQuickSearchSinglePositiveQueryTerm {
    param([object]$Query)

    if (-not (TestQuickSearchBooleanQueryHasTerms -Query $Query)) { return '' }
    if (@($Query.Groups).Count -ne 1) { return '' }
    $group = @($Query.Groups)[0]
    if (@($group.Includes).Count -ne 1 -or @($group.Excludes).Count -ne 0) { return '' }
    return [string]@($group.Includes)[0]
}