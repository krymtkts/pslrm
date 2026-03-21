<#
.Synopsis
    Invoke-Build tasks
#>

# Build script parameters
[CmdletBinding(DefaultParameterSetName = 'Default')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables are used in script blocks and argument completers')]
param(
    [Parameter(Position = 0, ParameterSetName = 'Default')]
    [Parameter(Position = 0, ParameterSetName = 'Publish')]
    [ValidateSet('Init', 'Clean', 'Lint', 'Build', 'UnitTest', 'IntegrationTest', 'TestAll', 'SyncReleaseNotes', 'Stage', 'Import', 'ReleaseTestAll', 'Release')]
    [string[]] $Tasks = @('UnitTest'),

    [Parameter()]
    [switch] $DisableCoverage,

    [Parameter(ParameterSetName = 'Publish', Mandatory)]
    [switch] $PushToGallery,

    [Parameter(ParameterSetName = 'Publish', Mandatory)]
    [ValidateNotNull()]
    [securestring] $ApiKey,

    [Parameter(ParameterSetName = 'Publish', Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $ReleaseTag
)

# If invoked directly (not dot-sourced by Invoke-Build), hand off execution to Invoke-Build.
if ($MyInvocation.InvocationName -ne '.') {
    $moduleManifestPath = Join-Path $PSScriptRoot 'pslrm.psd1'
    if (-not (Test-Path -LiteralPath $moduleManifestPath -PathType Leaf)) {
        throw "Module manifest not found: $moduleManifestPath"
    }

    Import-Module -Name $moduleManifestPath -Force

    $invokeBuildArguments = @(
        $Tasks
        $PSCommandPath
    )
    if ($DisableCoverage) {
        $invokeBuildArguments += '-DisableCoverage'
    }
    if ($PushToGallery) {
        $invokeBuildArguments += '-ReleaseTag'
        $invokeBuildArguments += $ReleaseTag
        $invokeBuildArguments += '-PushToGallery'
        $invokeBuildArguments += '-ApiKey'
        $invokeBuildArguments += $ApiKey
    }

    try {
        Invoke-PSLResource -Path $PSScriptRoot -CommandName 'Invoke-Build' -ArgumentTokens $invokeBuildArguments
        exit 0
    }
    catch {
        Write-Error $_
        exit 1
    }
}

# Required PowerShell version check.
if ($PSVersionTable.PSVersion -lt [Version]'5.1') {
    throw "This build requires PowerShell 5.1+. Current: $($PSVersionTable.PSVersion)."
}

$coverageAwareTasks = @('UnitTest', 'IntegrationTest', 'TestAll', 'ReleaseTestAll', 'Release')
if ($DisableCoverage -and -not ($Tasks | Where-Object { $_ -in $coverageAwareTasks })) {
    throw '-DisableCoverage is only valid with UnitTest, IntegrationTest, TestAll, ReleaseTestAll, or Release.'
}

if ($PushToGallery -and ('Release' -notin $Tasks)) {
    throw '-PushToGallery is only valid when the Release task is requested.'
}

# --- Setup ---

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'tools\Build.Helpers.ps1')
. (Join-Path $PSScriptRoot 'tools\ReleaseNotes.Helpers.ps1')

$ModuleScript = Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.psm1' | Select-Object -First 1
if (-not $ModuleScript) {
    throw "Module script (.psm1) not found under: $PSScriptRoot"
}

$ModuleName = $ModuleScript.BaseName
$ModuleManifest = Get-Item -LiteralPath (Join-Path $PSScriptRoot "$ModuleName.psd1")
$ModuleSrcPath = (Resolve-Path (Join-Path $PSScriptRoot 'src')).Path
$TestsPath = (Resolve-Path (Join-Path $PSScriptRoot 'tests')).Path
$ToolsPath = (Resolve-Path (Join-Path $PSScriptRoot 'tools')).Path
$ModuleVersion = Import-PowerShellDataFile -Path $ModuleManifest.FullName | Get-FullModuleVersion
$ModulePublishPath = Join-Path $PSScriptRoot (Join-Path 'publish' $ModuleName)
$PublishModuleManifest = Join-Path $ModulePublishPath "${ModuleName}.psd1"
$FullChangelogUrl = 'https://github.com/krymtkts/pslrm/blob/main/CHANGELOG.md'
$ScriptAnalyzerSettingsPath = Join-Path $PSScriptRoot 'PSScriptAnalyzerSettings.psd1'

# --- Tasks (Invoke-Build) ---

Task Init {
    Write-Host "Module: ${ModuleName} ver${ModuleVersion} root=${ModuleSrcPath} publish=${ModulePublishPath}" -ForegroundColor Magenta
    Write-Host "Parameters: $($PSBoundParameters | ConvertTo-Json -Compress)" -ForegroundColor Green

    Assert-CommandAvailable -Name 'Invoke-Build'
    Assert-CommandAvailable -Name 'Invoke-ScriptAnalyzer'
    Assert-CommandAvailable -Name 'Invoke-Pester'

    if (-not (Test-Path -LiteralPath $ScriptAnalyzerSettingsPath -PathType Leaf)) {
        throw "PSScriptAnalyzer settings file not found: $ScriptAnalyzerSettingsPath"
    }

    New-Item -ItemType Directory -Path $ModulePublishPath -Force | Out-Null
}

Task Clean Init, {
    Write-Host 'Cleaning build artifacts.' -ForegroundColor Yellow

    if (Test-Path -LiteralPath $ModulePublishPath -PathType Container) {
        Remove-Item -LiteralPath $ModulePublishPath -Recurse -Force
    }

    @('testResults*.xml', 'coverage*.xml') | ForEach-Object {
        Get-ChildItem -LiteralPath $PSScriptRoot -Filter $_ -File -ErrorAction SilentlyContinue
    } | Remove-Item -Force
}

Task Build Clean, {
    Write-Host 'Building module.' -ForegroundColor Yellow

    Test-ModuleManifest -Path $ModuleManifest.FullName -ErrorAction Stop | Format-List
    if (-not (Test-Path -LiteralPath $ModuleSrcPath -PathType Container)) {
        throw "Module source directory not found: $ModuleSrcPath"
    }
}

Task Lint Build, {
    Write-Host 'Running PSScriptAnalyzer.' -ForegroundColor Yellow

    # PowerShell script analysis.
    $issues = @(
        @(
            (Join-Path $PSScriptRoot '.build.ps1'),
            $ToolsPath,
            $ModuleScript.FullName,
            $ModuleSrcPath,
            $TestsPath
        ) | Invoke-ScriptAnalyzer -Recurse -Settings $ScriptAnalyzerSettingsPath
    )
    if ($issues.Count -gt 0) {
        $issues
        throw 'Invoke-ScriptAnalyzer reported issues.'
    }
}

Task UnitTest Lint, {
    Write-Host 'Running unit tests.' -ForegroundColor Yellow

    $Params = @{
        TestPath = 'tests/unit'
        TestResultOutputPath = 'testResults.xml'
    }
    if (-not $DisableCoverage) {
        $Params.CoverageOutputPath = 'coverage.xml'

    }
    Invoke-TestTask @Params
}

Task IntegrationTest Build, {
    Write-Host 'Running integration tests.' -ForegroundColor Yellow

    $Params = @{
        TestPath = 'tests/integration'
        TestResultOutputPath = 'testResults.integration.xml'
    }
    if (-not $DisableCoverage) {
        $Params.CoverageOutputPath = 'coverage.integration.xml'
    }
    Invoke-TestTask @Params
}

Task TestAll UnitTest, IntegrationTest

Task SyncReleaseNotes Build, {
    Write-Host 'Syncing module manifest ReleaseNotes from CHANGELOG.md.' -ForegroundColor Yellow

    $releaseNotes = Get-ManifestReleaseNotes -Version $ModuleVersion -FullChangelogUrl $FullChangelogUrl
    Set-ManifestReleaseNotes -ManifestPath $ModuleManifest.FullName -ReleaseNotes $releaseNotes
}

Task ReleaseTestAll Import, {
    Write-Host 'Running release tests against staged module artifacts.' -ForegroundColor Yellow

    $Params = @{
        TestPath = 'tests/unit'
        TestResultOutputPath = 'testResults.release.xml'
        ModuleRoot = $ModulePublishPath
    }
    if (-not $DisableCoverage) {
        $Params.CoverageOutputPath = 'coverage.release.xml'
    }
    Invoke-TestTask @Params
    $IntegrationTestParams = @{
        TestPath = 'tests/integration'
        TestResultOutputPath = 'testResults.integration.release.xml'
        ModuleRoot = $ModulePublishPath
    }
    if (-not $DisableCoverage) {
        $IntegrationTestParams.CoverageOutputPath = 'coverage.integration.release.xml'
    }
    Invoke-TestTask @IntegrationTestParams
}

Task Stage Build, {
    Write-Host "Staging module for release at $PublishModuleManifest." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $ModulePublishPath -Force | Out-Null

    Copy-Item -LiteralPath $ModuleManifest.FullName -Destination $PublishModuleManifest -Force
    Copy-Item -LiteralPath $ModuleScript.FullName -Destination (Join-Path $ModulePublishPath $ModuleScript.Name) -Force
    Copy-Item -LiteralPath $ModuleSrcPath -Destination (Join-Path $ModulePublishPath 'src') -Recurse -Force
}

Task Import Stage, {
    Write-Host "Importing module $PublishModuleManifest" -ForegroundColor Yellow

    Remove-Module -Name $ModuleName -Force -ErrorAction SilentlyContinue
    Import-Module -Name $PublishModuleManifest -Force
    $module = Get-Module -Name $ModuleName
    if (-not $module) {
        throw "Failed to import module: $PublishModuleManifest"
    }
    else {
        $module | Format-List
        Write-Host "Successfully imported module: $($module.Name) version $($module.Version)" -ForegroundColor Green
    }
}

Task ValidateReleaseMetadata Build, {
    Write-Host 'Validating release metadata.' -ForegroundColor Yellow

    Assert-ReleaseMetadata -Version $ModuleVersion -ReleaseTag $ReleaseTag
}

Task Release ValidateReleaseMetadata, ReleaseTestAll, {
    Write-Host "Releasing module $ModulePublishPath" -ForegroundColor Magenta

    if (-not (Test-Path -LiteralPath $PublishModuleManifest -PathType Leaf)) {
        throw "Publish manifest not found. Run Stage before Release: $PublishModuleManifest"
    }

    Write-Host "Release ${ModuleName}! version=${ModuleVersion} dryrun=$(-not $PushToGallery)" -ForegroundColor Magenta

    $module = Import-PowerShellDataFile $PublishModuleManifest
    $ManifestModuleVersion = $module | Get-FullModuleVersion
    if ($ManifestModuleVersion -ne $ModuleVersion) {
        throw "Version inconsistency between staged manifest and project manifest. Staged: ${ManifestModuleVersion}, Project: ${ModuleVersion}"
    }

    $Params = @{
        Path = $ModulePublishPath
        Repository = 'PSGallery'
        WhatIf = -not $PushToGallery
        Verbose = $true
    }
    if ($PushToGallery) {
        $Params.ApiKey = ConvertFrom-SecureStringToPlainText -SecureString $ApiKey
    }
    Publish-PSResource @Params
}

Task . UnitTest

