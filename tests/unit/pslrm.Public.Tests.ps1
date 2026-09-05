BeforeAll {
    $moduleRoot = if (-not [string]::IsNullOrWhiteSpace($env:PSLRM_TEST_MODULE_ROOT)) {
        $env:PSLRM_TEST_MODULE_ROOT
    }
    else {
        (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    }

    $modulePath = Join-Path $moduleRoot 'pslrm.psd1'
    Import-Module $modulePath -Force

    . (Join-Path $PSScriptRoot '..\support\Import-PslrmTestSupport.ps1')

    InModuleScope pslrm {
        function script:New-TestStoreModule {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [string] $ProjectRoot,

                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [string] $ModuleName,

                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [string] $CommandName,

                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [string] $ModuleBody,

                [Parameter()]
                [ValidateNotNullOrEmpty()]
                [string] $Version = '1.0.0',

                [Parameter()]
                [AllowNull()]
                [string[]] $RequiredModules
            )

            $moduleRoot = Join-Path $ProjectRoot ".pslrm\$ModuleName\$Version"
            New-Item -ItemType Directory -Path $moduleRoot -Force | Out-Null

            $manifestPath = Join-Path $moduleRoot "$ModuleName.psd1"
            $modulePath = Join-Path $moduleRoot "$ModuleName.psm1"
            $utf8NoBom = [System.Text.UTF8Encoding]::new($false)

            [System.IO.File]::WriteAllText($modulePath, $ModuleBody, $utf8NoBom)

            $requiredModuleNames = @(
                $RequiredModules |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            )
            $manifestContent = [System.Collections.Generic.List[string]]::new()
            $manifestContent.Add('@{')
            $manifestContent.Add("    RootModule = '$ModuleName.psm1'")
            $manifestContent.Add("    ModuleVersion = '$Version'")
            $manifestContent.Add("    GUID = '$([guid]::NewGuid())'")
            $manifestContent.Add("    FunctionsToExport = @('$CommandName')")

            if ($requiredModuleNames.Count -gt 0) {
                $manifestContent.Add('    RequiredModules = @(')
                foreach ($requiredModuleName in $requiredModuleNames) {
                    $manifestContent.Add("        '$requiredModuleName'")
                }
                $manifestContent.Add('    )')
            }

            $manifestContent.Add('}')
            $manifestContent.Add('')

            [System.IO.File]::WriteAllText($manifestPath, ($manifestContent.ToArray() -join "`n"), $utf8NoBom)
        }

        function script:New-TestPSResourceInfo {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [string] $Name,

                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [string] $Version,

                [Parameter()]
                [AllowNull()]
                [string] $Prerelease,

                [Parameter()]
                [ValidateNotNullOrEmpty()]
                [string] $Repository = 'PSGallery'
            )

            $type = [Microsoft.PowerShell.PSResourceGet.UtilClasses.PSResourceInfo]
            $flags = [System.Reflection.BindingFlags]'Instance,NonPublic'
            $ctor = $type.GetConstructors($flags) | Where-Object { $_.GetParameters().Count -eq 24 } | Select-Object -First 1
            if ($null -eq $ctor) {
                throw 'Failed to locate a non-public PSResourceInfo constructor for tests.'
            }

            $includesType = [Microsoft.PowerShell.PSResourceGet.UtilClasses.ResourceIncludes]
            $includes = [System.Activator]::CreateInstance($includesType, $true)
            $deps = [Microsoft.PowerShell.PSResourceGet.UtilClasses.Dependency[]]@()
            $metadata = [System.Collections.Generic.Dictionary[string, string]]::new()

            $isPrerelease = -not [string]::IsNullOrWhiteSpace($Prerelease)
            $versionObj = [version]$Version

            return [Microsoft.PowerShell.PSResourceGet.UtilClasses.PSResourceInfo]$ctor.Invoke(@(
                    $metadata,
                    $null,
                    $null,
                    $null,
                    $deps,
                    $null,
                    $null,
                    $includes,
                    $null,
                    $null,
                    $isPrerelease,
                    $null,
                    $Name,
                    '3.0.0',
                    $Prerelease,
                    $null,
                    $null,
                    $null,
                    $Repository,
                    $null,
                    [string[]]@(),
                    [Microsoft.PowerShell.PSResourceGet.UtilClasses.ResourceType]::Module,
                    $null,
                    $versionObj
                ))
        }
    }
}

Describe 'Public manifest import' {
    It 'allows invoking exported commands outside InModuleScope' {
        $root = Join-Path $TestDrive 'proj-public-manifest'
        New-Item -ItemType Directory -Path $root -Force | Out-Null

        $requirementsContent = @(
            '@{'
            "    'Pester' = @{"
            "        'Repository' = 'PSGallery'"
            '    }'
            '}'
            ''
        ) -join "`n"

        [System.IO.File]::WriteAllText(
            (Join-Path $root 'psreq.psd1'),
            $requirementsContent,
            [System.Text.UTF8Encoding]::new($false)
        )

        { Install-PSLResource -Path $root -WhatIf } | Should -Not -Throw
    }
}

