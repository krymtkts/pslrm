function Assert-RequirementsAreSupported {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable] $Requirements,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RequirementsPath
    )

    foreach ($name in $Requirements.Keys) {
        $entry = $Requirements[$name]
        if ($entry -isnot [hashtable]) {
            throw "Requirement entry must be a hashtable for resource '$name': $RequirementsPath"
        }

        $repository = $entry['Repository']
        if ($repository -is [string] -and (-not [string]::IsNullOrWhiteSpace($repository))) {
            if ($repository -ine 'PSGallery') {
                throw "Only PSGallery is supported for Repository. Invalid repository '$repository' for '$name' in: $RequirementsPath"
            }
        }
    }
}

function Invoke-SavePSResource {
    [CmdletBinding()]
    [OutputType([Microsoft.PowerShell.PSResourceGet.UtilClasses.PSResourceInfo])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter()]
        [AllowNull()]
        [string] $Version,

        [Parameter()]
        [switch] $Prerelease,

        [Parameter()]
        [AllowNull()]
        [string] $Repository,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
    elseif (Test-Path -LiteralPath $Path -PathType Leaf) {
        throw "Save path must be a directory: $Path"
    }

    $params = @{
        Name = $Name
        Path = $Path
        PassThru = $true
    }
    if (-not [string]::IsNullOrWhiteSpace($Version)) {
        $params['Version'] = $Version
    }
    if ($Prerelease) {
        $params['Prerelease'] = $true
    }
    if (-not [string]::IsNullOrWhiteSpace($Repository)) {
        $params['Repository'] = $Repository
    }

    Save-PSResource @params
}

function Resolve-RequirementsToLockData {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable] $Requirements,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $RequirementsPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $StorePath
    )

    Assert-RequirementsAreSupported -Requirements $Requirements -RequirementsPath $RequirementsPath

    $savedResources = [System.Collections.Generic.List[Microsoft.PowerShell.PSResourceGet.UtilClasses.PSResourceInfo]]::new()
    $directNames = [string[]]$Requirements.Keys
    foreach ($name in $directNames) {
        $entry = $Requirements[$name]
        if ($entry -isnot [hashtable]) {
            throw "Requirement entry must be a hashtable for resource '$name': $RequirementsPath"
        }

        $ver = $entry['Version']
        $verString = if ($null -eq $ver) {
            $null
        }
        elseif ($ver -is [string]) {
            $ver.Trim()
        }
        else {
            $ver.ToString()
        }
        if ([string]::IsNullOrWhiteSpace($verString)) {
            $verString = $null
        }

        $prereleaseSwitch = $false
        if ($entry.ContainsKey('Prerelease')) {
            $prereleaseSwitch = [bool]$entry['Prerelease']
        }

        $saved = Invoke-SavePSResource -Name $name -Version $verString -Prerelease:$prereleaseSwitch -Repository 'PSGallery' -Path $StorePath
        foreach ($s in @($saved)) {
            if ($null -ne $s) {
                $savedResources.Add($s)
            }
        }
    }

    $lockData = @{}
    foreach ($r in $savedResources) {
        if ($null -eq $r) {
            continue
        }

        $name = $r.Name
        if (-not ($name -is [string]) -or [string]::IsNullOrWhiteSpace($name)) {
            throw 'Save-PSResource returned an entry without a valid Name.'
        }

        $repository = $r.Repository
        if (-not ($repository -is [string]) -or [string]::IsNullOrWhiteSpace($repository)) {
            $repository = 'PSGallery'
        }
        if ($repository -ine 'PSGallery') {
            throw "Only PSGallery is supported for Repository. Invalid repository '$repository' returned for '$name'."
        }

        $normalizedVersion = ConvertTo-NormalizedVersionString -Version $r.Version -Prerelease $r.Prerelease
        $lockData[$name] = @{
            Version = $normalizedVersion
            Repository = 'PSGallery'
        }
    }

    @{
        DirectNames = $directNames
        LockData = $lockData
    }
}

function ConvertTo-PSLRMResourcesFromLockData {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable] $LockData,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string[]] $DirectNames,

        [Parameter(Mandatory)]
        [bool] $IncludeDependencies,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ProjectRoot
    )

    $names = [string[]]$LockData.Keys
    [System.Array]::Sort($names, [System.StringComparer]::Ordinal)

    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($name in $names) {
        $isDirect = $DirectNames -contains $name
        if ($IncludeDependencies -or $isDirect) {
            $entry = $LockData[$name]
            $result.Add((New-Resource -Name $name -Version $entry['Version'] -Prerelease $null -Repository 'PSGallery' -IsDirect $isDirect -ProjectRoot $ProjectRoot))
        }
    }

    $result.ToArray()
}

