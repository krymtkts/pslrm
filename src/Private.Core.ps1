Set-StrictMode -Version Latest

$script:PSLRMRequirementsFileName = 'psreq.psd1'
$script:PSLRMLockfileFileName = 'psreq.lock.psd1'
$script:PSLRMStoreDirectoryName = '.pslrm'
$script:PSLRMResourceTypeName = 'PSLRM.Resource'

# Internal helpers

function Get-RequirementsPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ProjectRoot
    )

    Join-Path $ProjectRoot $script:PSLRMRequirementsFileName
}

function Get-LockfilePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ProjectRoot
    )

    Join-Path $ProjectRoot $script:PSLRMLockfileFileName
}

function Get-StorePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ProjectRoot
    )

    Join-Path $ProjectRoot $script:PSLRMStoreDirectoryName
}

function ConvertTo-NormalizedVersionString {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Version,

        [Parameter()]
        [AllowNull()]
        [string] $Prerelease
    )

    if ($null -eq $Version) {
        return $null
    }

    $normalized = if ($Version -is [string]) { $Version } else { $Version.ToString() }
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return $null
    }

    $normalized = $normalized.Trim()

    # NOTE: PSResourceGet reports prerelease separately (Version + Prerelease). Preserve it.
    if (-not [string]::IsNullOrWhiteSpace($Prerelease)) {
        $pr = $Prerelease.Trim()
        if (-not [string]::IsNullOrWhiteSpace($pr)) {
            if ($normalized -notmatch '-') {
                return "$normalized-$pr"
            }
        }
    }

    $normalized
}

function ConvertTo-PowerShellDataFileLiteral {
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Value,

        [Parameter(Mandatory)]
        [ValidateRange(0, 16)]
        [int] $IndentLevel,

        [Parameter(Mandatory)]
        [ValidateRange(2, 4)]
        [int] $IndentWidth
    )

    switch ($true) {
        ($null -eq $Value) {
            return '$null'
        }
        ($Value -is [hashtable]) {
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add('@{')

            $keys = [string[]]$Value.Keys
            [System.Array]::Sort($keys, [System.StringComparer]::Ordinal)
            $entryIndent = ' ' * ($IndentWidth * ($IndentLevel + 1))
            $closeIndent = ' ' * ($IndentWidth * $IndentLevel)
            foreach ($key in $keys) {
                $escapedKey = $key -replace "'", "''"
                $keyLiteral = "'$escapedKey'"

                $valLiteral = ConvertTo-PowerShellDataFileLiteral -Value $Value[$key] -IndentLevel ($IndentLevel + 1) -IndentWidth $IndentWidth
                $lines.Add($entryIndent + "$keyLiteral = $valLiteral")
            }

            $lines.Add($closeIndent + '}')
            if ($IndentLevel -eq 0) {
                $lines.Add('')
            }
            return ($lines -join "`n")
        }
        ($Value -is [string]) {
            $escaped = $Value -replace "'", "''"
            return "'$escaped'"
        }
        ($Value -is [bool]) {
            if ($Value) {
                return '$true'
            }
            return '$false'
        }
        ($Value.GetType() -in @([byte], [int16], [int32], [int64], [uint16], [uint32], [uint64], [single], [double], [decimal])) {
            return [string]$Value
        }
        ($Value -is [version]) {
            return "'$($Value.ToString())'"
        }
        ($Value -is [array]) {
            $itemLiterals = [System.Collections.Generic.List[string]]::new()
            foreach ($item in $Value) {
                $itemLiterals.Add((ConvertTo-PowerShellDataFileLiteral -Value $item -IndentLevel ($IndentLevel + 1) -IndentWidth $IndentWidth))
            }
            return '@(' + ($itemLiterals -join ', ') + ')'
        }
        default {
            throw "Unsupported value type for PowerShell data file serialization: $($Value.GetType().FullName)"
        }
    }
}

