BeforeAll {
    $moduleRoot = if (-not [string]::IsNullOrWhiteSpace($env:PSLRM_TEST_MODULE_ROOT)) {
        $env:PSLRM_TEST_MODULE_ROOT
    }
    else {
        (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    }

    $modulePath = Join-Path $moduleRoot 'pslrm.psd1'
    Import-Module $modulePath -Force

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
                [string] $Version = '1.0.0'
            )

            $moduleRoot = Join-Path $ProjectRoot ".pslrm\$ModuleName\$Version"
            New-Item -ItemType Directory -Path $moduleRoot -Force | Out-Null

            $manifestPath = Join-Path $moduleRoot "$ModuleName.psd1"
            $modulePath = Join-Path $moduleRoot "$ModuleName.psm1"
            $utf8NoBom = [System.Text.UTF8Encoding]::new($false)

            [System.IO.File]::WriteAllText($modulePath, $ModuleBody, $utf8NoBom)

            $manifestContent = @(
                '@{'
                "    RootModule = '$ModuleName.psm1'"
                "    ModuleVersion = '$Version'"
                "    GUID = '$([guid]::NewGuid())'"
                "    FunctionsToExport = @('$CommandName')"
                '}'
                ''
            ) -join "`n"

            [System.IO.File]::WriteAllText($manifestPath, $manifestContent, $utf8NoBom)
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