Describe 'Invoke-PSLResource' {
    It 'exposes explicit and natural argument parameter sets' {
        $parameterSets = (Get-Command -Name 'Invoke-PSLResource').ParameterSets
        $parameterSets.Name | Should -Contain 'Explicit'
        $parameterSets.Name | Should -Contain 'Natural'

        $naturalParameters = ($parameterSets | Where-Object Name -EQ 'Natural').Parameters
        ($naturalParameters | Where-Object Name -EQ 'CommandName').Position | Should -Be 0
        ($naturalParameters | Where-Object Name -EQ 'RemainingArgumentTokens').Position | Should -Be 1
        ($naturalParameters | Where-Object Name -EQ 'RemainingArgumentTokens').ValueFromRemainingArguments | Should -BeTrue

        $explicitParameters = ($parameterSets | Where-Object Name -EQ 'Explicit').Parameters
        ($explicitParameters | Where-Object Name -EQ 'ArgumentTokens').Aliases | Should -Contain 'Arguments'
    }

    It 'forwards natural arguments after the end-of-parameters token' {
        InModuleScope pslrm {
            Mock Find-ProjectRoot { 'C:\project' }
            Mock Invoke-InIsolatedRunspace {
                $script:capturedInvocation = [pscustomobject]@{
                    ProjectRoot = $ProjectRoot
                    CommandName = $CommandName
                    ArgumentTokens = $ArgumentTokens
                }
            }

            Invoke-PSLResource -Path . Invoke-Probe -- -Path child -ExecutionScope Child -Enabled $false -Count -1 -Verbose

            $script:capturedInvocation.ProjectRoot | Should -BeExactly 'C:\project'
            $script:capturedInvocation.CommandName | Should -BeExactly 'Invoke-Probe'
            $script:capturedInvocation.ArgumentTokens | Should -Be @(
                '-Path',
                'child',
                '-ExecutionScope',
                'Child',
                '-Enabled',
                $false,
                '-Count',
                -1,
                '-Verbose'
            )
        }
    }

    # NOTE: Windows PowerShell 5.1 passes this collection with an extra outer array, while PowerShell 7 passes the flat collection directly.
    It 'normalizes positional arrays across PowerShell argument binding behaviors' {
        InModuleScope pslrm {
            Mock Find-ProjectRoot { 'C:\project' }
            Mock Invoke-InIsolatedRunspace {
                $script:capturedArgumentTokens = $ArgumentTokens
            }

            $argumentTokens = '-Task', 'TestAll'
            Invoke-PSLResource Invoke-Probe $argumentTokens

            $script:capturedArgumentTokens | Should -Be @('-Task', 'TestAll')
        }
    }

    It 'normalizes typed collections across PowerShell argument binding behaviors' {
        InModuleScope pslrm {
            Mock Find-ProjectRoot { 'C:\project' }
            Mock Invoke-InIsolatedRunspace {
                $script:capturedArgumentTokens = $ArgumentTokens
            }

            $collections = [object[]]::new(2)
            $collections[0] = [int[]] @(1, 2)
            $collections[1] = [System.Collections.Generic.List[string]] @('one', 'two')

            foreach ($collection in $collections) {
                Invoke-PSLResource Invoke-Probe $collection

                $script:capturedArgumentTokens.Count | Should -Be 2
                $script:capturedArgumentTokens | Should -Be @($collection)
            }
        }
    }

    It 'preserves a hashtable as a scalar natural argument' {
        InModuleScope pslrm {
            Mock Find-ProjectRoot { 'C:\project' }
            Mock Invoke-InIsolatedRunspace {
                $script:capturedArgumentTokens = $ArgumentTokens
            }

            $hashtable = @{ Name = 'value' }

            Invoke-PSLResource Invoke-Probe $hashtable

            $script:capturedArgumentTokens.Count | Should -Be 1
            [object]::ReferenceEquals($script:capturedArgumentTokens[0], $hashtable) | Should -BeTrue
        }
    }

    # NOTE: This verifies that the pre-6.2 outer array is removed exactly once and that current PowerShell input is not unwrapped.
    It 'preserves a nested array in natural arguments' {
        InModuleScope pslrm {
            Mock Find-ProjectRoot { 'C:\project' }
            Mock Invoke-InIsolatedRunspace {
                $script:capturedArgumentTokens = $ArgumentTokens
            }

            $nestedArray = @('one', 'two')
            $remainingArguments = [object[]]::new(1)
            $remainingArguments[0] = $nestedArray

            Invoke-PSLResource Invoke-Probe $remainingArguments

            $script:capturedArgumentTokens.Count | Should -Be 1
            [object]::ReferenceEquals($script:capturedArgumentTokens[0], $nestedArray) | Should -BeTrue
            $script:capturedArgumentTokens[0] | Should -Be @('one', 'two')
        }
    }

    It 'supports natural invocation without arguments' {
        InModuleScope pslrm {
            Mock Find-ProjectRoot { 'C:\project' }
            Mock Invoke-InIsolatedRunspace {
                $script:capturedArgumentTokens = $ArgumentTokens
            }

            Invoke-PSLResource Invoke-Probe

            $script:capturedArgumentTokens | Should -BeNullOrEmpty
        }
    }

    It 'preserves explicit object and nested array arguments' {
        InModuleScope pslrm {
            Mock Find-ProjectRoot { 'C:\project' }
            Mock Invoke-InIsolatedRunspace {
                $script:capturedArgumentTokens = $ArgumentTokens
            }

            $hashtable = @{ Name = 'value' }
            $scriptBlock = { 'value' }
            $nestedArray = @('one', 'two')
            $argumentTokens = [object[]]::new(4)
            $argumentTokens[0] = $hashtable
            $argumentTokens[1] = $scriptBlock
            $argumentTokens[2] = $nestedArray
            $argumentTokens[3] = $null

            Invoke-PSLResource -CommandName Invoke-Probe -ArgumentTokens $argumentTokens

            $script:capturedArgumentTokens.Count | Should -Be 4
            [object]::ReferenceEquals($script:capturedArgumentTokens[0], $hashtable) | Should -BeTrue
            [object]::ReferenceEquals($script:capturedArgumentTokens[1], $scriptBlock) | Should -BeTrue
            [object]::ReferenceEquals($script:capturedArgumentTokens[2], $nestedArray) | Should -BeTrue
            $script:capturedArgumentTokens[2] | Should -Be @('one', 'two')
            $script:capturedArgumentTokens[3] | Should -BeNullOrEmpty
        }
    }

    It 'invokes a local command in an isolated runspace and preserves named arguments' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj-invoke-success'
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            Write-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1') -Data @{ LocalEchoModule = @{ Repository = 'PSGallery' } }
            Write-Lockfile -Path (Join-Path $root 'psreq.lock.psd1') -Data @{ LocalEchoModule = @{ Version = '1.0.0'; Repository = 'PSGallery' } }

            New-TestStoreModule -ProjectRoot $root -ModuleName 'LocalEchoModule' -CommandName 'Invoke-LocalEcho' -ModuleBody @'
function Invoke-LocalEcho {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $First,

        [Parameter()]
        [string] $Second
    )

    [pscustomobject]@{
        First = $First
        Second = $Second
        Module = $MyInvocation.MyCommand.Module.Name
    }
}

Export-ModuleMember -Function 'Invoke-LocalEcho'
'@

            Get-Module -Name 'LocalEchoModule' | Should -BeNullOrEmpty

            $actual = Invoke-PSLResource -Path $root -CommandName 'Invoke-LocalEcho' -Arguments @('-First', 'one', '-Second', 'two')

            $actual.First | Should -BeExactly 'one'
            $actual.Second | Should -BeExactly 'two'
            $actual.Module | Should -BeExactly 'LocalEchoModule'
            Get-Module -Name 'LocalEchoModule' | Should -BeNullOrEmpty
        }
    }

    It 'restores the process module path before executing the target command' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj-invoke-module-path'
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            Write-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1') -Data @{ ModulePathProbe = @{ Repository = 'PSGallery' } }
            Write-Lockfile -Path (Join-Path $root 'psreq.lock.psd1') -Data @{ ModulePathProbe = @{ Version = '1.0.0'; Repository = 'PSGallery' } }

            New-TestStoreModule -ProjectRoot $root -ModuleName 'ModulePathProbe' -CommandName 'Get-ModulePathProbe' -ModuleBody @'
function Get-ModulePathProbe {
    [Environment]::GetEnvironmentVariable('PSModulePath', 'Process')
}

Export-ModuleMember -Function 'Get-ModulePathProbe'
'@

            $originalModulePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'Process')
            $expectedModulePath = "pslrm-test-original-$PID"

            try {
                [Environment]::SetEnvironmentVariable('PSModulePath', $expectedModulePath, 'Process')
                $observedModulePath = [string](Invoke-PSLResource -Path $root -CommandName 'Get-ModulePathProbe')
                $observedModulePath | Should -BeExactly $expectedModulePath
                [Environment]::GetEnvironmentVariable('PSModulePath', 'Process') |
                    Should -BeExactly $expectedModulePath
            }
            finally {
                [Environment]::SetEnvironmentVariable('PSModulePath', $originalModulePath, 'Process')
            }
        }
    }

    It 'serializes module path changes across isolated module instances' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj-invoke-module-path-concurrent'
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            Write-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1') -Data @{ ConcurrentModulePathProbe = @{ Repository = 'PSGallery' } }
            Write-Lockfile -Path (Join-Path $root 'psreq.lock.psd1') -Data @{ ConcurrentModulePathProbe = @{ Version = '1.0.0'; Repository = 'PSGallery' } }

            New-TestStoreModule -ProjectRoot $root -ModuleName 'ConcurrentModulePathProbe' -CommandName 'Get-ConcurrentModulePathValue' -ModuleBody @'
