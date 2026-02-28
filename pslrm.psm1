Set-StrictMode -Version Latest

$script:PSLRMRequirementsFileName = 'psreq.psd1'
$script:PSLRMLockfileFileName = 'psreq.lock.psd1'
$script:PSLRMStoreDirectoryName = '.pslrm'

# Internal helpers

function Get-RequirementsPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ProjectRoot
    )

    Join-Path $ProjectRoot $script:PSLRMRequirementsFileName
}

function Get-LockfilePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ProjectRoot
    )

    Join-Path $ProjectRoot $script:PSLRMLockfileFileName
}

function Get-StorePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ProjectRoot
    )

    Join-Path $ProjectRoot $script:PSLRMStoreDirectoryName
}

class PSLRMResource {
    [string] $Name
    [string] $Version
    [string] $Repository
    [bool] $IsDirect
    [string] $ProjectRoot

    PSLRMResource(
        [string] $Name,
        [string] $Version,
        [string] $Repository,
        [bool] $IsDirect,
        [string] $ProjectRoot
    ) {
        $this.Name = $Name
        $this.Version = $Version
        $this.Repository = $Repository
        $this.IsDirect = $IsDirect
        $this.ProjectRoot = $ProjectRoot

        $this.PSObject.TypeNames.Insert(0, 'PSLRM.Resource')
    }
}

function ConvertTo-NormalizedVersionString {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Version,

        [Parameter()]
        [AllowNull()]
        [string] $Prerelease
    )

    if ($null -eq $Version) {
        return $null
    }

    $normalized = if ($Version -is [string]) { $Version } else { $Version.ToString() }
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return $null
    }

    $normalized = $normalized.Trim()

    # NOTE: PSResourceGet reports prerelease separately (Version + Prerelease). Preserve it.
    if (-not [string]::IsNullOrWhiteSpace($Prerelease)) {
        $pr = $Prerelease.Trim()
        if (-not [string]::IsNullOrWhiteSpace($pr)) {
            if ($normalized -notmatch '-') {
                return "$normalized-$pr"
            }
        }
    }

    $normalized
}

function ConvertTo-PowerShellDataFileLiteral {
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Value,

        [Parameter(Mandatory)]
        [ValidateRange(0, 16)]
        [int] $IndentLevel,

        [Parameter(Mandatory)]
        [ValidateRange(2, 4)]
        [int] $IndentWidth
    )

    switch ($true) {
        ($null -eq $Value) {
            return '$null'
        }
        ($Value -is [hashtable]) {
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add('@{')

            $keys = [string[]]$Value.Keys
            [System.Array]::Sort($keys, [System.StringComparer]::Ordinal)
            $entryIndent = ' ' * ($IndentWidth * ($IndentLevel + 1))
            $closeIndent = ' ' * ($IndentWidth * $IndentLevel)
            foreach ($key in $keys) {
                $escapedKey = $key -replace "'", "''"
                $keyLiteral = "'$escapedKey'"

                $valLiteral = ConvertTo-PowerShellDataFileLiteral -Value $Value[$key] -IndentLevel ($IndentLevel + 1) -IndentWidth $IndentWidth
                $lines.Add($entryIndent + "$keyLiteral = $valLiteral")
            }

            $lines.Add($closeIndent + '}')
            if ($IndentLevel -eq 0) {
                $lines.Add('')
            }
            return ($lines -join "`n")
        }
        ($Value -is [string]) {
            $escaped = $Value -replace "'", "''"
            return "'$escaped'"
        }
        ($Value -is [bool]) {
            if ($Value) {
                return '$true'
            }
            return '$false'
        }
        ($Value.GetType() -in @([byte], [int16], [int32], [int64], [uint16], [uint32], [uint64], [single], [double], [decimal])) {
            return [string]$Value
        }
        ($Value -is [version]) {
            return "'$($Value.ToString())'"
        }
        ($Value -is [array]) {
            $itemLiterals = [System.Collections.Generic.List[string]]::new()
            foreach ($item in $Value) {
                $itemLiterals.Add((ConvertTo-PowerShellDataFileLiteral -Value $item -IndentLevel ($IndentLevel + 1) -IndentWidth $IndentWidth))
            }
            return '@(' + ($itemLiterals -join ', ') + ')'
        }
        default {
            throw "Unsupported value type for PowerShell data file serialization: $($Value.GetType().FullName)"
        }
    }
}