function Write-PowerShellDataFile {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable] $Data,

        [Parameter()]
        [ValidateRange(2, 4)]
        [int] $IndentWidth = 4
    )

    $directory = Split-Path -Parent -Path $Path
    if ([string]::IsNullOrWhiteSpace($directory)) {
        $directory = (Get-Location).Path
    }

    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory | Out-Null
    }

    $content = ConvertTo-PowerShellDataFileLiteral -Value $Data -IndentLevel 0 -IndentWidth $IndentWidth

    if (-not $PSCmdlet.ShouldProcess($Path, 'Write PowerShell data file')) {
        return
    }

    $tmp = [System.IO.Path]::Combine($directory, [System.IO.Path]::GetRandomFileName())
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)

    try {
        [System.IO.File]::WriteAllText($tmp, $content, $utf8NoBom)
        Move-Item -LiteralPath $tmp -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $tmp) {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }
}

function Read-Lockfile {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ -not [string]::IsNullOrWhiteSpace($_) })]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Lockfile not found: $Path"
    }

    $data = Import-PowerShellDataFile -Path $Path
    if ($data -isnot [hashtable]) {
        throw "Lockfile must be a hashtable: $Path"
    }

    $data
}

function Write-Lockfile {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ -not [string]::IsNullOrWhiteSpace($_) })]
        [string] $Path,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable] $Data
    )

    # NOTE: indent width is fixed to 4 for lockfile to ensure deterministic output.
    Write-PowerShellDataFile -Path $Path -Data $Data -IndentWidth 4
}

function Find-ProjectRoot {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [ValidateNotNullOrWhiteSpace()]
        [string] $Path = (Get-Location).Path
    )

    $cursor = $Path

    if (Test-Path -LiteralPath $cursor -PathType Leaf) {
        $cursor = Split-Path -Parent -Path $cursor
    }

    if (-not (Test-Path -LiteralPath $cursor -PathType Container)) {
        throw "Path not found or not a directory: $Path"
    }

    $cursor = (Resolve-Path -LiteralPath $cursor).Path

    while ($true) {
        $requirementsPath = Get-RequirementsPath -ProjectRoot $cursor
        if (Test-Path -LiteralPath $requirementsPath) {
            return $cursor
        }

        $parent = Split-Path -Parent -Path $cursor
        if ([string]::IsNullOrWhiteSpace($parent) -or ($parent -eq $cursor)) {
            break
        }
        $cursor = $parent
    }

    throw "Project root not found. Missing psreq.psd1 from: $Path"
}

function New-PSLRMResourceObject {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter()]
        [AllowNull()]
        [string] $Version,

        [Parameter()]
        [AllowNull()]
        [string] $Repository,

        [Parameter(Mandatory)]
        [bool] $IsDirect,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ProjectRoot
    )

    $resource = [pscustomobject][ordered]@{
        Name = $Name
        Version = $Version
        Repository = $Repository
        IsDirect = $IsDirect
        ProjectRoot = $ProjectRoot
    }

    $resource.PSObject.TypeNames.Insert(0, $script:PSLRMResourceTypeName)
    $resource
}

function New-Resource {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter()]
        [AllowNull()]
        [object] $Version,

        [Parameter()]
        [AllowNull()]
        [string] $Prerelease,

        [Parameter()]
        [AllowNull()]
        [string] $Repository,

        [Parameter(Mandatory)]
        [bool] $IsDirect,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ProjectRoot
    )

    $normalizedVersion = ConvertTo-NormalizedVersionString -Version $Version -Prerelease $Prerelease

    New-PSLRMResourceObject -Name $Name -Version $normalizedVersion -Repository $Repository -IsDirect $IsDirect -ProjectRoot $ProjectRoot
}

function Get-LockfileResourceNames {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable] $LockData
    )

    $names = [string[]]$LockData.Keys
    [System.Array]::Sort($names, [System.StringComparer]::Ordinal)
    $names
}