[PslrmTestImportProbe]::EnterImport()

function Get-ConcurrentModulePathValue {
    'ok'
}

Export-ModuleMember -Function 'Get-ConcurrentModulePathValue'
'@

            [PslrmTestImportProbe]::Reset()
            $originalModulePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'Process')
            $expectedModulePath = "pslrm-test-concurrent-original-$PID"
            $modulePath = (Get-Module -Name pslrm).Path
            $powerShells = @(
                [System.Management.Automation.PowerShell]::Create()
                [System.Management.Automation.PowerShell]::Create()
            )
            $asyncResults = @($null, $null)
            $ended = @($false, $false)

            try {
                $powerShells[0].AddScript(@'
param(
    [string] $ModulePath,
    [string] $ProjectRoot
)

Import-Module -Name $ModulePath -Force
[PslrmTestImportProbe]::FirstInvocationReady.Set()
[PslrmTestImportProbe]::ReleaseInvocations.Wait()
Invoke-PSLResource -Path $ProjectRoot -CommandName 'Get-ConcurrentModulePathValue'
'@).AddParameter('ModulePath', $modulePath).AddParameter('ProjectRoot', $root) | Out-Null

                $powerShells[1].AddScript(@'
param(
    [string] $ModulePath,
    [string] $ProjectRoot
)

Import-Module -Name $ModulePath -Force
[PslrmTestImportProbe]::SecondInvocationReady.Set()
[PslrmTestImportProbe]::ReleaseInvocations.Wait()
Invoke-PSLResource -Path $ProjectRoot -CommandName 'Get-ConcurrentModulePathValue'
'@).AddParameter('ModulePath', $modulePath).AddParameter('ProjectRoot', $root) | Out-Null

                $asyncResults[0] = $powerShells[0].BeginInvoke()
                [PslrmTestImportProbe]::FirstInvocationReady.Wait(5000) | Should -BeTrue
                $asyncResults[1] = $powerShells[1].BeginInvoke()
                [PslrmTestImportProbe]::SecondInvocationReady.Wait(5000) | Should -BeTrue

                [Environment]::SetEnvironmentVariable('PSModulePath', $expectedModulePath, 'Process')
                [PslrmTestImportProbe]::ReleaseInvocations.Set()

                $firstImportEntered = [PslrmTestImportProbe]::FirstImportEntered.Wait(5000)
                if (-not $firstImportEntered) {
                    throw 'The first test import did not start.'
                }

                [PslrmTestImportProbe]::SecondImportEntered.Wait(1000) | Should -BeFalse

                [PslrmTestImportProbe]::ReleaseImports.Set()
                foreach ($asyncResult in $asyncResults) {
                    $asyncResult.AsyncWaitHandle.WaitOne(5000) | Should -BeTrue
                }

                for ($index = 0; $index -lt $powerShells.Count; $index++) {
                    $output = @($powerShells[$index].EndInvoke($asyncResults[$index]))
                    $ended[$index] = $true
                    $powerShells[$index].Streams.Error | Should -BeNullOrEmpty
                    $output | Should -BeExactly @('ok')
                }

                [PslrmTestImportProbe]::GetMaxActiveImportCount() | Should -Be 1
                [Environment]::GetEnvironmentVariable('PSModulePath', 'Process') |
                    Should -BeExactly $expectedModulePath
            }
            finally {
                [PslrmTestImportProbe]::ReleaseInvocations.Set()
                [PslrmTestImportProbe]::ReleaseImports.Set()
                for ($index = 0; $index -lt $powerShells.Count; $index++) {
                    if ($null -ne $asyncResults[$index] -and -not $ended[$index]) {
                        try {
                            if ($asyncResults[$index].AsyncWaitHandle.WaitOne(5000)) {
                                $powerShells[$index].EndInvoke($asyncResults[$index]) | Out-Null
                            }
                            else {
                                $powerShells[$index].Stop()
                            }
                        }
                        catch {
                        }
                    }
                    $powerShells[$index].Dispose()
                }
                [PslrmTestImportProbe]::Reset()
                [Environment]::SetEnvironmentVariable('PSModulePath', $originalModulePath, 'Process')
            }
        }
    }

    It 'invokes the locked version when a newer user-wide module has the same name' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj-invoke-locked-direct'
            $userRoot = Join-Path $TestDrive 'user-invoke-locked-direct'
            New-Item -ItemType Directory -Path $root, $userRoot -Force | Out-Null

            Write-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1') -Data @{ LockedDirectModule = @{ Repository = 'PSGallery' } }
            Write-Lockfile -Path (Join-Path $root 'psreq.lock.psd1') -Data @{ LockedDirectModule = @{ Version = '1.0.0'; Repository = 'PSGallery' } }

            New-TestStoreModule -ProjectRoot $root -ModuleName 'LockedDirectModule' -CommandName 'Get-LockedDirectValue' -ModuleBody @'
function Get-LockedDirectValue {
    'locked'
}

Export-ModuleMember -Function 'Get-LockedDirectValue'
'@

            New-TestStoreModule -ProjectRoot $userRoot -ModuleName 'LockedDirectModule' -CommandName 'Get-LockedDirectValue' -Version '2.0.0' -ModuleBody @'
function Get-LockedDirectValue {
    'newer-user-wide'
}

Export-ModuleMember -Function 'Get-LockedDirectValue'
'@

            $originalModulePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'Process')
            $separator = [string][System.IO.Path]::PathSeparator
            $userStorePath = Join-Path $userRoot '.pslrm'
            $modulePath = if ([string]::IsNullOrWhiteSpace($originalModulePath)) {
                $userStorePath
            }
            else {
                $userStorePath, $originalModulePath -join $separator
            }

            try {
                [Environment]::SetEnvironmentVariable('PSModulePath', $modulePath, 'Process')
                Invoke-PSLResource -Path $root -CommandName 'Get-LockedDirectValue' | Should -BeExactly 'locked'
            }
            finally {
                [Environment]::SetEnvironmentVariable('PSModulePath', $originalModulePath, 'Process')
            }
        }
    }

    It 'resolves a locked transitive dependency instead of a newer user-wide module' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj-invoke-locked-transitive'
            $userRoot = Join-Path $TestDrive 'user-invoke-locked-transitive'
            New-Item -ItemType Directory -Path $root, $userRoot -Force | Out-Null

            Write-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1') -Data @{
                ALockedParentModule = @{ Repository = 'PSGallery' }
                ZLockedDependencyModule = @{ Repository = 'PSGallery' }
            }
            Write-Lockfile -Path (Join-Path $root 'psreq.lock.psd1') -Data @{
                ALockedParentModule = @{ Version = '1.0.0'; Repository = 'PSGallery' }
                ZLockedDependencyModule = @{ Version = '1.0.0'; Repository = 'PSGallery' }
            }

            New-TestStoreModule -ProjectRoot $root -ModuleName 'ZLockedDependencyModule' -CommandName 'Get-LockedDependencyValue' -ModuleBody @'
