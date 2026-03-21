BeforeAll {
    $helperPath = Join-Path $PSScriptRoot '..\..\tools\ReleaseNotes.Helpers.ps1'
    . $helperPath

    $script:NewTestChangelogContent = {
        @(
            '# Changelog'
            ''
            'This file records all notable changes to this project.'
            ''
            '## [Unreleased]'
            ''
            'aaaaa'
            ''
            '## [1.1.2] - 2023-03-07'
            ''
            '### Added'
            ''
            'CCC'
            ''
            '## [1.1.1] - 2023-03-06'
            ''
            '### Added'
            ''
            'BBB'
            ''
            '## [1.1.0] - 2023-03-05'
            ''
            '### Added'
            ''
            'AAA'
            ''
            '---'
            ''
            '[Unreleased]: https://github.com/krymtkts/pslrm/commits/main'
        ) -join "`n"
    }
}

Describe 'Get-ChangelogSections' {
    It 'returns version sections with heading and body' {
        $changelogPath = Join-Path $TestDrive 'CHANGELOG.md'
        (& $script:NewTestChangelogContent) | Set-Content -LiteralPath $changelogPath -NoNewline

        $sections = Get-ChangelogSections -Path $changelogPath

        $sections.Count | Should -Be 4
        $sections[1].Version | Should -BeExactly '1.1.2'
        $sections[1].Heading | Should -BeExactly '## [1.1.2] - 2023-03-07'
        $sections[1].Body | Should -BeExactly (@(
                '### Added'
                ''
                'CCC'
            ) -join "`n")
    }
}

Describe 'Get-ChangelogEntry' {
    It 'returns the target section body without footer markers' {
        $changelogPath = Join-Path $TestDrive 'CHANGELOG.md'
        @(
            '# Changelog'
            ''
            '## [Unreleased]'
            ''
            '### Added'
            ''
            '- Add thing'
            ''
            '### Notes'
            ''
            '- Note thing'
            ''
            '---'
            ''
            '[Unreleased]: https://example.test/commits/main'
        ) -join "`n" | Set-Content -LiteralPath $changelogPath -NoNewline

        $entry = Get-ChangelogEntry -Path $changelogPath -Version 'Unreleased'

        $entry | Should -BeExactly (@(
                '### Added'
                ''
                '- Add thing'
                ''
                '### Notes'
                ''
                '- Note thing'
            ) -join "`n")
    }

    It 'fails when the requested version is missing' {
        $changelogPath = Join-Path $TestDrive 'CHANGELOG.md'
        @(
            '# Changelog'
            ''
            '## [Unreleased]'
        ) -join "`n" | Set-Content -LiteralPath $changelogPath -NoNewline

        { Get-ChangelogEntry -Path $changelogPath -Version '0.0.1-alpha' } |
            Should -Throw 'Changelog entry not found for version: 0.0.1-alpha'
    }
}

Describe 'ConvertFrom-ReleaseTagToVersion' {
    It 'returns the version part from a version tag' {
        $version = ConvertFrom-ReleaseTagToVersion -ReleaseTag 'v1.1.2'

        $version | Should -BeExactly '1.1.2'
    }

    It 'accepts a refs/tags prefix' {
        $version = ConvertFrom-ReleaseTagToVersion -ReleaseTag 'refs/tags/v1.1.2'

        $version | Should -BeExactly '1.1.2'
    }

    It 'fails when the tag does not start with v' {
        { ConvertFrom-ReleaseTagToVersion -ReleaseTag '1.1.2' } |
            Should -Throw 'Release tag must use the form v<version>: 1.1.2'
    }
}

Describe 'Assert-ReleaseMetadata' {
    It 'passes when the changelog section exists and the release tag matches the version' {
        $changelogPath = Join-Path $TestDrive 'CHANGELOG.md'
        (& $script:NewTestChangelogContent) | Set-Content -LiteralPath $changelogPath -NoNewline

        { Assert-ReleaseMetadata -Path $changelogPath -Version '1.1.2' -ReleaseTag 'v1.1.2' } |
            Should -Not -Throw
    }

    It 'passes when the changelog section exists and no release tag is supplied' {
        $changelogPath = Join-Path $TestDrive 'CHANGELOG.md'
        (& $script:NewTestChangelogContent) | Set-Content -LiteralPath $changelogPath -NoNewline

        { Assert-ReleaseMetadata -Path $changelogPath -Version '1.1.2' } |
            Should -Not -Throw
    }

    It 'fails when the changelog section is missing' {
        $changelogPath = Join-Path $TestDrive 'CHANGELOG.md'
        (& $script:NewTestChangelogContent) | Set-Content -LiteralPath $changelogPath -NoNewline

        { Assert-ReleaseMetadata -Path $changelogPath -Version '2.0.0' -ReleaseTag 'v2.0.0' } |
            Should -Throw 'Changelog entry not found for version: 2.0.0'
    }

    It 'fails when the release tag version does not match the manifest version' {
        $changelogPath = Join-Path $TestDrive 'CHANGELOG.md'
        (& $script:NewTestChangelogContent) | Set-Content -LiteralPath $changelogPath -NoNewline

        { Assert-ReleaseMetadata -Path $changelogPath -Version '1.1.2' -ReleaseTag 'v1.1.1' } |
            Should -Throw 'Release tag version does not match manifest version. Tag: 1.1.1, Manifest: 1.1.2'
    }
}

