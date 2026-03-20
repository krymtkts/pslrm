Set-StrictMode -Version Latest

$script:PSLRMBuildRoot = Split-Path -Parent $PSScriptRoot

function Get-FullModuleVersion {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [ValidateNotNull()]
        [psobject]
        $Module
    )

    $prereleaseSuffix = ''
    if ($Module.PrivateData -and $Module.PrivateData.PSData -and $Module.PrivateData.PSData['Prerelease']) {
        $prereleaseSuffix = "-$($Module.PrivateData.PSData['Prerelease'])"
    }
    $version = if ($Module.ModuleVersion) { $Module.ModuleVersion } else { $Module.Version }

    "${version}${prereleaseSuffix}"
}

function Assert-CommandAvailable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name
    )

    if (-not (Get-Command -Name $Name -ErrorAction SilentlyContinue)) {
        throw "Required command not available: $Name"
    }
}

function Invoke-TestTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $TestPath,

        [Parameter()]
        [AllowNull()]
        [string] $CoverageOutputPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $TestResultOutputPath,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $ModuleRoot = $script:PSLRMBuildRoot
    )

    $config = New-PesterConfiguration
    $config.Run.Path = @($TestPath)
    $config.Run.PassThru = $true
    $config.Output.Verbosity = 'Detailed'
    if ($CoverageOutputPath) {
        $config.CodeCoverage.Enabled = $true
        $config.CodeCoverage.Path = @(
            (Join-Path $ModuleRoot 'pslrm.psm1'),
            (Join-Path $ModuleRoot 'src\*.ps1')
        )
        $config.CodeCoverage.OutputFormat = 'JaCoCo'
        $config.CodeCoverage.OutputPath = $CoverageOutputPath
    }
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputFormat = 'NUnitXml'
    $config.TestResult.OutputPath = $TestResultOutputPath

    Push-Location $script:PSLRMBuildRoot

    $previousTestModuleRoot = $env:PSLRM_TEST_MODULE_ROOT
    try {
        $env:PSLRM_TEST_MODULE_ROOT = $ModuleRoot
        Write-Host "Invoking Pester tests for module: $ModuleRoot" -ForegroundColor Yellow
        $pesterResult = Invoke-Pester -Configuration $config

        if ($null -eq $pesterResult) {
            throw 'Invoke-Pester did not return a result object.'
        }

        if ($pesterResult.Result -ne 'Passed') {
            throw "Pester reported test failures. Result=$($pesterResult.Result); FailedCount=$($pesterResult.FailedCount)."
        }
    }
    finally {
        if ($null -eq $previousTestModuleRoot) {
            Remove-Item Env:PSLRM_TEST_MODULE_ROOT -ErrorAction SilentlyContinue
        }
        else {
            $env:PSLRM_TEST_MODULE_ROOT = $previousTestModuleRoot
        }

        Pop-Location
    }
}