function Get-LockedDependencyValue {
    'locked-dependency'
}

Export-ModuleMember -Function 'Get-LockedDependencyValue'
'@

            New-TestStoreModule -ProjectRoot $root -ModuleName 'ALockedParentModule' -CommandName 'Get-LockedParentValue' -RequiredModules @('ZLockedDependencyModule') -ModuleBody @'
function Get-LockedParentValue {
    Get-LockedDependencyValue
}

Export-ModuleMember -Function 'Get-LockedParentValue'
'@

            New-TestStoreModule -ProjectRoot $userRoot -ModuleName 'ZLockedDependencyModule' -CommandName 'Get-LockedDependencyValue' -Version '2.0.0' -ModuleBody @'
function Get-LockedDependencyValue {
    'newer-user-wide-dependency'
}

Export-ModuleMember -Function 'Get-LockedDependencyValue'
'@

            $originalModulePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'Process')
            $separator = [string][System.IO.Path]::PathSeparator
            $userStorePath = Join-Path $userRoot '.pslrm'
            $modulePath = if ([string]::IsNullOrWhiteSpace($originalModulePath)) {
                $userStorePath
            }
            else {
                $userStorePath, $originalModulePath -join $separator
            }

            try {
                [Environment]::SetEnvironmentVariable('PSModulePath', $modulePath, 'Process')
                Invoke-PSLResource -Path $root -CommandName 'Get-LockedParentValue' | Should -BeExactly 'locked-dependency'
            }
            finally {
                [Environment]::SetEnvironmentVariable('PSModulePath', $originalModulePath, 'Process')
            }
        }
    }

    It 'preserves trailing parameter-like tokens when using ArgumentTokens' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj-invoke-argument-tokens-trailing-switch'
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            Write-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1') -Data @{ LocalForwardModule = @{ Repository = 'PSGallery' } }
            Write-Lockfile -Path (Join-Path $root 'psreq.lock.psd1') -Data @{ LocalForwardModule = @{ Version = '1.0.0'; Repository = 'PSGallery' } }

            New-TestStoreModule -ProjectRoot $root -ModuleName 'LocalForwardModule' -CommandName 'Invoke-ForwardedBuildLikeCommand' -ModuleBody @'
function Invoke-ForwardedBuildLikeCommand {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $Task,

        [Parameter(Position = 0)]
        [string] $Path,

        [Parameter(ValueFromRemainingArguments)]
        [object[]] $RemainingArguments
    )

    [pscustomobject]@{
        Task = $Task
        Path = $Path
        RemainingArguments = @($RemainingArguments)
    }
}

Export-ModuleMember -Function 'Invoke-ForwardedBuildLikeCommand'
'@

            $actual = Invoke-PSLResource -Path $root -CommandName 'Invoke-ForwardedBuildLikeCommand' -ArgumentTokens @(
                '-Task',
                'UnitTest',
                '.build.ps1',
                '-DisableCoverage'
            )

            $actual.Task | Should -BeExactly 'UnitTest'
            $actual.Path | Should -BeExactly '.build.ps1'
            $actual.RemainingArguments | Should -Be @('-DisableCoverage')

            $naturalActual = Invoke-PSLResource -Path $root Invoke-ForwardedBuildLikeCommand -- -Task UnitTest '.build.ps1' -DisableCoverage

            $naturalActual.Task | Should -BeExactly 'UnitTest'
            $naturalActual.Path | Should -BeExactly '.build.ps1'
            $naturalActual.RemainingArguments | Should -Be @('-DisableCoverage')
        }
    }

    It 'treats inline boolean tokens as self-contained values' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj-invoke-argument-tokens-inline-bool'
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            Write-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1') -Data @{ LocalBooleanModule = @{ Repository = 'PSGallery' } }
            Write-Lockfile -Path (Join-Path $root 'psreq.lock.psd1') -Data @{ LocalBooleanModule = @{ Version = '1.0.0'; Repository = 'PSGallery' } }

            New-TestStoreModule -ProjectRoot $root -ModuleName 'LocalBooleanModule' -CommandName 'Invoke-InlineBooleanProbe' -ModuleBody @'
function Invoke-InlineBooleanProbe {
    [CmdletBinding()]
    param(
        [Parameter()]
        [bool] $Enabled,

        [Parameter(Position = 0)]
        [string] $Path,

        [Parameter(ValueFromRemainingArguments)]
        [object[]] $RemainingArguments
    )

    [pscustomobject]@{
        Enabled = $Enabled
        Path = $Path
        RemainingArguments = @($RemainingArguments)
    }
}

Export-ModuleMember -Function 'Invoke-InlineBooleanProbe'
'@

            $actual = Invoke-PSLResource -Path $root -CommandName 'Invoke-InlineBooleanProbe' -ArgumentTokens @(
                '-Enabled:$false',
                '.build.ps1',
                '-DisableCoverage'
            )

            $actual.Enabled | Should -BeFalse
            $actual.Path | Should -BeExactly '.build.ps1'
            $actual.RemainingArguments | Should -Be @('-DisableCoverage')

            $naturalActual = Invoke-PSLResource -Path $root Invoke-InlineBooleanProbe -- -Enabled $false '.build.ps1' -DisableCoverage

            $naturalActual.Enabled | Should -BeFalse
            $naturalActual.Path | Should -BeExactly '.build.ps1'
            $naturalActual.RemainingArguments | Should -Be @('-DisableCoverage')
        }
    }

    It 'treats negative numeric tokens as values instead of parameters' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj-invoke-argument-tokens-negative-number'
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            Write-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1') -Data @{ LocalNumberModule = @{ Repository = 'PSGallery' } }
            Write-Lockfile -Path (Join-Path $root 'psreq.lock.psd1') -Data @{ LocalNumberModule = @{ Version = '1.0.0'; Repository = 'PSGallery' } }

            New-TestStoreModule -ProjectRoot $root -ModuleName 'LocalNumberModule' -CommandName 'Invoke-NegativeNumberProbe' -ModuleBody @'
function Invoke-NegativeNumberProbe {
    [CmdletBinding()]
    param(
        [Parameter()]
        [int] $Count,

        [Parameter(Position = 0)]
        [string] $Path
    )

    [pscustomobject]@{
        Count = $Count
        Path = $Path
    }
}

Export-ModuleMember -Function 'Invoke-NegativeNumberProbe'
'@

            $actual = Invoke-PSLResource -Path $root -CommandName 'Invoke-NegativeNumberProbe' -ArgumentTokens @(
                '-Count',
                '-1',
                '.build.ps1'
            )

            $actual.Count | Should -Be -1
            $actual.Path | Should -BeExactly '.build.ps1'

            $naturalActual = Invoke-PSLResource -Path $root Invoke-NegativeNumberProbe -- -Count -1 '.build.ps1'

            $naturalActual.Count | Should -Be -1
            $naturalActual.Path | Should -BeExactly '.build.ps1'
        }
    }

    It 'resolves relative paths from the project root inside the isolated runspace' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj-invoke-relative-path'
            $src = Join-Path $root 'src'
            New-Item -ItemType Directory -Path $src -Force | Out-Null

            Write-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1') -Data @{ LocalPathModule = @{ Repository = 'PSGallery' } }
            Write-Lockfile -Path (Join-Path $root 'psreq.lock.psd1') -Data @{ LocalPathModule = @{ Version = '1.0.0'; Repository = 'PSGallery' } }

            [System.IO.File]::WriteAllText(
                (Join-Path $src 'message.txt'),
                'relative-ok',
                [System.Text.UTF8Encoding]::new($false)
            )

            New-TestStoreModule -ProjectRoot $root -ModuleName 'LocalPathModule' -CommandName 'Get-RelativeFileContent' -ModuleBody @'
