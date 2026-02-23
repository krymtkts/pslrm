BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\pslrm.psm1'
    Import-Module $modulePath -Force
}

Describe 'Write-PowerShellDataFile' {
    It 'writes expected text format' {
        InModuleScope pslrm {
            $path = Join-Path $TestDrive 'format.psd1'
            $data = @{
                'x-y' = "O'Brien"
                a = 'b'
                nested = @{
                    n = 1
                    flag = $true
                    inner = @{
                        arr = @('one', 'two')
                    }
                }
            }

            $expected = @(
                '@{',
                "    'a' = 'b'",
                "    'nested' = @{",
                "        'flag' = `$true",
                "        'inner' = @{",
                "            'arr' = @('one', 'two')",
                '        }',
                "        'n' = 1",
                '    }',
                "    'x-y' = 'O''Brien'",
                '}',
                ''
            ) -join "`n"

            Write-PowerShellDataFile -Path $path -Data $data
            $actual = Get-Content -LiteralPath $path -Raw

            $actual | Should -BeExactly $expected
        }
    }

    It 'round-trips via Import-PowerShellDataFile' {
        $result = InModuleScope pslrm {
            $path = Join-Path $TestDrive 'roundtrip.psd1'
            $data = @{
                alpha = @{
                    inner = @{
                        message = "O'Brien"
                        list = @('one', 'two')
                    }
                    number = 1
                }
                beta = @{
                    flag = $false
                }
            }

            Write-PowerShellDataFile -Path $path -Data $data
            $read = Import-PowerShellDataFile -Path $path

            [pscustomobject]@{
                Read = $read
                Data = $data
            }
        }

        $result.Read | Should-BeEquivalent $result.Data
    }

    It 'is stable after re-serializing imported data' {
        InModuleScope pslrm {
            $path1 = Join-Path $TestDrive 'reserialize-1.psd1'
            $path2 = Join-Path $TestDrive 'reserialize-2.psd1'

            $data = @{
                numbers = @{
                    int = 1
                    dec = [decimal]1.5
                }
                misc = @{
                    empty = @{}
                    none = $null
                    words = @('a', 'b')
                }
            }

            Write-PowerShellDataFile -Path $path1 -Data $data
            $c1 = Get-Content -LiteralPath $path1 -Raw

            $imported = Import-PowerShellDataFile -Path $path1
            Write-PowerShellDataFile -Path $path2 -Data $imported
            $c2 = Get-Content -LiteralPath $path2 -Raw

            $c2 | Should -BeExactly $c1
        }
    }

    It 'supports empty hashtable' {
        InModuleScope pslrm {
            $path = Join-Path $TestDrive 'empty.psd1'

            Write-PowerShellDataFile -Path $path -Data @{}

            $read = Import-PowerShellDataFile -Path $path
            $read.Count | Should -Be 0
        }
    }
}

