---
document type: cmdlet
external help file: pslrm-Help.xml
HelpUri: https://github.com/krymtkts/pslrm/blob/main/docs/pslrm/Update-PSLResource.md
Locale: en-US
Module Name: pslrm
ms.date: 08-22-2026
PlatyPS schema version: 2024-05-01
title: Update-PSLResource
---

# Update-PSLResource

## SYNOPSIS

Resolve requirements and update the project lockfile and local store.

## SYNTAX

### __AllParameterSets

```
Update-PSLResource [[-Path] <string>] [-IncludeDependencies] [-WhatIf] [-Confirm]
```

## ALIASES

## DESCRIPTION

Resolves every direct dependency declared in `psreq.psd1`.
The command writes the resulting exact versions to `psreq.lock.psd1`.
It then replaces the project-local store with the resolved resources.

Use this command after changing requirements or when intentionally updating dependency versions.

## EXAMPLES

### Example 1

```powershell
Update-PSLResource
```

Resolves requirements for the pslrm project containing the current directory.

### Example 2

```powershell
Update-PSLResource -Path . -IncludeDependencies
```

Updates the lockfile and local store, then returns direct and transitive resources.

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

### -IncludeDependencies

Includes transitive dependencies in the output.
The command always records and saves the dependencies returned by PSResourceGet.

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

Returns the resolved direct resources as `PSLRM.Resource` objects.
With `IncludeDependencies`, the result also contains transitive resources.

## NOTES

This command uses requirements as its source of truth.
Use `Restore-PSLResource` to reproduce the versions already recorded in the lockfile.

## RELATED LINKS

- [pslrm Module](https://github.com/krymtkts/pslrm/blob/main/docs/pslrm/pslrm.md)
- [Get-InstalledPSLResource](https://github.com/krymtkts/pslrm/blob/main/docs/pslrm/Get-InstalledPSLResource.md)
- [Install-PSLResource](https://github.com/krymtkts/pslrm/blob/main/docs/pslrm/Install-PSLResource.md)
- [Restore-PSLResource](https://github.com/krymtkts/pslrm/blob/main/docs/pslrm/Restore-PSLResource.md)
