# pslrm

pslrm (PowerShell Local Resource Manager) is a thin wrapper for [Microsoft.PowerShell.PSResourceGet](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.psresourceget/?view=powershellget-3.x).

pslrm saves PSResourceGet resources into a directory in your project.
This gives you project-local (directory-based) dependency management.
It also keeps the requirements format compatible with PSResourceGet.

## What it does

- Installs/updates required resources from PowerShell Gallery into a project-local directory
- Writes a lockfile that records the resolved versions
- Restores the project-local directory to match the lockfile
- Uninstalls resources from the project-local directory

## Project files

- `psreq.psd1`
  Requirements file (compatible with PSResourceGet `-RequiredResourceFile` format)
- `psreq.lock.psd1`
  Lockfile (versions that PSResourceGet saved)

In `psreq.psd1`, each entry is a hashtable keyed by module name.
The following keys are commonly used by [PSResourceGet](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.psresourceget/about/about_psresourceget?view=powershellget-3.x#searching-by-required-resources).

- `version`
  A version string.
  It can be a range expression like `[0.0.1,1.3.0]`.
- `repository`
  The repository name.
  pslrm supports PSGallery.
- `prerelease`
  Set to `$true` to allow prerelease versions.

The project root is the directory that contains `psreq.psd1`.

## Local directory (default)

By default, pslrm saves resources under the project root at `./.pslrm/`.

PSResourceGet decides the on-disk layout under `./.pslrm/`.
pslrm does not impose a directory structure.

## Repository support

- Supported repository: PowerShell Gallery (PSGallery).
  If you set `repository` in `psreq.psd1`, it must resolve to **PSGallery**.
  Otherwise, pslrm errors.

## State model

- `psreq.psd1`
  Desired state for direct dependencies and version constraints.
- `psreq.lock.psd1`
  Resolved state for reproducible installs.
- `./.pslrm/`
  Materialized local resources for the current project.

pslrm treats these files differently depending on the command.

- `Update-PSLResource` resolves from requirements and refreshes the lockfile.
- `Restore-PSLResource` restores from the lockfile.
- `Install-PSLResource` is the convenience entry point:
  - If `psreq.lock.psd1` exists, install uses the lockfile to reproduce the saved versions.
  - If `psreq.lock.psd1` does not exist, install resolves from `psreq.psd1` and creates the lockfile.

Use restore when you want a lockfile-driven restore.
Use update when you want to apply changes from requirements.

## Commands

- `Install-PSLResource`
  Install project-local resources.
  If `psreq.lock.psd1` exists, it restores the saved versions from the lockfile.
  If `psreq.lock.psd1` does not exist, it resolves from `psreq.psd1` and writes a new lockfile.
  By default, it outputs direct resources.
  Use `-IncludeDependencies` to output all saved resources.
- `Update-PSLResource`
  Re-resolve project-local resources from `psreq.psd1`.
  Rewrite `psreq.lock.psd1` and refresh `./.pslrm/`.
  By default, it outputs direct resources.
  Use `-IncludeDependencies` to output all saved resources.
- `Get-InstalledPSLResource`
  Read `psreq.lock.psd1` and list installed resources for the project.
- `Uninstall-PSLResource`
  Remove selected resources from the project by name.
  It updates `psreq.psd1` (and may normalize it) and rewrites `psreq.lock.psd1`.
  If it removes all resources, it writes an empty lockfile.
- `Restore-PSLResource`
  Restore project-local resources to match `psreq.lock.psd1`.
  This is the explicit lockfile-driven restore command.
  If `psreq.lock.psd1` is missing, it errors.
  If `./.pslrm/` exists, it clears the directory before restore.

## Command comparison

| Command                 | Primary input                               | Updates `psreq.lock.psd1`     | Updates `./.pslrm/` | Intended use                                        |
| ----------------------- | ------------------------------------------- | ----------------------------- | ------------------- | --------------------------------------------------- |
| `Install-PSLResource`   | Lockfile if present, otherwise requirements | Only when lockfile is missing | Yes                 | Convenience command for local setup                 |
| `Update-PSLResource`    | Requirements                                | Yes                           | Yes                 | Re-resolve dependencies after changing requirements |
| `Restore-PSLResource`   | Lockfile                                    | No                            | Yes                 | Explicit reproducible restore, especially for CI    |
| `Uninstall-PSLResource` | Requirements after removal                  | Yes                           | Yes                 | Remove direct dependencies from the project         |

## Notes / limitations

- pslrm does not include its own dependency solver.
  PSResourceGet resolves dependencies.
- pslrm does not attempt strict transitive dependency management.
  It records what PSResourceGet saved into the lockfile.
- `Invoke-PSLResource` runs commands in an isolated runspace.
  The outermost invocation shares the caller host.
  This keeps host-aware output alive through the async isolated-runspace forwarding path.
  Nested `Invoke-PSLResource` calls use the default nested runspace host.
  This avoids propagating child hosts across nested isolated invocations.
- NOTE: PSResourceGet models prerelease versions separately from `Version`.
  Example: `Version = 6.0.0` and `Prerelease = alpha5`.
  To preserve prerelease info, pslrm stores versions as normalized strings in the lockfile.
  Example: `6.0.0-alpha5`.
  Ideally, pslrm would use `[System.Management.Automation.SemanticVersion]`.
  Windows PowerShell 5.1 does not provide it.