Describe 'Get-ManifestReleaseNotes' {
    It 'formats the target version and the next two older versions plus a full changelog link' {
        $changelogPath = Join-Path $TestDrive 'CHANGELOG.md'
        (& $script:NewTestChangelogContent) | Set-Content -LiteralPath $changelogPath -NoNewline

        $content = Get-ManifestReleaseNotes -Path $changelogPath -Version '1.1.2' -RecentCount 3 -FullChangelogUrl 'https://example.test/CHANGELOG.md'

        $content | Should -BeExactly (@(
                '## [1.1.2] - 2023-03-07'
                ''
                '### Added'
                ''
                'CCC'
                ''
                '## [1.1.1] - 2023-03-06'
                ''
                '### Added'
                ''
                'BBB'
                ''
                '## [1.1.0] - 2023-03-05'
                ''
                '### Added'
                ''
                'AAA'
                ''
                'Full CHANGELOG: https://example.test/CHANGELOG.md'
            ) -join "`n")
    }

    It 'uses only the available sections when there are fewer than the requested count' {
        $changelogPath = Join-Path $TestDrive 'CHANGELOG.md'
        (& $script:NewTestChangelogContent) | Set-Content -LiteralPath $changelogPath -NoNewline

        $content = Get-ManifestReleaseNotes -Path $changelogPath -Version '1.1.1' -RecentCount 3 -FullChangelogUrl 'https://example.test/CHANGELOG.md'

        $content | Should -BeExactly (@(
                '## [1.1.1] - 2023-03-06'
                ''
                '### Added'
                ''
                'BBB'
                ''
                '## [1.1.0] - 2023-03-05'
                ''
                '### Added'
                ''
                'AAA'
                ''
                'Full CHANGELOG: https://example.test/CHANGELOG.md'
            ) -join "`n")
    }

    It 'limits the output when RecentCount is smaller than the available section count' {
        $changelogPath = Join-Path $TestDrive 'CHANGELOG.md'
        (& $script:NewTestChangelogContent) | Set-Content -LiteralPath $changelogPath -NoNewline

        $content = Get-ManifestReleaseNotes -Path $changelogPath -Version '1.1.2' -RecentCount 2 -FullChangelogUrl 'https://example.test/CHANGELOG.md'

        $content | Should -BeExactly (@(
                '## [1.1.2] - 2023-03-07'
                ''
                '### Added'
                ''
                'CCC'
                ''
                '## [1.1.1] - 2023-03-06'
                ''
                '### Added'
                ''
                'BBB'
                ''
                'Full CHANGELOG: https://example.test/CHANGELOG.md'
            ) -join "`n")
    }
}

Describe 'Set-ManifestReleaseNotes' {
    It 'writes a release notes here-string that Import-PowerShellDataFile can read' {
        $manifestPath = Join-Path $TestDrive 'test.psd1'
        @(
            '@{'
            '    PrivateData = @{'
            '        PSData = @{'
            '            # ReleaseNotes of this module'
            "            # ReleaseNotes = ''"
            ''
            '            # Prerelease string of this module'
            "            Prerelease = 'alpha'"
            '        }'
            '    }'
            '}'
        ) -join "`n" | Set-Content -LiteralPath $manifestPath -NoNewline

        $releaseNotes = @(
            '### Added'
            ''
            '- Add thing'
        ) -join "`n"

        Set-ManifestReleaseNotes -ManifestPath $manifestPath -ReleaseNotes $releaseNotes
        $manifest = Import-PowerShellDataFile -Path $manifestPath
        $manifestText = Get-Content -LiteralPath $manifestPath -Raw

        $manifest.PrivateData.PSData.ReleaseNotes | Should -BeExactly $releaseNotes
        $manifestText | Should -Not -Match "`r"
    }

    It 'replaces existing ReleaseNotes content instead of appending to it' {
        $manifestPath = Join-Path $TestDrive 'existing.psd1'
        @(
            '@{'
            '    PrivateData = @{'
            '        PSData = @{'
            '            # ReleaseNotes of this module'
            "            ReleaseNotes = @'"
            'old line'
            "'@"
            ''
            '            # Prerelease string of this module'
            "            Prerelease = 'alpha'"
            '        }'
            '    }'
            '}'
        ) -join "`n" | Set-Content -LiteralPath $manifestPath -NoNewline

        $releaseNotes = @(
            '### Added'
            ''
            '- New line'
        ) -join "`n"

        Set-ManifestReleaseNotes -ManifestPath $manifestPath -ReleaseNotes $releaseNotes
        $manifest = Import-PowerShellDataFile -Path $manifestPath
        $manifestText = Get-Content -LiteralPath $manifestPath -Raw

        $manifest.PrivateData.PSData.ReleaseNotes | Should -BeExactly $releaseNotes
        $manifestText | Should -Not -Match 'old line'
    }
}