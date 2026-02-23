Set-StrictMode -Version Latest

$script:PSLRMRequirementsFileName = 'psreq.psd1'
$script:PSLRMLockfileFileName = 'psreq.lock.psd1'
$script:PSLRMStoreDirectoryName = '.pslrm'

# Internal helpers

function Get-RequirementsPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ProjectRoot
    )

    return Join-Path $ProjectRoot $script:PSLRMRequirementsFileName
}

function Get-LockfilePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ProjectRoot
    )

    return Join-Path $ProjectRoot $script:PSLRMLockfileFileName
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

    return $normalized
}

function ConvertTo-PowerShellDataFileLiteral {
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

    return $data
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
    return [PSLRMResource]::new($Name, $normalizedVersion, $Repository, $IsDirect, $ProjectRoot)
}

# Public cmdlets

function Get-InstalledPSLResource {
    [CmdletBinding()]
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

    return $result.ToArray()
}

Export-ModuleMember -Function @(
    'Get-InstalledPSLResource'
)