function Get-RelativeFileContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    Get-Content -LiteralPath $Path -Raw
}

Export-ModuleMember -Function 'Get-RelativeFileContent'
'@

            $actual = Invoke-PSLResource -Path $root -CommandName 'Get-RelativeFileContent' -Arguments @('-Path', '.\src\message.txt')

            $actual.TrimEnd("`r", "`n") | Should -BeExactly 'relative-ok'
        }
    }

    It 'forwards host information records without failing on reserved tags' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj-invoke-write-host'
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            Write-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1') -Data @{ LocalHostModule = @{ Repository = 'PSGallery' } }
            Write-Lockfile -Path (Join-Path $root 'psreq.lock.psd1') -Data @{ LocalHostModule = @{ Version = '1.0.0'; Repository = 'PSGallery' } }

            New-TestStoreModule -ProjectRoot $root -ModuleName 'LocalHostModule' -CommandName 'Invoke-HostMessage' -ModuleBody @'
function Invoke-HostMessage {
    [CmdletBinding()]
    param()

    Write-Host 'hello from isolated runspace'
    'ok'
}

Export-ModuleMember -Function 'Invoke-HostMessage'
'@

            $actual = @(Invoke-PSLResource -Path $root -CommandName 'Invoke-HostMessage' 6>&1)
            # NOTE: write output and host information records are interleaved, so we check them together here.
            $actual | Should -Contain 'ok'
        }
    }

    It 'shares the caller host for top-level coverage-style host messages' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj-invoke-host-aware-output'
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            Write-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1') -Data @{ LocalHostAwareModule = @{ Repository = 'PSGallery' } }
            Write-Lockfile -Path (Join-Path $root 'psreq.lock.psd1') -Data @{ LocalHostAwareModule = @{ Version = '1.0.0'; Repository = 'PSGallery' } }

            New-TestStoreModule -ProjectRoot $root -ModuleName 'LocalHostAwareModule' -CommandName 'Invoke-HostAwareOutputProbe' -ModuleBody @'
function Invoke-HostAwareOutputProbe {
    [CmdletBinding()]
    param()

    $script:SafeCommands = @{
        'Write-Host' = Get-Command -Name 'Write-Host' -Module 'Microsoft.PowerShell.Utility'
    }

    function Write-HostMessage {
        [CmdletBinding()]
        param(
            [Parameter(Position = 0, ValueFromPipeline = $true)]
            [Alias('Message', 'Msg')]
            $Object,

            [ConsoleColor]
            $ForegroundColor,

            [switch]
            $NoNewLine
        )

        process {
            & $script:SafeCommands['Write-Host'] @PSBoundParameters
        }
    }

    Write-HostMessage -ForegroundColor Magenta 'coverage-host-output'

    'ok'
}

Export-ModuleMember -Function 'Invoke-HostAwareOutputProbe'
'@

            $actual = @(Invoke-PSLResource -Path $root -CommandName 'Invoke-HostAwareOutputProbe' 6>&1)

            @(
                $actual | Where-Object {
                    $_ -isnot [System.Management.Automation.InformationRecord]
                }
            ) | Should -Contain 'ok'
        }
    }

    It 'falls back to the nested runspace host for nested isolated invocations' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj-invoke-nested'
            $moduleManifestPath = Get-Module 'pslrm' | Select-Object -First 1 -ExpandProperty Path
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            Write-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1') -Data @{
                OuterModule = @{ Repository = 'PSGallery' }
                InnerModule = @{ Repository = 'PSGallery' }
            }
            Write-Lockfile -Path (Join-Path $root 'psreq.lock.psd1') -Data @{
                OuterModule = @{ Version = '1.0.0'; Repository = 'PSGallery' }
                InnerModule = @{ Version = '1.0.0'; Repository = 'PSGallery' }
            }

            New-TestStoreModule -ProjectRoot $root -ModuleName 'InnerModule' -CommandName 'Invoke-InnerMessage' -ModuleBody @'
function Invoke-InnerMessage {
    [CmdletBinding()]
    param()

    Write-Host 'inner-host-output' -ForegroundColor DarkGray
    'inner-ok'
}

Export-ModuleMember -Function 'Invoke-InnerMessage'
'@

            New-TestStoreModule -ProjectRoot $root -ModuleName 'OuterModule' -CommandName 'Invoke-NestedMessage' -ModuleBody @'
function Invoke-NestedMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ProjectRoot,

        [Parameter(Mandatory)]
        [string] $ModuleManifestPath
    )

    Import-Module -Name $ModuleManifestPath -Force

    Write-Host 'outer-host-output' -ForegroundColor DarkGray
    $nested = @(Invoke-PSLResource -Path $ProjectRoot -CommandName 'Invoke-InnerMessage' 6>&1)
    $nested
    'outer-ok'
}

Export-ModuleMember -Function 'Invoke-NestedMessage'
'@

            $actual = @(
                Invoke-PSLResource -Path $root -CommandName 'Invoke-NestedMessage' -Arguments @(
                    '-ProjectRoot', $root,
                    '-ModuleManifestPath', $moduleManifestPath
                ) 6>&1
            )

            $actual[-1] | Should -BeExactly 'outer-ok'
            $actual | Should -Contain 'inner-ok'
            @(
                $actual | Where-Object {
                    $_ -is [System.Management.Automation.InformationRecord]
                } | ForEach-Object { [string]$_.MessageData }
            ) | Should -Contain 'inner-host-output'
        }
    }

    It 'resolves commands only from local resources even when the name collides with a built-in command' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj-invoke-shadow'
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            Write-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1') -Data @{ LocalShadowModule = @{ Repository = 'PSGallery' } }
            Write-Lockfile -Path (Join-Path $root 'psreq.lock.psd1') -Data @{ LocalShadowModule = @{ Version = '1.0.0'; Repository = 'PSGallery' } }

            New-TestStoreModule -ProjectRoot $root -ModuleName 'LocalShadowModule' -CommandName 'Get-ChildItem' -ModuleBody @'
function Get-ChildItem {
    [CmdletBinding()]
    param()

    'local-shadow'
}

Export-ModuleMember -Function 'Get-ChildItem'
'@

            $actual = @(Invoke-PSLResource -Path $root -CommandName 'Get-ChildItem')

            $actual | Should -Be @('local-shadow')
        }
    }

    It 'errors when the command is not exported by any local resource' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj-invoke-missing-command'
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            Write-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1') -Data @{ LocalEchoModule = @{ Repository = 'PSGallery' } }
            Write-Lockfile -Path (Join-Path $root 'psreq.lock.psd1') -Data @{ LocalEchoModule = @{ Version = '1.0.0'; Repository = 'PSGallery' } }

            New-TestStoreModule -ProjectRoot $root -ModuleName 'LocalEchoModule' -CommandName 'Invoke-LocalEcho' -ModuleBody @'
