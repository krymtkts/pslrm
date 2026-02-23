Set-StrictMode -Version Latest

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