function Write-PowerShellDataFile {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable] $Data,

        [Parameter()]
        [ValidateRange(2, 4)]
        [int] $IndentWidth = 4
    )

    $directory = Split-Path -Parent -Path $Path
    if ([string]::IsNullOrWhiteSpace($directory)) {
        $directory = (Get-Location).Path
    }

    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory | Out-Null
    }

    $content = ConvertTo-PowerShellDataFileLiteral -Value $Data -IndentLevel 0 -IndentWidth $IndentWidth

    if (-not $PSCmdlet.ShouldProcess($Path, 'Write PowerShell data file')) {
        return
    }

    $tmp = [System.IO.Path]::Combine($directory, [System.IO.Path]::GetRandomFileName())
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)

    try {
        [System.IO.File]::WriteAllText($tmp, $content, $utf8NoBom)
        Move-Item -LiteralPath $tmp -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $tmp) {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }
}

function Read-Lockfile {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ -not [string]::IsNullOrWhiteSpace($_) })]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Lockfile not found: $Path"
    }

    $data = Import-PowerShellDataFile -Path $Path
    if ($data -isnot [hashtable]) {
        throw "Lockfile must be a hashtable: $Path"
    }

    $data
}

function Write-Lockfile {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ -not [string]::IsNullOrWhiteSpace($_) })]
        [string] $Path,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable] $Data
    )

    # NOTE: indent width is fixed to 4 for lockfile to ensure deterministic output.
    Write-PowerShellDataFile -Path $Path -Data $Data -IndentWidth 4
}

function Find-ProjectRoot {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [ValidateNotNullOrWhiteSpace()]
        [string] $Path = (Get-Location).Path
    )

    $cursor = $Path

    if (Test-Path -LiteralPath $cursor -PathType Leaf) {
        $cursor = Split-Path -Parent -Path $cursor
    }

    if (-not (Test-Path -LiteralPath $cursor -PathType Container)) {
        throw "Path not found or not a directory: $Path"
    }

    while ($true) {
        $requirementsPath = Get-RequirementsPath -ProjectRoot $cursor
        if (Test-Path -LiteralPath $requirementsPath) {
            return $cursor
        }

        $parent = Split-Path -Parent -Path $cursor
        if ([string]::IsNullOrWhiteSpace($parent) -or ($parent -eq $cursor)) {
            break
        }
        $cursor = $parent
    }

    throw "Project root not found. Missing psreq.psd1 from: $Path"
}

function New-Resource {
    [CmdletBinding()]
    [OutputType([PSLRMResource])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter()]
        [AllowNull()]
        [object] $Version,

        [Parameter()]
        [AllowNull()]
        [string] $Prerelease,

        [Parameter()]
        [AllowNull()]
        [string] $Repository,

        [Parameter(Mandatory)]
        [bool] $IsDirect,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ProjectRoot
    )

    $normalizedVersion = ConvertTo-NormalizedVersionString -Version $Version -Prerelease $Prerelease
    [PSLRMResource]::new($Name, $normalizedVersion, $Repository, $IsDirect, $ProjectRoot)
}

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

        $null = Invoke-SavePSResource -Name $name -Version $versionString -Prerelease:$prereleaseSwitch -Repository 'PSGallery' -Path $StorePath
    }
}

# Public cmdlets