function Invoke-LocalEcho {
    [CmdletBinding()]
    param()

    'ok'
}

Export-ModuleMember -Function 'Invoke-LocalEcho'
'@

            { Invoke-PSLResource -Path $root -CommandName 'Missing-Command' } | Should -Throw
        }
    }

    It 'surfaces the original isolated-runspace failure instead of the EndInvoke wrapper' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj-invoke-inner-failure'
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            Write-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1') -Data @{ BrokenModule = @{ Repository = 'PSGallery' } }
            Write-Lockfile -Path (Join-Path $root 'psreq.lock.psd1') -Data @{ BrokenModule = @{ Version = '1.0.0'; Repository = 'PSGallery' } }

            New-TestStoreModule -ProjectRoot $root -ModuleName 'BrokenModule' -CommandName 'Invoke-BrokenCount' -ModuleBody @'
function Invoke-BrokenCount {
    [CmdletBinding()]
    param()

    $item = [pscustomobject]@{ Name = 'only-name' }
    $item | Select-Object -ExpandProperty Count -ErrorAction Stop | Out-Null
}

Export-ModuleMember -Function 'Invoke-BrokenCount'
'@

            $thrown = $null

            try {
                Invoke-PSLResource -Path $root -CommandName 'Invoke-BrokenCount'
            }
            catch {
                $thrown = $_
            }

            $thrown | Should -Not -BeNullOrEmpty
            $thrown.Exception.Message | Should -BeLike '*Count*cannot be found*'
            $thrown.Exception.Message | Should -Not -BeLike '*Exception calling "EndInvoke"*'
        }
    }

    It 'errors when multiple local resources export the same command' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj-invoke-conflict'
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            Write-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1') -Data @{
                ConflictOne = @{ Repository = 'PSGallery' }
                ConflictTwo = @{ Repository = 'PSGallery' }
            }
            Write-Lockfile -Path (Join-Path $root 'psreq.lock.psd1') -Data @{
                ConflictOne = @{ Version = '1.0.0'; Repository = 'PSGallery' }
                ConflictTwo = @{ Version = '1.0.0'; Repository = 'PSGallery' }
            }

            New-TestStoreModule -ProjectRoot $root -ModuleName 'ConflictOne' -CommandName 'Invoke-Conflict' -ModuleBody @'
function Invoke-Conflict {
    [CmdletBinding()]
    param()

    'one'
}

Export-ModuleMember -Function 'Invoke-Conflict'
'@

            New-TestStoreModule -ProjectRoot $root -ModuleName 'ConflictTwo' -CommandName 'Invoke-Conflict' -ModuleBody @'
function Invoke-Conflict {
    [CmdletBinding()]
    param()

    'two'
}

Export-ModuleMember -Function 'Invoke-Conflict'
'@

            { Invoke-PSLResource -Path $root -CommandName 'Invoke-Conflict' } | Should -Throw
        }
    }

    It 'errors when a lockfile resource is missing from the local store' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj-invoke-missing-store'
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            Write-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1') -Data @{ MissingStoreModule = @{ Repository = 'PSGallery' } }
            Write-Lockfile -Path (Join-Path $root 'psreq.lock.psd1') -Data @{ MissingStoreModule = @{ Version = '1.0.0'; Repository = 'PSGallery' } }
            New-Item -ItemType Directory -Path (Join-Path $root '.pslrm') -Force | Out-Null

            { Invoke-PSLResource -Path $root -CommandName 'Invoke-Missing' } | Should -Throw
        }
    }

    It 'errors when InProcess execution is requested' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj-invoke-inprocess'
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            Write-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1') -Data @{ A = @{ Repository = 'PSGallery' } }

            { Invoke-PSLResource -Path $root -CommandName 'Anything' -ExecutionScope InProcess } | Should -Throw
        }
    }
}

Describe 'Get-InstalledPSLResource' {
    It 'lists direct resources by default and marks IsDirect' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj2'
            $nested = Join-Path $root 'src'
            New-Item -ItemType Directory -Path $nested -Force | Out-Null

            $req = @{ A = @{ Version = [version]'1.0.0'; Repository = 'PSGallery' } }
            Write-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1') -Data $req

            $lock = @{
                A = @{ Version = [version]'1.0.0'; Repository = 'PSGallery' }
                Dep = @{ Version = [version]'9.9.9'; Repository = 'PSGallery' }
            }
            Write-Lockfile -Path (Join-Path $root 'psreq.lock.psd1') -Data $lock

            $actual = @(Get-InstalledPSLResource -Path $nested)

            $actual.Count | Should -Be 1
            $actual[0].Name | Should -BeExactly 'A'
            $actual[0].IsDirect | Should -BeTrue
            $actual[0].PSObject.TypeNames[0] | Should -BeExactly 'PSLRM.Resource'
        }
    }

    It 'normalizes prerelease when lockfile provides Version + Prerelease' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj-pre'
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            $req = @{ Pester = @{ Version = '[6.0.0,7.0.0)'; Repository = 'PSGallery'; Prerelease = $true } }
            Write-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1') -Data $req

            $lock = @{ Pester = @{ Version = '6.0.0'; Prerelease = 'alpha5'; Repository = 'PSGallery' } }
            Write-Lockfile -Path (Join-Path $root 'psreq.lock.psd1') -Data $lock

            $actual = @(Get-InstalledPSLResource -Path $root)

            $actual.Count | Should -Be 1
            $actual[0].Name | Should -BeExactly 'Pester'
            $actual[0].Version | Should -BeExactly '6.0.0-alpha5'
        }
    }

    It 'lists all saved resources with -IncludeDependencies' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj3'
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            $req = @{ A = @{ Version = [version]'1.0.0'; Repository = 'PSGallery' } }
            Write-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1') -Data $req

            $lock = @{
                A = @{ Version = [version]'1.0.0'; Repository = 'PSGallery' }
                Dep = @{ Version = [version]'9.9.9'; Repository = 'PSGallery' }
            }
            Write-Lockfile -Path (Join-Path $root 'psreq.lock.psd1') -Data $lock

            $actual = @(Get-InstalledPSLResource -Path $root -IncludeDependencies)
            ($actual | ForEach-Object Name) | Should -Be @('A', 'Dep')
            ($actual | Where-Object Name -EQ 'Dep').IsDirect | Should -BeFalse
        }
    }

    It 'errors if the lockfile is missing' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj4'
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            Write-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1') -Data @{ A = @{ Version = [version]'1.0.0'; Repository = 'PSGallery' } }

            { Get-InstalledPSLResource -Path $root } | Should -Throw
        }
    }
}