function Save-LockDataToStore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable] $LockData,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $StorePath
    )

    $names = [string[]]$LockData.Keys
    [System.Array]::Sort($names, [System.StringComparer]::Ordinal)

    foreach ($name in $names) {
        $entry = $LockData[$name]
        if ($entry -isnot [hashtable]) {
            throw "Lockfile entry must be a hashtable for resource '$name'."
        }

        $version = $entry['Version']
        $versionString = if ($null -eq $version) {
            $null
        }
        elseif ($version -is [string]) {
            $version.Trim()
        }
        else {
            $version.ToString()
        }
        if ([string]::IsNullOrWhiteSpace($versionString)) {
            throw "Lockfile entry must contain a non-empty Version for '$name'."
        }

        $repository = $entry['Repository']
        if (-not ($repository -is [string]) -or [string]::IsNullOrWhiteSpace($repository)) {
            $repository = 'PSGallery'
        }
        if ($repository -ine 'PSGallery') {
            throw "Only PSGallery is supported for Repository. Invalid repository '$repository' for '$name'."
        }

        $prereleaseSwitch = $false
        if ($entry.ContainsKey('Prerelease')) {
            $prereleaseSwitch = [bool]$entry['Prerelease']
        }
        elseif ($versionString -match '-') {
            $prereleaseSwitch = $true
        }

        Invoke-SavePSResource -Name $name -Version $versionString -Prerelease:$prereleaseSwitch -Repository 'PSGallery' -Path $StorePath | Out-Null
    }
}

