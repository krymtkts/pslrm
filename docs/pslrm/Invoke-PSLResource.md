---
document type: cmdlet
external help file: pslrm-Help.xml
HelpUri: https://github.com/krymtkts/pslrm/blob/main/docs/pslrm/Invoke-PSLResource.md
Locale: en-US
Module Name: pslrm
ms.date: 08-22-2026
PlatyPS schema version: 2024-05-01
title: Invoke-PSLResource
---

# Invoke-PSLResource

## SYNOPSIS

Run a command exported by a project-local resource.

## SYNTAX

### Explicit (Default)

```
Invoke-PSLResource -CommandName <string> [-ArgumentTokens <Object[]>] [-Path <string>]
 [-ExecutionScope <string>]
```

### Natural

```
Invoke-PSLResource [-CommandName] <string> [[-RemainingArgumentTokens] <Object[]>] [-Path <string>]
 [-ExecutionScope <string>]
```

## ALIASES

## DESCRIPTION

Runs a command exported by a resource recorded in the project lockfile.
The command executes in an isolated runspace configured with the project-local store.
It uses the project root as its current directory.

Use the natural parameter set to forward trailing argument tokens directly.
Use `ArgumentTokens` when code constructs the token array explicitly.

## EXAMPLES

### Example 1

```powershell
Invoke-PSLResource Invoke-Build -- -Task UnitTest '.build.ps1'
```

Runs `Invoke-Build` from the project-local store.
The end-of-parameters token prevents `Invoke-PSLResource` from binding `Task`.

### Example 2

```powershell
$tokens = @('-Task', 'UnitTest', '.build.ps1')
Invoke-PSLResource -CommandName Invoke-Build -ArgumentTokens $tokens
```

Runs the same command with an explicitly constructed argument token array.

### Example 3

```powershell
Invoke-PSLResource -Path ./tools Invoke-Pester -- -Path tests
```

Finds the project root above `./tools`.
The command forwards a separate `Path` parameter to the project-local command.

## PARAMETERS

### -ArgumentTokens

The ordered argument tokens to pass to the target command.
Use this parameter when code constructs the tokens explicitly.
`Arguments` is an alias for this parameter.

```yaml
Type: System.Object[]
DefaultValue: ""
SupportsWildcards: false
Aliases:
  - Arguments
ParameterSets:
  - Name: Explicit
    Position: Named
    IsRequired: false
    ValueFromPipeline: false
    ValueFromPipelineByPropertyName: false
    ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ""
```

### -CommandName

The name of a command exported by a single resource in the project-local store.

```yaml
Type: System.String
DefaultValue: ""
SupportsWildcards: false
Aliases: []
ParameterSets:
  - Name: Natural
    Position: 0
    IsRequired: true
    ValueFromPipeline: false
    ValueFromPipelineByPropertyName: false
    ValueFromRemainingArguments: false
  - Name: Explicit
    Position: Named
    IsRequired: true
    ValueFromPipeline: false
    ValueFromPipelineByPropertyName: false
    ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ""
```

### -ExecutionScope

The execution isolation mode.
The default is `IsolatedRunspace`.
The command accepts `InProcess`, but that mode is not implemented.

```yaml
Type: System.String
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
    Position: Named
    IsRequired: false
    ValueFromPipeline: false
    ValueFromPipelineByPropertyName: false
    ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ""
```

### -RemainingArgumentTokens

The trailing tokens captured by the natural parameter set and forwarded to the target command.
Place `--` before tokens that could bind to parameters of `Invoke-PSLResource`.

```yaml
Type: System.Object[]
DefaultValue: ""
SupportsWildcards: false
Aliases: []
ParameterSets:
  - Name: Natural
    Position: 1
    IsRequired: false
    ValueFromPipeline: false
    ValueFromPipelineByPropertyName: false
    ValueFromRemainingArguments: true
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

Returns the output produced by the target command.

## NOTES

The target command must come from a resource in the project-local store.
The command fails if no resource exports the name.
It also fails if more than one resource exports the same name.

The outermost isolated invocation shares the caller host.
Nested invocations use the default runspace host.

## RELATED LINKS

- [pslrm Module](https://github.com/krymtkts/pslrm/blob/main/docs/pslrm/pslrm.md)
- [Get-InstalledPSLResource](https://github.com/krymtkts/pslrm/blob/main/docs/pslrm/Get-InstalledPSLResource.md)
- [Restore-PSLResource](https://github.com/krymtkts/pslrm/blob/main/docs/pslrm/Restore-PSLResource.md)
