---
document type: cmdlet
external help file: pslrm-Help.xml
HelpUri: https://github.com/krymtkts/pslrm/blob/main/docs/pslrm/Get-InstalledPSLResource.md
Locale: en-US
Module Name: pslrm
ms.date: 08-22-2026
PlatyPS schema version: 2024-05-01
title: Get-InstalledPSLResource
---

# Get-InstalledPSLResource

## SYNOPSIS

List resources recorded in the project lockfile.

## SYNTAX

### __AllParameterSets

```
Get-InstalledPSLResource [[-Path] <string>] [-IncludeDependencies]
```

## ALIASES

## DESCRIPTION

Reads `psreq.psd1` and `psreq.lock.psd1` from the project root and returns the locked direct resources.
Use `IncludeDependencies` to include transitive dependencies recorded in the lockfile.

This command reads project metadata without resolving dependencies.
It leaves the project-local store unchanged.

## EXAMPLES

### Example 1

```powershell
Get-InstalledPSLResource
```

Lists direct resources from the pslrm project containing the current directory.

### Example 2

```powershell
Get-InstalledPSLResource -Path ./tools -IncludeDependencies
```

Finds the project root above `./tools` and lists direct and transitive resources.

## PARAMETERS

### -IncludeDependencies

Includes transitive dependencies recorded in the lockfile.
By default, the command returns direct resources declared in `psreq.psd1`.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ""
SupportsWildcards: false
Aliases: []
ParameterSets:
  - Name: (All)
    Position: Named
    IsRequired: false
    ValueFromPipeline: false
    ValueFromPipelineByPropertyName: false
    ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ""
```

### -Path

The project root or a directory below it.
The command searches parent directories for `psreq.psd1`.
The default is the current directory.

```yaml
Type: System.String
DefaultValue: ""
SupportsWildcards: false
Aliases: []
ParameterSets:
  - Name: (All)
    Position: 0
    IsRequired: false
    ValueFromPipeline: false
    ValueFromPipelineByPropertyName: false
    ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ""
```

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable.
For more information, see [about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### System.Object

Returns `PSLRM.Resource` objects containing resource identity and project information.
Resource properties include `Name`, `Version`, and `Repository`.
Project properties include `IsDirect` and `ProjectRoot`.

## NOTES

The result reflects the lockfile and does not verify that each resource exists under `.pslrm`.

## RELATED LINKS

- [pslrm Module](https://github.com/krymtkts/pslrm/blob/main/docs/pslrm/pslrm.md)
- [Install-PSLResource](https://github.com/krymtkts/pslrm/blob/main/docs/pslrm/Install-PSLResource.md)
- [Update-PSLResource](https://github.com/krymtkts/pslrm/blob/main/docs/pslrm/Update-PSLResource.md)
- [Restore-PSLResource](https://github.com/krymtkts/pslrm/blob/main/docs/pslrm/Restore-PSLResource.md)
