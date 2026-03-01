BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\..\pslrm.psd1'
    Import-Module $modulePath -Force

    $repo = Get-PSResourceRepository -Name 'PSGallery' -ErrorAction Stop
    if ($repo.PSObject.Properties.Name -contains 'Trusted') {
        if (-not [bool]$repo.Trusted) {
            throw 'PSGallery is not trusted. Trust it before running integration tests.'
        }
    }
}

Describe 'Integration: Install-PSLResource (Save-PSResource real)' {
    It 'installs a resource and writes lockfile' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj-integration-install'
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            $req = @{ 'Get-GzipContent' = @{ Repository = 'PSGallery' } }
            Write-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1') -Data $req

            $actual = @(Install-PSLResource -Path $root -Confirm:$false)

            $actual.Count | Should -Be 1
            $actual[0].Name | Should -BeExactly 'Get-GzipContent'
            $actual[0].IsDirect | Should -BeTrue
            $actual[0].ProjectRoot | Should -BeExactly $root

            $lockPath = Join-Path $root 'psreq.lock.psd1'
            Test-Path -LiteralPath $lockPath | Should -BeTrue

            $lock = Read-Lockfile -Path $lockPath
            $lock.Keys | Should -Contain 'Get-GzipContent'
            $lock['Get-GzipContent']['Version'] | Should -Not -BeNullOrEmpty

            Write-Host "Lockfile content at ${lockPath}:" -ForegroundColor DarkGray
            Get-Content $lockPath | Write-Host -ForegroundColor DarkGray

            $storePath = Join-Path $root '.pslrm'
            Test-Path -LiteralPath $storePath | Should -BeTrue
            @(Get-ChildItem -LiteralPath $storePath -Recurse -File -ErrorAction Stop).Count | Should -BeGreaterThan 0

            Write-Host "Store content at ${storePath}:" -ForegroundColor DarkGray
            Get-ChildItem -LiteralPath $storePath -Recurse -File | ForEach-Object {
                Write-Host $_.FullName -ForegroundColor DarkGray
            }

        }
    }
}

Describe 'Integration: Update-PSLResource (Save-PSResource real)' {
    It 'updates from requirements and rewrites lockfile' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj-integration-update'
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            $req = @{ 'Get-GzipContent' = @{ Repository = 'PSGallery' } }
            Write-PowerShellDataFile -Path (Join-Path $root 'psreq.psd1') -Data $req

            # Seed stale lockfile data to verify Update rewrites from requirements resolution.
            $staleLock = @{ 'Old-Only-Entry' = @{ Version = '0.0.1'; Repository = 'PSGallery' } }
            Write-Lockfile -Path (Join-Path $root 'psreq.lock.psd1') -Data $staleLock

            $actual = @(Update-PSLResource -Path $root -Confirm:$false)

            $actual.Count | Should -Be 1
            $actual[0].Name | Should -BeExactly 'Get-GzipContent'
            $actual[0].IsDirect | Should -BeTrue
            $actual[0].ProjectRoot | Should -BeExactly $root

            $lockPath = Join-Path $root 'psreq.lock.psd1'
            Test-Path -LiteralPath $lockPath | Should -BeTrue

            $lock = Read-Lockfile -Path $lockPath
            $lock.Keys | Should -Contain 'Get-GzipContent'
            $lock.Keys | Should -Not -Contain 'Old-Only-Entry'
            $lock['Get-GzipContent']['Version'] | Should -Not -BeNullOrEmpty

            Write-Host "Lockfile content at ${lockPath}:" -ForegroundColor DarkGray
            Get-Content $lockPath | Write-Host -ForegroundColor DarkGray

            $storePath = Join-Path $root '.pslrm'
            Test-Path -LiteralPath $storePath | Should -BeTrue
            @(Get-ChildItem -LiteralPath $storePath -Recurse -File -ErrorAction Stop).Count | Should -BeGreaterThan 0

            Write-Host "Store content at ${storePath}:" -ForegroundColor DarkGray
            Get-ChildItem -LiteralPath $storePath -Recurse -File | ForEach-Object {
                Write-Host $_.FullName -ForegroundColor DarkGray
            }
        }
    }
}

