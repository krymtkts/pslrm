Set-StrictMode -Version Latest

$filesToLoad = @(
    'src/Private.Core.ps1'
    'src/Private.PSResourceGet.ps1'
    'src/Public.ps1'
)

foreach ($relativePath in $filesToLoad) {
    $filePath = Join-Path $PSScriptRoot $relativePath
    if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
        throw "Required module source file not found: $filePath"
    }

    . $filePath
}

Export-ModuleMember -Function @(
    'Get-InstalledPSLResource',
    'Install-PSLResource',
    'Update-PSLResource',
    'Uninstall-PSLResource',
    'Restore-PSLResource'
)