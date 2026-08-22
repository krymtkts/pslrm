# Changelog

This file records all notable changes to this project.

This changelog uses the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format.
This project uses prerelease versions such as 0.0.1-alpha.

## [Unreleased]

### Added

- Add natural argument forwarding to `Invoke-PSLResource` with `-ArgumentTokens` for arrays.

## [0.0.1] - 2026-05-30

### Changed

- Unpin `Microsoft.PowerShell.PSResourceGet` in the manifest to allow newer versions.

## [0.0.1-alpha] - 2026-03-22

### Added

- Add project-local PowerShell resource management based on PSResourceGet.
- Add requirements and lockfile workflows with `Install-PSLResource` and `Update-PSLResource`.
- Add lockfile restore and removal workflows with `Restore-PSLResource` and `Uninstall-PSLResource`.
- Add `Get-InstalledPSLResource` for reading installed project resources from the lockfile.
- Add `Invoke-PSLResource` for running commands from project-local resources in an isolated runspace.
- Add build, lint, unit test, and integration test tasks through `Invoke-Build`.

### Notes

- This is the initial alpha release track for `pslrm`.
- Supported PowerShell versions are Windows PowerShell 5.1 through PowerShell 7.x.
- Supported repository is PowerShell Gallery.
- `Invoke-PSLResource` uses `IsolatedRunspace` execution. `InProcess` execution is not implemented.

---

[Unreleased]: https://github.com/krymtkts/pslrm/compare/v0.0.1...HEAD
[0.0.1]: https://github.com/krymtkts/pslrm/compare/v0.0.1-alpha...v0.0.1
[0.0.1-alpha]: https://github.com/krymtkts/pslrm/releases/tag/v0.0.1-alpha
