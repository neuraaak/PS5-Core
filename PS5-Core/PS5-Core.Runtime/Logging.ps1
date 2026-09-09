<#
.SYNOPSIS
    File logging for PS5-Core, opt-in and dependency-free.

.DESCRIPTION
    Nothing is written until a script calls Initialize-Logging: a library that
    creates files nobody asked for is intrusive, and on a locked-down machine
    the writable path is not guessable.

    Initialize-Logging MAY throw - the caller explicitly asked for logging, so a
    path it cannot use is a real error. Write-Log NEVER throws: a logger that
    kills the workload it observes is worse than no logger at all. On the first
    write failure it disables itself, warns once, and lets the script continue.

    Entries are appended one call at a time, with no buffering, so a script
    killed by the task scheduler still leaves behind everything it had written.

.NOTES
    Author:  Neuraaak
    License: MIT
#>

#region Module State

# Enabled stays $false until Initialize-Logging succeeds, and drops back to
# $false for good on the first write failure.
$script:LogContext = @{
    Enabled      = $false
    Path         = $null
    MinimumLevel = 'Info'
}

# Ordering used by the level filter. Lower number = more verbose.
$script:LogLevelRank = @{
    Debug   = 0
    Info    = 1
    Warning = 2
    Error   = 3
}

#endregion


#region Public Functions

<#
.SYNOPSIS
    Turns file logging on for the current session.

.DESCRIPTION
    Creates the parent directory if needed and appends to the file once to prove
    it is writable. Calling it again re-targets the log; a logger that had
    disabled itself is re-enabled.

.PARAMETER Path
    Full path of the log file. Include a timestamp in the name if you want one
    file per run - this module does no rotation on purpose.

.PARAMETER MinimumLevel
    Lowest level actually written. Debug, Info (default), Warning or Error.

.EXAMPLE
    Initialize-Logging -Path "$env:LOCALAPPDATA\MyScript\run.log"

.EXAMPLE
    Initialize-Logging -Path .\debug.log -MinimumLevel Debug
#>
function Initialize-Logging {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Debug', 'Info', 'Warning', 'Error')]
        [string]$MinimumLevel = 'Info'
    )

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        # Deliberately not wrapped in a try: an unusable path is a real error
        # here, and the caller asked for logging explicitly.
        New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null
    }

    # Touch the file so an unwritable location fails now, not mid-run.
    Add-Content -LiteralPath $Path -Value '' -Encoding UTF8 -ErrorAction Stop

    $script:LogContext.Path = $Path
    $script:LogContext.MinimumLevel = $MinimumLevel
    $script:LogContext.Enabled = $true
}

<#
.SYNOPSIS
    Writes one line to the log, if logging is on and the level passes.

.DESCRIPTION
    A no-op when logging was never initialized or has disabled itself. Never
    throws: any write failure disables logging and emits a single warning.

.PARAMETER Message
    Text to record. Newlines are flattened so one entry stays one line.

.PARAMETER Level
    Debug, Info (default), Warning or Error.

.EXAMPLE
    Write-Log -Message 'Archive extracted' -Level Info
#>
function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Debug', 'Info', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )

    if (-not $script:LogContext.Enabled) { return }
    if ($script:LogLevelRank[$Level] -lt $script:LogLevelRank[$script:LogContext.MinimumLevel]) { return }

    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
    $flat = ($Message -replace '\r?\n', ' ')
    $line = '{0} [{1,-7}] {2}' -f $stamp, $Level.ToUpperInvariant(), $flat

    try {
        # Add-Content silently recreates a missing FILE but not a missing
        # DIRECTORY; checking the parent is what makes a vanished target an
        # error instead of a silent resurrection somewhere unexpected.
        $parent = Split-Path -Parent $script:LogContext.Path
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            throw "Log directory no longer exists: $parent"
        }
        Add-Content -LiteralPath $script:LogContext.Path -Value $line -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        $script:LogContext.Enabled = $false
        Write-Warning "Logging disabled after a write failure on '$($script:LogContext.Path)': $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Returns the current logging state.

.DESCRIPTION
    A function rather than an exported variable: Export-ModuleMember -Variable
    does not cross the nested-submodule boundary, so a variable would work on a
    direct submodule import and silently vanish after Import-Module PS5-Core.

.EXAMPLE
    if ((Get-LogContext).Enabled) { Write-Log -Message 'still on' }

.OUTPUTS
    Hashtable. Keys: Enabled, Path, MinimumLevel.
#>
function Get-LogContext {
    [CmdletBinding()]
    param ()

    return $script:LogContext.Clone()
}

#endregion
