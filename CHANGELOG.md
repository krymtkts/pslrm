# Changelog

This file records all notable changes to this project.

This changelog uses the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format.
This project uses prerelease versions such as 0.0.1-alpha.

## [Unreleased]

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
- Supported repository is PSGallery.
- `Invoke-PSLResource` defaults to `IsolatedRunspace` execution.

---

[Unreleased]: https://github.com/krymtkts/pslrm/commits/main
