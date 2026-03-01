BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\pslrm.psd1'
    Import-Module $modulePath -Force

    InModuleScope pslrm {
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
