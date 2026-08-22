---
document type: module
Help Version: 0.0.1
HelpInfoUri:
Locale: en-US
Module Guid: 31c24738-0fc2-40fa-b565-437c9e315535
Module Name: pslrm
ms.date: 08-22-2026
PlatyPS schema version: 2024-05-01
title: pslrm Module
---

# pslrm Module

## Description

A PowerShell module for managing project-based PowerShell resources.
It uses a lockfile, following package managers such as npm and Cargo.

pslrm uses `psreq.psd1` as the desired state for direct dependencies.
It records the resolved state in `psreq.lock.psd1` for reproducible installs.
pslrm saves resources under `.pslrm` in the project directory instead of a user-wide module path.

Use `Update-PSLResource` after changing requirements.
Use `Restore-PSLResource` to reproduce a lockfile.
Use `Invoke-PSLResource` to run a command exported by a project-local resource.

## pslrm

### [Get-InstalledPSLResource](Get-InstalledPSLResource.md)

List resources recorded in the project lockfile.

### [Install-PSLResource](Install-PSLResource.md)

Install project-local resources from the lockfile or requirements.

### [Invoke-PSLResource](Invoke-PSLResource.md)

Run a command exported by a project-local resource.

### [Restore-PSLResource](Restore-PSLResource.md)

Restore project-local resources from the lockfile.

### [Uninstall-PSLResource](Uninstall-PSLResource.md)

Remove direct resources from a pslrm project.

### [Update-PSLResource](Update-PSLResource.md)

Resolve requirements and update the project lockfile and local store.
