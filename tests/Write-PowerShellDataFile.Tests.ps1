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