Describe 'Integration: Uninstall-PSLResource' {
    It 'removes a direct dependency and rewrites requirements/lock/store' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj-integration-uninstall'
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            $req = @{ 'Get-GzipContent' = @{ Repository = 'PSGallery' } }
            $reqPath = Join-Path $root 'psreq.psd1'
            $lockPath = Join-Path $root 'psreq.lock.psd1'
            $storePath = Join-Path $root '.pslrm'

            Write-PowerShellDataFile -Path $reqPath -Data $req

            $installed = @(Install-PSLResource -Path $root -Confirm:$false)
            $installed.Count | Should -Be 1
            $installed[0].Name | Should -BeExactly 'Get-GzipContent'

            Test-Path -LiteralPath $lockPath | Should -BeTrue
            Test-Path -LiteralPath $storePath | Should -BeTrue

            $actual = @(Uninstall-PSLResource -Path $root -Name 'Get-GzipContent' -Confirm:$false)
            $actual.Count | Should -Be 0

            $reqAfter = Import-PowerShellDataFile -Path $reqPath
            $reqAfter.Count | Should -Be 0

            $lockAfter = Read-Lockfile -Path $lockPath
            $lockAfter.Count | Should -Be 0

            Test-Path -LiteralPath $storePath | Should -BeFalse

            Write-Host "Requirements content at ${reqPath}:" -ForegroundColor DarkGray
            Get-Content $reqPath | Write-Host -ForegroundColor DarkGray

            Write-Host "Lockfile content at ${lockPath}:" -ForegroundColor DarkGray
            Get-Content $lockPath | Write-Host -ForegroundColor DarkGray
        }
    }
}

Describe 'Integration: Restore-PSLResource' {
    It 'restores multiple modules from lockfile and clears stale store content' {
        InModuleScope pslrm {
            $root = Join-Path $TestDrive 'proj-integration-restore'
            New-Item -ItemType Directory -Path $root -Force | Out-Null

            $req = @{
                'Get-GzipContent' = @{ Repository = 'PSGallery' }
                'InvokeBuild' = @{ Repository = 'PSGallery' }
            }
            $reqPath = Join-Path $root 'psreq.psd1'
            $lockPath = Join-Path $root 'psreq.lock.psd1'
            $storePath = Join-Path $root '.pslrm'

            Write-PowerShellDataFile -Path $reqPath -Data $req

            $installed = @(Install-PSLResource -Path $root -Confirm:$false)
            $installed.Count | Should -Be 2
            ($installed | ForEach-Object Name) | Should-BeEquivalent @('Get-GzipContent', 'InvokeBuild')

            Test-Path -LiteralPath $lockPath | Should -BeTrue
            Test-Path -LiteralPath $storePath | Should -BeTrue

            New-Item -ItemType Directory -Path (Join-Path $storePath 'stale') -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $storePath 'stale\old.txt'), 'old', [System.Text.UTF8Encoding]::new($false))

            $actual = @(Restore-PSLResource -Path $root -Confirm:$false)

            $actual.Count | Should -Be 2
            ($actual | ForEach-Object Name) | Should-BeEquivalent @('Get-GzipContent', 'InvokeBuild')
            ($actual | ForEach-Object IsDirect | Select-Object -Unique) | Should -Be @($true)
            ($actual | ForEach-Object ProjectRoot | Select-Object -Unique) | Should -Be @($root)

            Test-Path -LiteralPath (Join-Path $storePath 'stale\old.txt') | Should -BeFalse
            Test-Path -LiteralPath $storePath | Should -BeTrue
            @(Get-ChildItem -LiteralPath $storePath -Recurse -File -ErrorAction Stop).Count | Should -BeGreaterThan 0

            $lock = Read-Lockfile -Path $lockPath
            $lock.Keys | Should -Contain 'Get-GzipContent'
            $lock.Keys | Should -Contain 'InvokeBuild'

            Write-Host "Lockfile content at ${lockPath}:" -ForegroundColor DarkGray
            Get-Content $lockPath | Write-Host -ForegroundColor DarkGray

            Write-Host "Store content at ${storePath}:" -ForegroundColor DarkGray
            Get-ChildItem -LiteralPath $storePath -Recurse -File | ForEach-Object {
                Write-Host $_.FullName -ForegroundColor DarkGray
            }
        }
    }
}