function Get-InstalledPSLResource {
    [CmdletBinding()]
    [OutputType([PSLRMResource])]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Path = (Get-Location).Path,

        [Parameter()]
        [switch] $IncludeDependencies
    )

    $projectRoot = Find-ProjectRoot -Path $Path
    $requirementsPath = Get-RequirementsPath -ProjectRoot $projectRoot
    $lockfilePath = Get-LockfilePath -ProjectRoot $projectRoot

    $requirements = Import-PowerShellDataFile -Path $requirementsPath
    if ($requirements -isnot [hashtable]) {
        throw "Requirements file must be a hashtable: $requirementsPath"
    }
    $directNames = [string[]]$requirements.Keys

    $lock = Read-Lockfile -Path $lockfilePath

    $names = [string[]]$lock.Keys
    [System.Array]::Sort($names, [System.StringComparer]::Ordinal)

    $result = [System.Collections.Generic.List[PSLRMResource]]::new()
    foreach ($name in $names) {
        $entry = $lock[$name]
        if ($entry -isnot [hashtable]) {
            throw "Lockfile entry must be a hashtable for resource '$name': $lockfilePath"
        }

        $version = $entry['Version']
        $prerelease = $entry['Prerelease']
        if ($prerelease -isnot [string]) {
            $prerelease = $null
        }
        $repository = $entry['Repository']

        $isDirect = $directNames -contains $name
        if ($IncludeDependencies -or $isDirect) {
            $result.Add((New-Resource -Name $name -Version $version -Prerelease $prerelease -Repository $repository -IsDirect $isDirect -ProjectRoot $projectRoot))
        }
    }

    $result.ToArray()
}

function Install-PSLResource {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSLRMResource])]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Path = (Get-Location).Path,

        [Parameter()]
        [switch] $IncludeDependencies
    )

    $projectRoot = Find-ProjectRoot -Path $Path
    $requirementsPath = Get-RequirementsPath -ProjectRoot $projectRoot
    $lockfilePath = Get-LockfilePath -ProjectRoot $projectRoot
    $storePath = Get-StorePath -ProjectRoot $projectRoot

    $requirements = Import-PowerShellDataFile -Path $requirementsPath
    if ($requirements -isnot [hashtable]) {
        throw "Requirements file must be a hashtable: $requirementsPath"
    }
    Assert-RequirementsAreSupported -Requirements $requirements -RequirementsPath $requirementsPath
    $directNames = [string[]]$requirements.Keys

    if (-not $PSCmdlet.ShouldProcess($projectRoot, 'Install project-local resources')) {
        return
    }

    if (Test-Path -LiteralPath $lockfilePath) {
        $lockData = Read-Lockfile -Path $lockfilePath
        Save-LockDataToStore -LockData $lockData -StorePath $storePath

        ConvertTo-PSLRMResourcesFromLockData -LockData $lockData -DirectNames $directNames -IncludeDependencies ([bool]$IncludeDependencies) -ProjectRoot $projectRoot
        return
    }

    $resolved = Resolve-RequirementsToLockData -Requirements $requirements -RequirementsPath $requirementsPath -StorePath $storePath
    $directNames = [string[]]$resolved['DirectNames']
    $lockData = [hashtable]$resolved['LockData']

    Write-Lockfile -Path $lockfilePath -Data $lockData

    ConvertTo-PSLRMResourcesFromLockData -LockData $lockData -DirectNames $directNames -IncludeDependencies ([bool]$IncludeDependencies) -ProjectRoot $projectRoot
}

function Update-PSLResource {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSLRMResource])]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Path = (Get-Location).Path,

        [Parameter()]
        [switch] $IncludeDependencies
    )

    $projectRoot = Find-ProjectRoot -Path $Path
    $requirementsPath = Get-RequirementsPath -ProjectRoot $projectRoot
    $lockfilePath = Get-LockfilePath -ProjectRoot $projectRoot
    $storePath = Get-StorePath -ProjectRoot $projectRoot

    $requirements = Import-PowerShellDataFile -Path $requirementsPath
    if ($requirements -isnot [hashtable]) {
        throw "Requirements file must be a hashtable: $requirementsPath"
    }

    if (-not $PSCmdlet.ShouldProcess($projectRoot, 'Update project-local resources')) {
        return
    }

    # Update also regenerates lockfile from scratch to keep it aligned with the latest save results.
    $resolved = Resolve-RequirementsToLockData -Requirements $requirements -RequirementsPath $requirementsPath -StorePath $storePath
    $directNames = [string[]]$resolved['DirectNames']
    $lockData = [hashtable]$resolved['LockData']

    Write-Lockfile -Path $lockfilePath -Data $lockData

    ConvertTo-PSLRMResourcesFromLockData -LockData $lockData -DirectNames $directNames -IncludeDependencies ([bool]$IncludeDependencies) -ProjectRoot $projectRoot
}

Export-ModuleMember -Function @(
    'Get-InstalledPSLResource',
    'Install-PSLResource',
    'Update-PSLResource'
)
