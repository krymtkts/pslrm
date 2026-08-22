---
document type: cmdlet
external help file: pslrm-Help.xml
HelpUri: https://github.com/krymtkts/pslrm/blob/main/docs/pslrm/Restore-PSLResource.md
Locale: en-US
Module Name: pslrm
ms.date: 08-22-2026
PlatyPS schema version: 2024-05-01
title: Restore-PSLResource
---

# Restore-PSLResource

## SYNOPSIS

Restore project-local resources from the lockfile.

## SYNTAX

### __AllParameterSets

```
Restore-PSLResource [[-Path] <string>] [-IncludeDependencies] [-WhatIf] [-Confirm]
```

## ALIASES

## DESCRIPTION

Replaces the `.pslrm` directory with the exact resource versions recorded in `psreq.lock.psd1`.
The command does not resolve requirements and leaves the lockfile unchanged.

The command reads the requirements file to identify which locked resources are direct dependencies.

## EXAMPLES

### Example 1

```powershell
Restore-PSLResource
```

Restores project-local resources for the pslrm project containing the current directory.

### Example 2

```powershell
Restore-PSLResource -Path . -IncludeDependencies
```

Restores exact locked versions and returns direct and transitive resources.

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
The command always restores all resources recorded in the lockfile.

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

Returns the restored direct resources as `PSLRM.Resource` objects.
With `IncludeDependencies`, the result also contains transitive resources.

## NOTES

The command fails when `psreq.lock.psd1` is missing.
Run `Update-PSLResource` to create a lockfile from the current requirements.

## RELATED LINKS

- [pslrm Module](https://github.com/krymtkts/pslrm/blob/main/docs/pslrm/pslrm.md)
- [Get-InstalledPSLResource](https://github.com/krymtkts/pslrm/blob/main/docs/pslrm/Get-InstalledPSLResource.md)
- [Install-PSLResource](https://github.com/krymtkts/pslrm/blob/main/docs/pslrm/Install-PSLResource.md)
- [Update-PSLResource](https://github.com/krymtkts/pslrm/blob/main/docs/pslrm/Update-PSLResource.md)
