function Get-InstalledPSLResource {
    [CmdletBinding()]
    [OutputType([object])]
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

    $result = [System.Collections.Generic.List[object]]::new()
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
    [OutputType([object])]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Path = (Get-Location).Path,

        [Parameter()]
        [switch] $IncludeDependencies
    )

    $projectRoot = Find-ProjectRoot -Path $Path
    if (-not $PSCmdlet.ShouldProcess($projectRoot, 'Install project-local resources')) {
        return
    }

    Invoke-InstallOrUpdateCore -ProjectRoot $projectRoot -Operation 'Install' -IncludeDependencies ([bool]$IncludeDependencies)
}

function Update-PSLResource {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([object])]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Path = (Get-Location).Path,

        [Parameter()]
        [switch] $IncludeDependencies
    )

    $projectRoot = Find-ProjectRoot -Path $Path
    if (-not $PSCmdlet.ShouldProcess($projectRoot, 'Update project-local resources')) {
        return
    }

    Invoke-InstallOrUpdateCore -ProjectRoot $projectRoot -Operation 'Update' -IncludeDependencies ([bool]$IncludeDependencies)
}

function Uninstall-PSLResource {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([object])]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Path = (Get-Location).Path,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]] $Name
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

    foreach ($resourceName in $Name) {
        if ([string]::IsNullOrWhiteSpace($resourceName)) {
            throw 'Name must not contain empty values.'
        }
        if (-not $requirements.ContainsKey($resourceName)) {
            throw "Requirement not found for resource '$resourceName': $requirementsPath"
        }
    }

    if (-not $PSCmdlet.ShouldProcess($projectRoot, 'Uninstall project-local resources')) {
        return
    }

    foreach ($resourceName in $Name) {
        $requirements.Remove($resourceName) | Out-Null
    }

    Write-PowerShellDataFile -Path $requirementsPath -Data $requirements

    if (Test-Path -LiteralPath $storePath) {
        if (Test-Path -LiteralPath $storePath -PathType Leaf) {
            throw "Store path must be a directory: $storePath"
        }
        Remove-Item -LiteralPath $storePath -Recurse -Force
    }

    if ($requirements.Count -eq 0) {
        $emptyLockData = @{}
        Write-Lockfile -Path $lockfilePath -Data $emptyLockData
        return @()
    }

    $resolved = Resolve-RequirementsToLockData -Requirements $requirements -RequirementsPath $requirementsPath -StorePath $storePath
    $directNames = [string[]]$resolved['DirectNames']
    $lockData = [hashtable]$resolved['LockData']

    Write-Lockfile -Path $lockfilePath -Data $lockData

    ConvertTo-PSLRMResourcesFromLockData -LockData $lockData -DirectNames $directNames -IncludeDependencies $false -ProjectRoot $projectRoot
}

function Restore-PSLResource {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([object])]
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

    $lockData = Read-Lockfile -Path $lockfilePath

    if (-not $PSCmdlet.ShouldProcess($projectRoot, 'Restore project-local resources from lockfile')) {
        return
    }

    if (Test-Path -LiteralPath $storePath) {
        if (Test-Path -LiteralPath $storePath -PathType Leaf) {
            throw "Store path must be a directory: $storePath"
        }
        Remove-Item -LiteralPath $storePath -Recurse -Force
    }

    Save-LockDataToStore -LockData $lockData -StorePath $storePath

    ConvertTo-PSLRMResourcesFromLockData -LockData $lockData -DirectNames $directNames -IncludeDependencies ([bool]$IncludeDependencies) -ProjectRoot $projectRoot
}

function Invoke-PSLResource {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $CommandName,

        [Parameter()]
        [Alias('Arguments')]
        [AllowNull()]
        [object[]] $ArgumentTokens,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Path = (Get-Location).Path,

        [Parameter()]
        [ValidateSet('IsolatedRunspace', 'InProcess')]
        [string] $ExecutionScope = 'IsolatedRunspace'
    )

    $projectRoot = Find-ProjectRoot -Path $Path

    if ($ExecutionScope -eq 'InProcess') {
        throw "ExecutionScope 'InProcess' is not implemented yet. Use 'IsolatedRunspace'."
    }

    try {
        Invoke-InIsolatedRunspace -ProjectRoot $projectRoot -CommandName $CommandName -ArgumentTokens $ArgumentTokens
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
