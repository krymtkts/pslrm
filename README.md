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

## Commands

- `Install-PSLResource`
  Install project-local resources from `psreq.psd1`.
  Write `psreq.lock.psd1`.
  By default, it outputs direct resources.
  Use `-IncludeDependencies` to output all saved resources.
- `Update-PSLResource`
  Update project-local resources from `psreq.psd1`.
  Rewrite `psreq.lock.psd1`.
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
  If `psreq.lock.psd1` is missing, it errors.
  If `./.pslrm/` exists, it clears the directory before restore.

## Notes / limitations

- pslrm does not include its own dependency solver.
  PSResourceGet resolves dependencies.
- pslrm does not attempt strict transitive dependency management.
  It records what PSResourceGet saved into the lockfile.
- NOTE: PSResourceGet models prerelease versions separately from `Version`.
  Example: `Version = 6.0.0` and `Prerelease = alpha5`.
  To preserve prerelease info, pslrm stores versions as normalized strings in the lockfile.
  Example: `6.0.0-alpha5`.
  Ideally, pslrm would use `[System.Management.Automation.SemanticVersion]`.
  Windows PowerShell 5.1 does not provide it.
