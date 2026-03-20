Set-StrictMode -Version Latest

$script:PSLRMBuildRoot = Split-Path -Parent $PSScriptRoot
$script:PSLRMNewLine = "`n"

function Get-ChangelogSections {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Path = (Get-ChangelogPath)
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Changelog not found: $Path"
    }

    $content = Get-Content -LiteralPath $Path -Raw
    $headerPattern = '(?m)^## \[(?<Name>[^\]]+)\](?<Suffix>(?: - .+)?)\r?$'
    $headerMatches = [System.Text.RegularExpressions.Regex]::Matches($content, $headerPattern)
    $sections = [System.Collections.Generic.List[object]]::new()

    for ($index = 0; $index -lt $headerMatches.Count; $index++) {
        $headerMatch = $headerMatches[$index]
        $bodyStartIndex = $headerMatch.Index + $headerMatch.Length
        $bodyEndIndex = $content.Length

        if ($index + 1 -lt $headerMatches.Count) {
            $bodyEndIndex = $headerMatches[$index + 1].Index
        }

        $rawBody = $content.Substring($bodyStartIndex, $bodyEndIndex - $bodyStartIndex).TrimStart("`r", "`n")
        $footerMatch = [System.Text.RegularExpressions.Regex]::Match($rawBody, '(?m)^---\s*\r?$')
        if ($footerMatch.Success) {
            $rawBody = $rawBody.Substring(0, $footerMatch.Index)
        }

        $sections.Add([pscustomobject]@{
                Version = $headerMatch.Groups['Name'].Value
                Heading = $headerMatch.Value.TrimEnd("`r", "`n")
                Body = $rawBody.TrimEnd("`r", "`n")
            })
    }

    $sections.ToArray()
}

function Get-ChangelogPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    Join-Path $script:PSLRMBuildRoot 'CHANGELOG.md'
}

function Get-ChangelogSection {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Path = (Get-ChangelogPath),

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Version
    )

    $section = Get-ChangelogSections -Path $Path |
        Where-Object { $_.Version -eq $Version } |
        Select-Object -First 1

    if (-not $section) {
        throw "Changelog entry not found for version: $Version"
    }

    $section
}

function Get-ChangelogEntry {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Path = (Get-ChangelogPath),

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Version
    )

    (Get-ChangelogSection -Path $Path -Version $Version).Body
}

function Get-ManifestReleaseNotes {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Path = (Get-ChangelogPath),

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Version,

        [Parameter()]
        [ValidateRange(1, 20)]
        [int] $RecentCount = 3,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $FullChangelogUrl
    )

    $sections = Get-ChangelogSections -Path $Path
    $startIndex = -1
    for ($index = 0; $index -lt $sections.Count; $index++) {
        if ($sections[$index].Version -eq $Version) {
            $startIndex = $index
            break
        }
    }

    if ($startIndex -lt 0) {
        throw "Changelog entry not found for version: $Version"
    }

    $selectedSections = $sections | Select-Object -Skip $startIndex -First $RecentCount
    $sectionTexts = foreach ($section in $selectedSections) {
        @(
            $section.Heading
            ''
            $section.Body
        ) -join $script:PSLRMNewLine
    }

    (@(
        ($sectionTexts -join ($script:PSLRMNewLine + $script:PSLRMNewLine))
        ''
        "Full CHANGELOG: $FullChangelogUrl"
    ) -join $script:PSLRMNewLine).TrimEnd("`r", "`n")
}

function Set-ManifestReleaseNotes {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ManifestPath,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $ReleaseNotes
    )

    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw "Manifest not found: $ManifestPath"
    }

    $content = Get-Content -LiteralPath $ManifestPath -Raw
    $pattern = '(?ms)^(?<Indent>\s*)# ReleaseNotes of this module\s*\r?\n.*?(?=^\k<Indent># Prerelease string of this module\s*$)'
    $match = [System.Text.RegularExpressions.Regex]::Match($content, $pattern)
    if (-not $match.Success) {
        throw "Could not find ReleaseNotes section in manifest: $ManifestPath"
    }

    $indent = $match.Groups['Indent'].Value
    $normalizedReleaseNotes = ($ReleaseNotes -replace "`r?`n", $script:PSLRMNewLine).TrimEnd("`r", "`n")
    $replacement = @(
        "${indent}# ReleaseNotes of this module"
        "${indent}ReleaseNotes = @'"
        $normalizedReleaseNotes
        "'@"
        ''
    ) -join $script:PSLRMNewLine

    $updatedContent = $content.Substring(0, $match.Index) + $replacement + $content.Substring($match.Index + $match.Length)

    if (-not $PSCmdlet.ShouldProcess($ManifestPath, 'Update manifest ReleaseNotes')) {
        return
    }

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($ManifestPath, $updatedContent, $utf8NoBom)
}