Describe 'Write-Lockfile' {
    It 'writes expected text format' {
        InModuleScope pslrm {
            $path = Join-Path $TestDrive 'format.lock.psd1'
            $data = @{
                Zeta = @{ Version = [version]'1.0.0'; Repository = 'PSGallery' }
                Alpha = @{ Version = [version]'2.0.0'; Repository = 'PSGallery' }
            }

            $expected = @(
                '@{',
                "    'Alpha' = @{",
                "        'Repository' = 'PSGallery'",
                "        'Version' = '2.0.0'",
                '    }',
                "    'Zeta' = @{",
                "        'Repository' = 'PSGallery'",
                "        'Version' = '1.0.0'",
                '    }',
                '}',
                ''
            ) -join "`n"

            Write-Lockfile -Path $path -Data $data
            $actual = Get-Content -LiteralPath $path -Raw

            $actual | Should -BeExactly $expected
        }
    }

    It 'sorts keys deterministically (ordinal)' {
        InModuleScope pslrm {
            $path = Join-Path $TestDrive 'sorted.lock.psd1'
            # NOTE: use case-sensitive keys to verify that sorting is ordinal.
            $data = [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
            $data['b'] = @{ Version = [version]'1.0.0'; Repository = 'PSGallery' }
            $data['A'] = @{ Version = [version]'1.0.0'; Repository = 'PSGallery' }
            $data['a'] = @{ Version = [version]'1.0.0'; Repository = 'PSGallery' }

            Write-Lockfile -Path $path -Data $data
            $lines = Get-Content -LiteralPath $path

            $topLevelKeysInOrder = $lines |
                Where-Object { $_ -match "^\s{4}'([^']+)'\s=\s@\{$" } |
                ForEach-Object { $Matches[1] }

            $topLevelKeysInOrder | Should -Be @('A', 'a', 'b')
        }
    }

    It 'writes deterministically (same content on second write)' {
        InModuleScope pslrm {
            $path1 = Join-Path $TestDrive 'det-1.lock.psd1'
            $path2 = Join-Path $TestDrive 'det-2.lock.psd1'

            $data = @{
                Zeta = @{ Version = [version]'1.0.0'; Repository = 'PSGallery' }
                Alpha = @{ Version = [version]'2.0.0'; Repository = 'PSGallery' }
            }

            Write-Lockfile -Path $path1 -Data $data
            $c1 = Get-Content -LiteralPath $path1 -Raw

            Write-Lockfile -Path $path2 -Data $data
            $c2 = Get-Content -LiteralPath $path2 -Raw

            $c2 | Should -BeExactly $c1
        }
    }

    It 'overwrites an existing lockfile' {
        InModuleScope pslrm {
            $path = Join-Path $TestDrive 'overwrite.lock.psd1'

            $data1 = @{ A = @{ Version = [version]'1.0.0'; Repository = 'PSGallery' } }
            $data2 = @{ B = @{ Version = [version]'2.0.0'; Repository = 'PSGallery' } }

            Write-Lockfile -Path $path -Data $data1
            $c1 = Get-Content -LiteralPath $path -Raw

            Write-Lockfile -Path $path -Data $data2
            $c2 = Get-Content -LiteralPath $path -Raw

            $c2 | Should -Not -BeExactly $c1
            $expected2 = @(
                '@{',
                "    'B' = @{",
                "        'Repository' = 'PSGallery'",
                "        'Version' = '2.0.0'",
                '    }',
                '}',
                ''
            ) -join "`n"

            $c2 | Should -BeExactly $expected2
        }
    }
}

Describe 'Read-Lockfile' {
    It 'errors when the lockfile is missing' {
        InModuleScope pslrm {
            $missing = Join-Path $TestDrive 'missing.lock.psd1'
            { Read-Lockfile -Path $missing } | Should -Throw
        }
    }

    It 'errors when the lockfile content cannot be parsed' {
        InModuleScope pslrm {
            $path = Join-Path $TestDrive 'not-hashtable.lock.psd1'
            $content = "'hello'`n"

            [System.IO.File]::WriteAllText($path, $content, [System.Text.UTF8Encoding]::new($false))
            { Read-Lockfile -Path $path -ErrorAction Stop 2>$null } | Should -Throw
        }
    }

    It 'reads expected data from prepared lockfile content' {
        $result = InModuleScope pslrm {
            $path = Join-Path $TestDrive 'prepared.lock.psd1'
            $content = @(
                '@{',
                "    'Alpha' = @{",
                "        'Repository' = 'PSGallery'",
                "        'Version' = '2.0.0'",
                '    }',
                "    'Zeta' = @{",
                "        'Repository' = 'PSGallery'",
                "        'Version' = '1.0.0'",
                '    }',
                '}',
                ''
            ) -join "`n"

            [System.IO.File]::WriteAllText($path, $content, [System.Text.UTF8Encoding]::new($false))
            $read = Read-Lockfile -Path $path

            $expected = @{
                Alpha = @{ Repository = 'PSGallery'; Version = '2.0.0' }
                Zeta = @{ Repository = 'PSGallery'; Version = '1.0.0' }
            }

            [pscustomobject]@{
                Read = $read
                Expected = $expected
            }
        }

        $result.Read | Should-BeEquivalent $result.Expected
    }
}

Describe 'Read-Lockfile + Write-Lockfile' {
    It 'round-trips an empty lockfile' {
        InModuleScope pslrm {
            $path = Join-Path $TestDrive 'empty.lock.psd1'

            Write-Lockfile -Path $path -Data @{}
            $read = Read-Lockfile -Path $path

            $read.Count | Should -Be 0
        }
    }

    It 'round-trips a non-empty lockfile (Write then Read)' {
        $result = InModuleScope pslrm {
            $path = Join-Path $TestDrive 'roundtrip.lock.psd1'
            $data = @{
                Zeta = @{ Version = [version]'1.0.0'; Repository = 'PSGallery' }
                Alpha = @{ Version = [version]'2.0.0'; Repository = 'PSGallery' }
            }

            Write-Lockfile -Path $path -Data $data
            $read = Read-Lockfile -Path $path

            $expected = @{
                Alpha = @{ Repository = 'PSGallery'; Version = '2.0.0' }
                Zeta = @{ Repository = 'PSGallery'; Version = '1.0.0' }
            }

            [pscustomobject]@{
                Read = $read
                Expected = $expected
            }
        }

        $result.Read | Should-BeEquivalent $result.Expected
    }
}