function Test-VersionConstraintSatisfied {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $VersionConstraint,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $ResolvedVersion
    )

    $constraintString = ConvertTo-NormalizedVersionString -Version $VersionConstraint
    if ([string]::IsNullOrWhiteSpace($constraintString)) {
        return $true
    }

    $resolvedVersionString = ConvertTo-NormalizedVersionString -Version $ResolvedVersion
    if ([string]::IsNullOrWhiteSpace($resolvedVersionString)) {
        throw 'ResolvedVersion must be a non-empty version string.'
    }

    function ConvertTo-ComparableVersion {
        param(
            [Parameter(Mandatory)]
            [string] $VersionString,

            [Parameter(Mandatory)]
            [string] $Label
        )

        if ($VersionString -notmatch '^(?<core>\d+(?:\.\d+){0,3})(?:-(?<prerelease>.+))?$') {
            throw "Unsupported version format for ${Label}: '$VersionString'"
        }

        $segments = [System.Collections.Generic.List[int]]::new()
        foreach ($segment in ($Matches['core'] -split '\.')) {
            $segments.Add([int]$segment)
        }

        $prerelease = $Matches['prerelease']
        $prereleaseIdentifiers = if ([string]::IsNullOrWhiteSpace($prerelease)) {
            @()
        }
        else {
            @($prerelease.Split('.'))
        }

        [pscustomobject]@{
            Core = $segments.ToArray()
            Prerelease = $prerelease
            PrereleaseIdentifiers = $prereleaseIdentifiers
        }
    }

    function Compare-ComparableVersion {
        param(
            [Parameter(Mandatory)]
            [psobject] $Left,

            [Parameter(Mandatory)]
            [psobject] $Right
        )

        $leftCore = @($Left.Core)
        $rightCore = @($Right.Core)
        $leftPrereleaseIdentifiers = @($Left.PrereleaseIdentifiers)
        $rightPrereleaseIdentifiers = @($Right.PrereleaseIdentifiers)

        $maxCoreLength = [Math]::Max($leftCore.Count, $rightCore.Count)
        for ($index = 0; $index -lt $maxCoreLength; $index++) {
            $leftSegment = if ($index -lt $leftCore.Count) { $leftCore[$index] } else { 0 }
            $rightSegment = if ($index -lt $rightCore.Count) { $rightCore[$index] } else { 0 }
            if ($leftSegment -lt $rightSegment) {
                return -1
            }
            if ($leftSegment -gt $rightSegment) {
                return 1
            }
        }

        $leftHasPrerelease = -not [string]::IsNullOrWhiteSpace($Left.Prerelease)
        $rightHasPrerelease = -not [string]::IsNullOrWhiteSpace($Right.Prerelease)
        if ($leftHasPrerelease -and (-not $rightHasPrerelease)) {
            return -1
        }
        if ((-not $leftHasPrerelease) -and $rightHasPrerelease) {
            return 1
        }
        if ((-not $leftHasPrerelease) -and (-not $rightHasPrerelease)) {
            return 0
        }

        $maxPrereleaseLength = [Math]::Max($leftPrereleaseIdentifiers.Count, $rightPrereleaseIdentifiers.Count)
        for ($index = 0; $index -lt $maxPrereleaseLength; $index++) {
            if ($index -ge $leftPrereleaseIdentifiers.Count) {
                return -1
            }
            if ($index -ge $rightPrereleaseIdentifiers.Count) {
                return 1
            }

            $leftIdentifier = [string]$leftPrereleaseIdentifiers[$index]
            $rightIdentifier = [string]$rightPrereleaseIdentifiers[$index]
            $leftIsNumeric = $leftIdentifier -match '^\d+$'
            $rightIsNumeric = $rightIdentifier -match '^\d+$'

            if ($leftIsNumeric -and $rightIsNumeric) {
                $leftNumber = [int64]$leftIdentifier
                $rightNumber = [int64]$rightIdentifier
                if ($leftNumber -lt $rightNumber) {
                    return -1
                }
                if ($leftNumber -gt $rightNumber) {
                    return 1
                }
                continue
            }

            if ($leftIsNumeric -and (-not $rightIsNumeric)) {
                return -1
            }
            if ((-not $leftIsNumeric) -and $rightIsNumeric) {
                return 1
            }

            $comparison = [System.StringComparer]::OrdinalIgnoreCase.Compare($leftIdentifier, $rightIdentifier)
            if ($comparison -lt 0) {
                return -1
            }
            if ($comparison -gt 0) {
                return 1
            }
        }

        return 0
    }

    $resolvedComparable = ConvertTo-ComparableVersion -VersionString $resolvedVersionString -Label 'ResolvedVersion'

    if (($constraintString.StartsWith('[') -or $constraintString.StartsWith('(')) -and ($constraintString.EndsWith(']') -or $constraintString.EndsWith(')'))) {
        if ($constraintString -match '^\[(?<exact>[^,\]]+)\]$') {
            $exactComparable = ConvertTo-ComparableVersion -VersionString $Matches['exact'].Trim() -Label 'VersionConstraint'
            return ((Compare-ComparableVersion -Left $resolvedComparable -Right $exactComparable) -eq 0)
        }

        if ($constraintString -notmatch '^(?<lowerBracket>[\[\(])\s*(?<lower>[^,\)]*)\s*,\s*(?<upper>[^\]\)]*)\s*(?<upperBracket>[\]\)])$') {
            throw "Unsupported version constraint format: '$constraintString'"
        }

        if (-not [string]::IsNullOrWhiteSpace($Matches['lower'])) {
            $lowerComparable = ConvertTo-ComparableVersion -VersionString $Matches['lower'].Trim() -Label 'VersionConstraint lower bound'
            $lowerComparison = Compare-ComparableVersion -Left $resolvedComparable -Right $lowerComparable
            if (($Matches['lowerBracket'] -eq '[') -and ($lowerComparison -lt 0)) {
                return $false
            }
            if (($Matches['lowerBracket'] -eq '(') -and ($lowerComparison -le 0)) {
                return $false
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($Matches['upper'])) {
            $upperComparable = ConvertTo-ComparableVersion -VersionString $Matches['upper'].Trim() -Label 'VersionConstraint upper bound'
            $upperComparison = Compare-ComparableVersion -Left $resolvedComparable -Right $upperComparable
            if (($Matches['upperBracket'] -eq ']') -and ($upperComparison -gt 0)) {
                return $false
            }
            if (($Matches['upperBracket'] -eq ')') -and ($upperComparison -ge 0)) {
                return $false
            }
        }

        return $true
    }

    $exactVersionComparable = ConvertTo-ComparableVersion -VersionString $constraintString -Label 'VersionConstraint'
    (Compare-ComparableVersion -Left $resolvedComparable -Right $exactVersionComparable) -eq 0
}