Describe 'Install-PSLResource' {
    It 'calls Save-PSResource via wrapper, writes lockfile, and outputs direct resources by default' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj-install'
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            $req = @{ A = @{ Version = '[1.0.0,2.0.0)'; Repository = 'PSGallery' } }
            Write-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1') -Data $req

            $saved = @(
                (New-TestPSResourceInfo -Name 'A' -Version '1.2.3' -Prerelease $null -Repository 'PSGallery'),
                (New-TestPSResourceInfo -Name 'Dep' -Version '9.9.9' -Prerelease $null -Repository 'PSGallery')
            )

            Mock Invoke-SavePSResource -ModuleName pslrm {
                param([string] $Name, [string] $Version, [switch] $Prerelease, [string] $Repository, [string] $Path)
                $script:captured = [pscustomobject]@{ Name = $Name; Version = $Version; Prerelease = [bool]$Prerelease; Repository = $Repository; Path = $Path }
                return $saved
            }

            $actual = @(Install-PSLResource -Path $root)

            $script:captured.Name | Should -BeExactly 'A'
            $script:captured.Version | Should -BeExactly '[1.0.0,2.0.0)'
            $script:captured.Prerelease | Should -BeFalse
            $script:captured.Repository | Should -BeExactly 'PSGallery'
            $script:captured.Path | Should -BeExactly (Join-Path $root '.pslrm')

            $lockPath = Join-Path $root 'psreq.lock.psd1'
            $lock = Read-Lockfile -Path $lockPath
            $lock.Keys.Count | Should -Be 2
            $lock['A']['Version'] | Should -BeExactly '1.2.3'
            $lock['Dep']['Version'] | Should -BeExactly '9.9.9'

            ($actual | ForEach-Object Name) | Should -Be @('A')
            $actual[0].IsDirect | Should -BeTrue
            $actual[0].ProjectRoot | Should -BeExactly $root
        }
    }

    It 'outputs dependencies when -IncludeDependencies is specified' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj-install-deps'
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            $req = @{ A = @{ Version = '[1.0.0,2.0.0)'; Repository = 'PSGallery' } }
            Write-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1') -Data $req

            $saved = @(
                (New-TestPSResourceInfo -Name 'Dep' -Version '9.9.9' -Prerelease $null -Repository 'PSGallery'),
                (New-TestPSResourceInfo -Name 'A' -Version '1.2.3' -Prerelease $null -Repository 'PSGallery')
            )

            Mock Invoke-SavePSResource -ModuleName pslrm { return $saved }

            $actual = @(Install-PSLResource -Path $root -IncludeDependencies)

            ($actual | ForEach-Object Name) | Should -Be @('A', 'Dep')
            ($actual | Where-Object Name -EQ 'Dep').IsDirect | Should -BeFalse
        }
    }

    It 'uses lockfile as source of truth when lockfile exists' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj-install-from-lock'
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            $req = @{ A = @{ Version = '[1.0.0,2.0.0)'; Repository = 'PSGallery' } }
            Write-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1') -Data $req

            $lock = @{
                A = @{ Version = '1.2.3'; Repository = 'PSGallery' }
                Dep = @{ Version = '9.9.9'; Repository = 'PSGallery' }
            }
            Write-Lockfile -Path (Join-Path $root 'psreq.lock.psd1') -Data $lock

            Mock Invoke-SavePSResource -ModuleName pslrm {
                param([string] $Name, [string] $Version, [switch] $Prerelease, [string] $Repository, [string] $Path)
                if (-not $script:capturedCalls) {
                    $script:capturedCalls = [System.Collections.Generic.List[object]]::new()
                }
                $script:capturedCalls.Add([pscustomobject]@{
                        Name = $Name
                        Version = $Version
                        Prerelease = [bool]$Prerelease
                        Repository = $Repository
                        Path = $Path
                    })
                return @()
            }

            $script:capturedCalls = [System.Collections.Generic.List[object]]::new()
            $actual = @(Install-PSLResource -Path $root -IncludeDependencies)

            $script:capturedCalls.Count | Should -Be 2
            ($script:capturedCalls | ForEach-Object Name) | Should -Be @('A', 'Dep')
            ($script:capturedCalls | ForEach-Object Version) | Should -Be @('1.2.3', '9.9.9')
            ($script:capturedCalls | ForEach-Object Repository | Select-Object -Unique) | Should -Be @('PSGallery')
            ($script:capturedCalls | ForEach-Object Path | Select-Object -Unique) | Should -Be @(Join-Path $root '.pslrm')

            $lockAfter = Read-Lockfile -Path (Join-Path $root 'psreq.lock.psd1')
            $lockAfter | Should-BeEquivalent $lock

            ($actual | ForEach-Object Name) | Should -Be @('A', 'Dep')
            ($actual | Where-Object Name -EQ 'Dep').IsDirect | Should -BeFalse
        }
    }

    It 'errors when the lockfile is stale for current requirements' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj-install-stale-lock'
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            $req = @{
                A = @{ Version = '[1.0.0,2.0.0)'; Repository = 'PSGallery' }
                B = @{ Version = '[2.0.0,3.0.0)'; Repository = 'PSGallery' }
            }
            Write-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1') -Data $req

            $lock = @{
                A = @{ Version = '1.2.3'; Repository = 'PSGallery' }
                Dep = @{ Version = '9.9.9'; Repository = 'PSGallery' }
            }
            Write-Lockfile -Path (Join-Path $root 'psreq.lock.psd1') -Data $lock

            Mock Invoke-SavePSResource -ModuleName pslrm { throw 'should not be called' }

            { Install-PSLResource -Path $root } | Should -Throw '*Update-PSLResource*'
        }
    }

    It 'errors when requirements specify a non-PSGallery repository' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj-install-bad-repo'
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            $req = @{ A = @{ Version = '[1.0.0,2.0.0)'; Repository = 'OtherRepo' } }
            Write-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1') -Data $req

            Mock Invoke-SavePSResource -ModuleName pslrm { throw 'should not be called' }

            { Install-PSLResource -Path $root } | Should -Throw
        }
    }
}

Describe 'Update-PSLResource' {
    It 'recreates lockfile and outputs direct resources by default' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj-update'
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            $req = @{ A = @{ Version = '[1.0.0,2.0.0)'; Repository = 'PSGallery' } }
            Write-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1') -Data $req

            # Seed old lockfile to verify update rewrites from latest save result.
            Write-Lockfile -Path (Join-Path $root 'psreq.lock.psd1') -Data @{ Old = @{ Version = '0.1.0'; Repository = 'PSGallery' } }

            $saved = @(
                (New-TestPSResourceInfo -Name 'A' -Version '1.2.3' -Prerelease $null -Repository 'PSGallery'),
                (New-TestPSResourceInfo -Name 'Dep' -Version '9.9.9' -Prerelease $null -Repository 'PSGallery')
            )

            Mock Invoke-SavePSResource -ModuleName pslrm { return $saved }

            $actual = @(Update-PSLResource -Path $root)

            $lock = Read-Lockfile -Path (Join-Path $root 'psreq.lock.psd1')
            $lock.Keys | Should-BeEquivalent @('A', 'Dep')
            $lock.Keys | Should -Not -Contain 'Old'
            $lock['A']['Version'] | Should -BeExactly '1.2.3'
            $lock['Dep']['Version'] | Should -BeExactly '9.9.9'

            ($actual | ForEach-Object Name) | Should -Be @('A')
            $actual[0].IsDirect | Should -BeTrue
            $actual[0].ProjectRoot | Should -BeExactly $root
        }
    }

    It 'outputs dependencies when -IncludeDependencies is specified' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj-update-deps'
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            $req = @{ A = @{ Version = '[1.0.0,2.0.0)'; Repository = 'PSGallery' } }
            Write-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1') -Data $req

            $saved = @(
                (New-TestPSResourceInfo -Name 'Dep' -Version '9.9.9' -Prerelease $null -Repository 'PSGallery'),
                (New-TestPSResourceInfo -Name 'A' -Version '1.2.3' -Prerelease $null -Repository 'PSGallery')
            )

            Mock Invoke-SavePSResource -ModuleName pslrm { return $saved }

            $actual = @(Update-PSLResource -Path $root -IncludeDependencies)

            ($actual | ForEach-Object Name) | Should -Be @('A', 'Dep')
            ($actual | Where-Object Name -EQ 'Dep').IsDirect | Should -BeFalse
        }
    }

    It 'errors when requirements specify a non-PSGallery repository' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj-update-bad-repo'
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            $req = @{ A = @{ Version = '[1.0.0,2.0.0)'; Repository = 'OtherRepo' } }
            Write-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1') -Data $req

            Mock Invoke-SavePSResource -ModuleName pslrm { throw 'should not be called' }

            { Update-PSLResource -Path $root } | Should -Throw
        }
    }
}

