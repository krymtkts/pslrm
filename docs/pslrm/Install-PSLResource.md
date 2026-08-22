---
document type: cmdlet
external help file: pslrm-Help.xml
HelpUri: https://github.com/krymtkts/pslrm/blob/main/docs/pslrm/Install-PSLResource.md
Locale: en-US
Module Name: pslrm
ms.date: 08-22-2026
PlatyPS schema version: 2024-05-01
title: Install-PSLResource
---

# Install-PSLResource

## SYNOPSIS

Install project-local resources from the lockfile or requirements.

## SYNTAX

### __AllParameterSets

```
Install-PSLResource [[-Path] <string>] [-IncludeDependencies] [-WhatIf] [-Confirm]
```

## ALIASES

## DESCRIPTION

Installs resources under `.pslrm` in the project root.

The command restores exact versions when `psreq.lock.psd1` exists and matches `psreq.psd1`.
Without a lockfile, it resolves `psreq.psd1` and writes a new lockfile.
It then saves the resolved resources.

Use `Update-PSLResource` when requirements and the lockfile are out of sync.

## EXAMPLES

### Example 1

```powershell
Install-PSLResource
```

Installs resources for the pslrm project containing the current directory.

### Example 2

```powershell
Install-PSLResource -Path ./build -IncludeDependencies
```

Finds the project root above `./build` and installs its resources.
The result contains direct and transitive resources.

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
The command always saves the dependencies needed by the locked resources.

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

Returns the installed direct resources as `PSLRM.Resource` objects.
With `IncludeDependencies`, the result also contains transitive resources.

## NOTES

The command fails instead of restoring a stale lockfile.
Run `Update-PSLResource` to resolve the current requirements and refresh the lockfile.

## RELATED LINKS

- [pslrm Module](https://github.com/krymtkts/pslrm/blob/main/docs/pslrm/pslrm.md)
- [Get-InstalledPSLResource](https://github.com/krymtkts/pslrm/blob/main/docs/pslrm/Get-InstalledPSLResource.md)
- [Update-PSLResource](https://github.com/krymtkts/pslrm/blob/main/docs/pslrm/Update-PSLResource.md)
- [Restore-PSLResource](https://github.com/krymtkts/pslrm/blob/main/docs/pslrm/Restore-PSLResource.md)