function ConvertTo-PSLResourceInvocationArguments {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.CommandInfo] $Command,

        [Parameter()]
        [AllowNull()]
        [object[]] $Arguments
    )

    $namedArguments = @{}
    $positionalArguments = [System.Collections.Generic.List[object]]::new()

    if ($null -eq $Arguments) {
        $Arguments = @()
    }

    for ($index = 0; $index -lt $Arguments.Count; $index++) {
        $argument = $Arguments[$index]

        if (($argument -is [string]) -and $argument.StartsWith('-') -and ($argument.Length -gt 1)) {
            $parameterName = $argument.Substring(1)
            $parameter = $null

            foreach ($candidateName in $Command.Parameters.Keys) {
                if ($candidateName -ieq $parameterName) {
                    $parameter = $Command.Parameters[$candidateName]
                    $parameterName = $candidateName
                    break
                }
            }

            if ($null -ne $parameter) {
                $nextIndex = $index + 1
                $isSwitch = ($parameter.ParameterType -eq [System.Management.Automation.SwitchParameter]) -or ($parameter.ParameterType -eq [bool])
                $hasValue = $nextIndex -lt $Arguments.Count

                if ($isSwitch) {
                    if ($hasValue -and ($Arguments[$nextIndex] -isnot [string] -or -not $Arguments[$nextIndex].StartsWith('-'))) {
                        $namedArguments[$parameterName] = $Arguments[$nextIndex]
                        $index++
                    }
                    else {
                        $namedArguments[$parameterName] = $true
                    }
                }
                else {
                    if (-not $hasValue) {
                        throw "Missing value for parameter '$argument'."
                    }

                    $namedArguments[$parameterName] = $Arguments[$nextIndex]
                    $index++
                }

                continue
            }
        }

        $positionalArguments.Add($argument)
    }

    [pscustomobject]@{
        NamedArguments = $namedArguments
        PositionalArguments = $positionalArguments.ToArray()
    }
}

function Invoke-PSLResourceRunspaceCommand {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ProjectRoot,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $StorePath,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [string[]] $ModuleNames,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $CommandName,

        [Parameter()]
        [AllowNull()]
        [object[]] $Arguments
    )

    Set-Location -LiteralPath $ProjectRoot

    $separator = [string][System.IO.Path]::PathSeparator
    $currentModulePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'Process')
    $modulePathEntries = [System.Collections.Generic.List[string]]::new()
    $modulePathEntries.Add($StorePath)

    if (-not [string]::IsNullOrWhiteSpace($currentModulePath)) {
        foreach ($entry in ($currentModulePath -split [regex]::Escape($separator))) {
            if ([string]::IsNullOrWhiteSpace($entry)) {
                continue
            }

            if (-not $modulePathEntries.Contains($entry)) {
                $modulePathEntries.Add($entry)
            }
        }
    }

    [Environment]::SetEnvironmentVariable('PSModulePath', ($modulePathEntries.ToArray() -join $separator), 'Process')

    $importedModuleNames = [System.Collections.Generic.List[string]]::new()
    $missingModuleNames = [System.Collections.Generic.List[string]]::new()

    foreach ($moduleName in $ModuleNames) {
        $availableModules = @(Get-Module -ListAvailable -Name $moduleName)
        if ($availableModules.Count -eq 0) {
            $missingModuleNames.Add($moduleName)
            continue
        }

        $selectedModule = $availableModules | Sort-Object Version -Descending | Select-Object -First 1
        $importedModule = Import-Module -Name $selectedModule.Path -Force -PassThru
        $importedModuleNames.Add($importedModule.Name)
    }

    if ($missingModuleNames.Count -gt 0) {
        throw "Local resources missing from store: $($missingModuleNames.ToArray() -join ', '). Run Restore-PSLResource."
    }

    $commands = @(Get-Command -Name $CommandName -Module $importedModuleNames.ToArray() -All -ErrorAction SilentlyContinue)
    $candidateModuleNames = @(
        $commands |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_.Source) } |
            ForEach-Object Source |
            Sort-Object -Unique
    )

    if ($candidateModuleNames.Count -eq 0) {
        throw "Command '$CommandName' was not found in local resources: $($importedModuleNames.ToArray() -join ', ')."
    }

    if ($candidateModuleNames.Count -gt 1) {
        throw "Command '$CommandName' is exported by multiple local resources: $($candidateModuleNames -join ', ')."
    }

    $resolvedArguments = ConvertTo-PSLResourceInvocationArguments -Command @($commands)[0] -Arguments $Arguments
    $namedArguments = [hashtable]$resolvedArguments.NamedArguments
    $remainingArguments = [object[]]$resolvedArguments.PositionalArguments

    & $CommandName @namedArguments @remainingArguments
}