Describe 'Uninstall-PSLResource' {
    It 'removes target from requirements and recreates lock/store from remaining resources' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj-uninstall-one'
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            $req = @{
                A = @{ Version = '[1.0.0,2.0.0)'; Repository = 'PSGallery' }
                B = @{ Version = '[2.0.0,3.0.0)'; Repository = 'PSGallery' }
            }
            Write-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1') -Data $req

            # Seed artifacts to ensure uninstall clears store and rebuilds from remaining requirements.
            Write-Lockfile -Path (Join-Path $root 'psreq.lock.psd1') -Data @{ A = @{ Version = '1.1.1'; Repository = 'PSGallery' } }
            $store = Join-Path $root '.pslrm'
            New-Item -ItemType Directory -Path (Join-Path $store 'stale') -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $store 'stale\old.txt'), 'old', [System.Text.UTF8Encoding]::new($false))

            $saved = @(
                (New-TestPSResourceInfo -Name 'B' -Version '2.3.4' -Prerelease $null -Repository 'PSGallery')
            )
            Mock Invoke-SavePSResource -ModuleName pslrm { return $saved }

            $actual = @(Uninstall-PSLResource -Path $root -Name 'A')

            $reqAfter = Import-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1')
            $reqAfter.Keys | Should -Be @('B')

            $lockAfter = Read-Lockfile -Path (Join-Path $root 'psreq.lock.psd1')
            $lockAfter.Keys | Should -Be @('B')
            $lockAfter['B']['Version'] | Should -BeExactly '2.3.4'

            Test-Path -LiteralPath (Join-Path $store 'stale\old.txt') | Should -BeFalse

            ($actual | ForEach-Object Name) | Should -Be @('B')
        }
    }

    It 'writes empty lockfile when all requirements are removed' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj-uninstall-all'
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            $req = @{ A = @{ Version = '[1.0.0,2.0.0)'; Repository = 'PSGallery' } }
            Write-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1') -Data $req

            Mock Invoke-SavePSResource -ModuleName pslrm { throw 'should not be called' }

            $actual = @(Uninstall-PSLResource -Path $root -Name 'A')

            $reqAfter = Import-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1')
            $reqAfter.Count | Should -Be 0

            $lockAfter = Read-Lockfile -Path (Join-Path $root 'psreq.lock.psd1')
            $lockAfter.Count | Should -Be 0

            $actual.Count | Should -Be 0
        }
    }

    It 'errors when target requirement does not exist' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj-uninstall-missing'
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            $req = @{ A = @{ Version = '[1.0.0,2.0.0)'; Repository = 'PSGallery' } }
            Write-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1') -Data $req

            { Uninstall-PSLResource -Path $root -Name 'Missing' } | Should -Throw
        }
    }
}

Describe 'Restore-PSLResource' {
    It 'errors when the lockfile is missing' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj-restore-missing-lock'
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            $req = @{ A = @{ Version = '[1.0.0,2.0.0)'; Repository = 'PSGallery' } }
            Write-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1') -Data $req

            { Restore-PSLResource -Path $root } | Should -Throw
        }
    }

    It 'clears existing store and restores resources from lockfile' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj-restore'
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            $req = @{ A = @{ Version = '[1.0.0,2.0.0)'; Repository = 'PSGallery' } }
            Write-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1') -Data $req

            $lock = @{
                A = @{ Version = '1.2.3'; Repository = 'PSGallery' }
                Dep = @{ Version = '9.9.9'; Repository = 'PSGallery' }
            }
            Write-Lockfile -Path (Join-Path $root 'psreq.lock.psd1') -Data $lock

            $store = Join-Path $root '.pslrm'
            New-Item -ItemType Directory -Path (Join-Path $store 'stale') -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $store 'stale\old.txt'), 'old', [System.Text.UTF8Encoding]::new($false))

            Mock Invoke-SavePSResource -ModuleName pslrm {
                param([string] $Name, [string] $Version, [switch] $Prerelease, [string] $Repository, [string] $Path)
                if (-not $script:capturedCalls) {
                    $script:capturedCalls = [System.Collections.Generic.List[object]]::new()
                }
                $script:capturedCalls.Add([pscustomobject]@{
                        Name = $Name
                        Version = $Version
                        Prerelease = [bool]$Prerelease
                        Repository = $Repository
                        Path = $Path
                    })
                return @()
            }

            $script:capturedCalls = [System.Collections.Generic.List[object]]::new()
            $actual = @(Restore-PSLResource -Path $root)

            Test-Path -LiteralPath (Join-Path $store 'stale\old.txt') | Should -BeFalse

            $script:capturedCalls.Count | Should -Be 2
            ($script:capturedCalls | ForEach-Object Name) | Should -Be @('A', 'Dep')
            ($script:capturedCalls | ForEach-Object Version) | Should -Be @('1.2.3', '9.9.9')
            ($script:capturedCalls | ForEach-Object Repository | Select-Object -Unique) | Should -Be @('PSGallery')
            ($script:capturedCalls | ForEach-Object Path | Select-Object -Unique) | Should -Be @(Join-Path $root '.pslrm')

            ($actual | ForEach-Object Name) | Should -Be @('A')
            $actual[0].IsDirect | Should -BeTrue
            $actual[0].ProjectRoot | Should -BeExactly $root
        }
    }

    It 'outputs dependencies when -IncludeDependencies is specified' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj-restore-deps'
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            $req = @{ A = @{ Version = '[1.0.0,2.0.0)'; Repository = 'PSGallery' } }
            Write-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1') -Data $req

            $lock = @{
                A = @{ Version = '1.2.3'; Repository = 'PSGallery' }
                Dep = @{ Version = '9.9.9'; Repository = 'PSGallery' }
            }
            Write-Lockfile -Path (Join-Path $root 'psreq.lock.psd1') -Data $lock

            Mock Invoke-SavePSResource -ModuleName pslrm { return @() }

            $actual = @(Restore-PSLResource -Path $root -IncludeDependencies)

            ($actual | ForEach-Object Name) | Should -Be @('A', 'Dep')
            ($actual | Where-Object Name -EQ 'Dep').IsDirect | Should -BeFalse
        }
    }
}