function Test-LockfileDrift {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable] $Requirements,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable] $LockData
    )

    $reasons = [System.Collections.Generic.List[string]]::new()
    $missingDirectNames = [System.Collections.Generic.List[string]]::new()
    $unexpectedDirectNames = [System.Collections.Generic.List[string]]::new()
    $repositoryMismatches = [System.Collections.Generic.List[string]]::new()
    $prereleaseViolations = [System.Collections.Generic.List[string]]::new()
    $versionViolations = [System.Collections.Generic.List[string]]::new()

    $directNames = [string[]]$Requirements.Keys
    [System.Array]::Sort($directNames, [System.StringComparer]::Ordinal)

    foreach ($name in $directNames) {
        if (-not $LockData.ContainsKey($name)) {
            $missingDirectNames.Add($name)
            $reasons.Add("Missing direct dependency in lockfile: '$name'.")
            continue
        }

        $requirementEntry = $Requirements[$name]
        if ($requirementEntry -isnot [hashtable]) {
            throw "Requirement entry must be a hashtable for resource '$name'."
        }

        $lockEntry = $LockData[$name]
        if ($lockEntry -isnot [hashtable]) {
            throw "Lockfile entry must be a hashtable for resource '$name'."
        }

        $requirementRepository = $requirementEntry['Repository']
        if (-not ($requirementRepository -is [string]) -or [string]::IsNullOrWhiteSpace($requirementRepository)) {
            $requirementRepository = 'PSGallery'
        }

        $lockRepository = $lockEntry['Repository']
        if (-not ($lockRepository -is [string]) -or [string]::IsNullOrWhiteSpace($lockRepository)) {
            $lockRepository = 'PSGallery'
        }

        if ($requirementRepository -cne $lockRepository) {
            $repositoryMismatches.Add($name)
            $reasons.Add("Repository mismatch for '$name': requirements=$requirementRepository lockfile=$lockRepository")
        }

        $resolvedVersion = ConvertTo-NormalizedVersionString -Version $lockEntry['Version'] -Prerelease $null
        if ([string]::IsNullOrWhiteSpace($resolvedVersion)) {
            $versionViolations.Add($name)
            $reasons.Add("Lockfile entry must contain a non-empty Version for '$name'.")
            continue
        }

        $allowPrerelease = $false
        if ($requirementEntry.ContainsKey('Prerelease')) {
            $allowPrerelease = [bool]$requirementEntry['Prerelease']
        }

        if ((-not $allowPrerelease) -and ($resolvedVersion -match '-')) {
            $prereleaseViolations.Add($name)
            $reasons.Add("Prerelease version is not allowed for '$name': $resolvedVersion")
        }

        $versionConstraint = ConvertTo-NormalizedVersionString -Version $requirementEntry['Version'] -Prerelease $null
        if ((-not [string]::IsNullOrWhiteSpace($versionConstraint)) -and (-not (Test-VersionConstraintSatisfied -VersionConstraint $versionConstraint -ResolvedVersion $resolvedVersion))) {
            $versionViolations.Add($name)
            $reasons.Add("Resolved version '$resolvedVersion' does not satisfy version constraint '$versionConstraint' for '$name'.")
        }
    }

    [pscustomobject]@{
        IsDrifted = ($reasons.Count -gt 0)
        Reasons = $reasons.ToArray()
        MissingDirectNames = $missingDirectNames.ToArray()
        UnexpectedDirectNames = $unexpectedDirectNames.ToArray()
        RepositoryMismatches = $repositoryMismatches.ToArray()
        PrereleaseViolations = $prereleaseViolations.ToArray()
        VersionViolations = $versionViolations.ToArray()
    }
}

function Invoke-InstallOrUpdateCore {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ProjectRoot,

        [Parameter(Mandatory)]
        [ValidateSet('Install', 'Update')]
        [string] $Operation,

        [Parameter(Mandatory)]
        [bool] $IncludeDependencies
    )

    $requirementsPath = Get-RequirementsPath -ProjectRoot $ProjectRoot
    $lockfilePath = Get-LockfilePath -ProjectRoot $ProjectRoot
    $storePath = Get-StorePath -ProjectRoot $ProjectRoot

    $requirements = Import-PowerShellDataFile -Path $requirementsPath
    if ($requirements -isnot [hashtable]) {
        throw "Requirements file must be a hashtable: $requirementsPath"
    }

    Assert-RequirementsAreSupported -Requirements $requirements -RequirementsPath $requirementsPath
    $directNames = [string[]]$requirements.Keys

    if (($Operation -eq 'Install') -and (Test-Path -LiteralPath $lockfilePath)) {
        $lockData = Read-Lockfile -Path $lockfilePath
        $driftResult = Test-LockfileDrift -Requirements $requirements -LockData $lockData
        if ($driftResult.IsDrifted) {
            $reasonText = $driftResult.Reasons -join ' '
            throw "Requirements and lockfile are out of sync. Run Update-PSLResource to refresh the lockfile. $reasonText"
        }

        Save-LockDataToStore -LockData $lockData -StorePath $storePath

        return (ConvertTo-PSLRMResourcesFromLockData -LockData $lockData -DirectNames $directNames -IncludeDependencies $IncludeDependencies -ProjectRoot $ProjectRoot)
    }

    # Shared resolve-and-write path (currently Update always and Install when lockfile is missing).
    # Future module-scoped operations can filter requirements before resolution here.
    $resolved = Resolve-RequirementsToLockData -Requirements $requirements -RequirementsPath $requirementsPath -StorePath $storePath
    $directNames = [string[]]$resolved['DirectNames']
    $lockData = [hashtable]$resolved['LockData']

    Write-Lockfile -Path $lockfilePath -Data $lockData

    ConvertTo-PSLRMResourcesFromLockData -LockData $lockData -DirectNames $directNames -IncludeDependencies $IncludeDependencies -ProjectRoot $ProjectRoot
}
