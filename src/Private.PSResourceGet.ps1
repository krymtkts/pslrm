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
    [OutputType([PSLRMResource])]
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

    $result = [System.Collections.Generic.List[PSLRMResource]]::new()
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

function Invoke-InstallOrUpdateCore {
    [CmdletBinding()]
    [OutputType([PSLRMResource])]
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
        # Keep install reproducible when lockfile exists; future lock freshness checks can branch here.
        $lockData = Read-Lockfile -Path $lockfilePath
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
