BeforeAll {
    $helperPath = Join-Path $PSScriptRoot '..\..\tools\Build.Helpers.ps1'
    . $helperPath

    $script:NewTestSecureString = {
        param(
            [Parameter(Mandatory)]
            [string] $Value
        )

        ConvertTo-SecureString -String $Value -AsPlainText -Force
    }
}

Describe 'ConvertFrom-SecureStringToPlainText' {
    It 'returns the original string value' {
        $value = ConvertFrom-SecureStringToPlainText -SecureString (& $script:NewTestSecureString -Value 'example-key')

        $value | Should -BeExactly 'example-key'
    }
}