function New-PSLResourceDataAddedSubscription {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Collection,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Queue
    )

    $handler = [System.EventHandler[System.Management.Automation.DataAddedEventArgs]]({
            $null = $Queue.Enqueue($args[0][$args[1].Index])
        }.GetNewClosure())

    $Collection.add_DataAdded($handler)

    [pscustomobject]@{
        Collection = $Collection
        Handler = $handler
    }
}

function Remove-PSLResourceDataAddedSubscription {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [pscustomobject] $Subscription
    )

    if ($null -eq $Subscription) {
        return
    }

    if (($null -ne $Subscription.Collection) -and ($null -ne $Subscription.Handler)) {
        $Subscription.Collection.remove_DataAdded($Subscription.Handler)
    }
}

function Invoke-PSLResourceQueuedStreamDrain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [pscustomobject[]] $Forwarders,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $ErrorQueue,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $ErrorRecords
    )

    $typedErrorRecords = [System.Collections.Generic.List[System.Management.Automation.ErrorRecord]]$ErrorRecords

    do {
        $drainedAny = $false

        foreach ($forwarder in $Forwarders) {
            $record = $null

            while ($forwarder.Queue.TryDequeue([ref]$record)) {
                $drainedAny = $true
                & $forwarder.Action $record
                $record = $null
            }
        }

        $errorRecord = $null
        while ($ErrorQueue.TryDequeue([ref]$errorRecord)) {
            $drainedAny = $true
            $typedErrorRecords.Add($errorRecord) | Out-Null
            $errorRecord = $null
        }
    } while ($drainedAny)
}

function Resolve-PSLResourceInvocationError {
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorRecord])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.ErrorRecord] $ErrorRecord
    )

    $currentException = $ErrorRecord.Exception
    $resolvedErrorRecord = $ErrorRecord

    while ($null -ne $currentException) {
        $errorRecordProperty = $currentException.PSObject.Properties['ErrorRecord']
        if ($null -ne $errorRecordProperty) {
            $innerErrorRecord = $errorRecordProperty.Value
            if (($innerErrorRecord -is [System.Management.Automation.ErrorRecord]) -and (-not [object]::ReferenceEquals($innerErrorRecord, $ErrorRecord))) {
                $resolvedErrorRecord = $innerErrorRecord
            }
        }

        $currentException = $currentException.InnerException
    }

    $resolvedErrorRecord
}

