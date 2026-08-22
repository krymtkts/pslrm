---
document type: cmdlet
external help file: pslrm-Help.xml
HelpUri: https://github.com/krymtkts/pslrm/blob/main/docs/pslrm/Uninstall-PSLResource.md
Locale: en-US
Module Name: pslrm
ms.date: 08-22-2026
PlatyPS schema version: 2024-05-01
title: Uninstall-PSLResource
---

# Uninstall-PSLResource

## SYNOPSIS

Remove direct resources from a pslrm project.

## SYNTAX

### __AllParameterSets

```
Uninstall-PSLResource [[-Path] <string>] [-Name] <string[]> [-WhatIf] [-Confirm]
```

## ALIASES

## DESCRIPTION

Removes the specified direct dependencies from `psreq.psd1`.
The command resolves the remaining requirements and rewrites `psreq.lock.psd1`.
It then replaces the project-local store.

If no requirements remain, the command writes an empty lockfile.
The project then has no local resource store.

## EXAMPLES

### Example 1

```powershell
Uninstall-PSLResource -Name Pester
```

Removes `Pester` from the pslrm project containing the current directory.
The command rebuilds the lockfile and local store.

### Example 2

```powershell
Uninstall-PSLResource -Path ./build -Name Pester, PSScriptAnalyzer
```

Finds the project root above `./build` and removes two direct dependencies.

## PARAMETERS

### -Confirm

Prompts you for confirmation before running the cmdlet.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ""
SupportsWildcards: false
Aliases:
  - cf
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

### -Name

The names of direct dependencies to remove.
Every name must exist in `psreq.psd1`.

```yaml
Type: System.String[]
DefaultValue: ""
SupportsWildcards: false
Aliases: []
ParameterSets:
  - Name: (All)
    Position: 1
    IsRequired: true
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

### -WhatIf

Reports what would happen without performing the actions.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: ""
SupportsWildcards: false
Aliases:
  - wi
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable.
For more information, see [about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### System.Object

Returns the remaining direct resources as `PSLRM.Resource` objects.
The command returns no objects when no requirements remain.

## NOTES

This command removes requirements, not arbitrary transitive dependencies.
PSResourceGet determines the transitive dependencies of the remaining direct resources.

## RELATED LINKS

- [pslrm Module](https://github.com/krymtkts/pslrm/blob/main/docs/pslrm/pslrm.md)
- [Get-InstalledPSLResource](https://github.com/krymtkts/pslrm/blob/main/docs/pslrm/Get-InstalledPSLResource.md)
- [Install-PSLResource](https://github.com/krymtkts/pslrm/blob/main/docs/pslrm/Install-PSLResource.md)
- [Update-PSLResource](https://github.com/krymtkts/pslrm/blob/main/docs/pslrm/Update-PSLResource.md)
