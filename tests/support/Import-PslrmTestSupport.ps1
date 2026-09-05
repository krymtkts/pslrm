$sourcePath = Join-Path $PSScriptRoot 'PslrmTestSynchronization.cs'
if (-not ('PslrmTestMutexOwner' -as [type])) {
    Add-Type -Path $sourcePath -ErrorAction Stop
}