function Invoke-PSLResourceInIsolatedRunspace {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ProjectRoot,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $CommandName,

        [Parameter()]
        [AllowNull()]
        [object[]] $Arguments
    )

    $lockfilePath = Get-LockfilePath -ProjectRoot $ProjectRoot
    $storePath = Get-StorePath -ProjectRoot $ProjectRoot

    if (-not (Test-Path -LiteralPath $storePath -PathType Container)) {
        throw "Store path not found. Run Restore-PSLResource to recreate local resources: $storePath"
    }

    $lockData = Read-Lockfile -Path $lockfilePath
    $moduleNames = [string[]]@(Get-LockfileResourceNames -LockData $lockData)
    if ($moduleNames.Count -eq 0) {
        throw "Lockfile does not contain any local resources: $lockfilePath"
    }

    if ($null -eq $Arguments) {
        $Arguments = @()
    }

    # NOTE: Top-level isolated invocations need the caller host so host-aware output survives the
    # async BeginInvoke forwarding path. Nested isolated invocations must not reuse the current
    # runspace host, because propagating child hosts destabilizes nested build/test flows.
    # Track nesting depth so only depth 0 reuses $Host and deeper isolated runspaces fall back to
    # the default host created from InitialSessionState.
    #
    # NOTE: PSHOST-tagged InformationRecords need special handling when depth 0 shares $Host.
    # With a shared host, Write-Host is already rendered directly by that host. If PSLRM also
    # forwards the same PSHOST record from Streams.Information, the caller sees the same host
    # message twice. Nested isolated runspaces do not share the original caller host, so their
    # PSHOST records still need normal information-stream forwarding.
    $isolatedRunspaceDepthVariableName = 'PSLRMIsolatedRunspaceDepth'
    $isolatedRunspaceDepthVariable = $ExecutionContext.SessionState.PSVariable.Get($isolatedRunspaceDepthVariableName)
    $isolatedRunspaceDepth = if ($null -ne $isolatedRunspaceDepthVariable) {
        [int]$isolatedRunspaceDepthVariable.Value
    }
    else {
        0
    }

    $initialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $argumentResolverName = 'ConvertTo-PSLResourceInvocationArguments'
    $argumentResolverDefinition = (Get-Command $argumentResolverName -CommandType Function).ScriptBlock.ToString()
    $runspaceInvokerName = 'Invoke-PSLResourceRunspaceCommand'
    $runspaceInvokerDefinition = (Get-Command $runspaceInvokerName -CommandType Function).ScriptBlock.ToString()
    $initialSessionState.Variables.Add(
        [System.Management.Automation.Runspaces.SessionStateVariableEntry]::new(
            $isolatedRunspaceDepthVariableName,
            ($isolatedRunspaceDepth + 1),
            'Current nesting depth for PSLRM isolated runspaces.'
        )
    ) | Out-Null
    $initialSessionState.Commands.Add(
        [System.Management.Automation.Runspaces.SessionStateFunctionEntry]::new(
            $argumentResolverName,
            $argumentResolverDefinition
        )
    ) | Out-Null
    $initialSessionState.Commands.Add(
        [System.Management.Automation.Runspaces.SessionStateFunctionEntry]::new(
            $runspaceInvokerName,
            $runspaceInvokerDefinition
        )
    ) | Out-Null

    $shareCallerHost = $isolatedRunspaceDepth -eq 0

    $runspace = if ($shareCallerHost) {
        [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($Host, $initialSessionState)
    }
    else {
        [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($initialSessionState)
    }
    $runspace.Open()

    $outputCollection = $null
    $streamForwarders = @()
    $errorSubscription = $null

    try {
        $powerShell = [System.Management.Automation.PowerShell]::Create()
        $powerShell.Runspace = $runspace
        $powerShell = $powerShell.AddCommand($runspaceInvokerName)
        $powerShell = $powerShell.AddParameter('ProjectRoot', $ProjectRoot)
        $powerShell = $powerShell.AddParameter('StorePath', $storePath)
        $powerShell = $powerShell.AddParameter('ModuleNames', $moduleNames)
        $powerShell = $powerShell.AddParameter('CommandName', $CommandName)
        $powerShell = $powerShell.AddParameter('Arguments', $Arguments)

        $outputCollection = [System.Management.Automation.PSDataCollection[psobject]]::new()
        $inputCollection = [System.Management.Automation.PSDataCollection[psobject]]::new()
        $inputCollection.Complete()

        $streamForwarders = @(
            [pscustomobject]@{
                Collection = $outputCollection
                Queue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
                Action = { param($record) $PSCmdlet.WriteObject($record) }
                Subscription = $null
            }
            [pscustomobject]@{
                Collection = $powerShell.Streams.Debug
                Queue = [System.Collections.Concurrent.ConcurrentQueue[System.Management.Automation.DebugRecord]]::new()
                Action = { param($record) $PSCmdlet.WriteDebug($record.Message) }
                Subscription = $null
            }
            [pscustomobject]@{
                Collection = $powerShell.Streams.Verbose
                Queue = [System.Collections.Concurrent.ConcurrentQueue[System.Management.Automation.VerboseRecord]]::new()
                Action = { param($record) $PSCmdlet.WriteVerbose($record.Message) }
                Subscription = $null
            }
            [pscustomobject]@{
                Collection = $powerShell.Streams.Warning
                Queue = [System.Collections.Concurrent.ConcurrentQueue[System.Management.Automation.WarningRecord]]::new()
                Action = { param($record) $PSCmdlet.WriteWarning($record.Message) }
                Subscription = $null
            }
            [pscustomobject]@{
                Collection = $powerShell.Streams.Information
                Queue = [System.Collections.Concurrent.ConcurrentQueue[System.Management.Automation.InformationRecord]]::new()
                Action = {
                    param($record)

                    $isHostRecord = ($null -ne $record.Tags) -and ($record.Tags -contains 'PSHOST')
                    # NOTE: Shared-host top-level invocations already rendered this host message.
                    # Re-forwarding the PSHOST record would duplicate the visible output.
                    if ($shareCallerHost -and $isHostRecord) {
                        return
                    }

                    $PSCmdlet.WriteInformation($record)
                }
                Subscription = $null
            }
            [pscustomobject]@{
                Collection = $powerShell.Streams.Progress
                Queue = [System.Collections.Concurrent.ConcurrentQueue[System.Management.Automation.ProgressRecord]]::new()
                Action = { param($record) $PSCmdlet.WriteProgress($record) }
                Subscription = $null
            }
        )

        $errorQueue = [System.Collections.Concurrent.ConcurrentQueue[System.Management.Automation.ErrorRecord]]::new()
        $errorRecords = [System.Collections.Generic.List[System.Management.Automation.ErrorRecord]]::new()

        foreach ($forwarder in $streamForwarders) {
            $forwarder.Subscription = New-PSLResourceDataAddedSubscription -Collection $forwarder.Collection -Queue $forwarder.Queue
        }

        $errorSubscription = New-PSLResourceDataAddedSubscription -Collection $powerShell.Streams.Error -Queue $errorQueue

        $drainQueues = {
            Invoke-PSLResourceQueuedStreamDrain -Forwarders $streamForwarders -ErrorQueue $errorQueue -ErrorRecords $errorRecords
        }

        $asyncResult = $null
        $endInvokeError = $null

        try {
            $asyncResult = $powerShell.BeginInvoke($inputCollection, $outputCollection)

            while (-not $asyncResult.AsyncWaitHandle.WaitOne(50)) {
                & $drainQueues
            }

            $powerShell.EndInvoke($asyncResult) | Out-Null
        }
        catch {
            $endInvokeError = Resolve-PSLResourceInvocationError -ErrorRecord $_
        }

        & $drainQueues

        if ($errorRecords.Count -gt 0) {
            $PSCmdlet.ThrowTerminatingError((Resolve-PSLResourceInvocationError -ErrorRecord $errorRecords[0]))
        }

        if ($null -ne $endInvokeError) {
            $PSCmdlet.ThrowTerminatingError($endInvokeError)
        }
    }
    finally {
        foreach ($forwarder in $streamForwarders) {
            Remove-PSLResourceDataAddedSubscription -Subscription $forwarder.Subscription
        }
        Remove-PSLResourceDataAddedSubscription -Subscription $errorSubscription
        if ($null -ne $powerShell) {
            $powerShell.Dispose()
        }
        if ($null -ne $runspace) {
            $runspace.Dispose()
        }
    }
}
