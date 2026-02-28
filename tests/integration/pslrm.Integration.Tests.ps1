Describe 'Integration: Install-PSLResource (Save-PSResource real)' {
    BeforeAll {
        $modulePath = Join-Path $PSScriptRoot '..\..\pslrm.psm1'
        Import-Module $modulePath -Force

        Import-Module Microsoft.PowerShell.PSResourceGet -ErrorAction Stop

        $repo = Get-PSResourceRepository -Name 'PSGallery' -ErrorAction Stop
        if ($repo.PSObject.Properties.Name -contains 'Trusted') {
            if (-not [bool]$repo.Trusted) {
                throw 'PSGallery is not trusted. Trust it before running integration tests.'
            }
        }
    }

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
    BeforeAll {
        $modulePath = Join-Path $PSScriptRoot '..\..\pslrm.psm1'
        Import-Module $modulePath -Force

        Import-Module Microsoft.PowerShell.PSResourceGet -ErrorAction Stop

        $repo = Get-PSResourceRepository -Name 'PSGallery' -ErrorAction Stop
        if ($repo.PSObject.Properties.Name -contains 'Trusted') {
            if (-not [bool]$repo.Trusted) {
                throw 'PSGallery is not trusted. Trust it before running integration tests.'
            }
        }
    }

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
