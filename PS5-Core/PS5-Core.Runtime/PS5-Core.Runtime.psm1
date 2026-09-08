<#
.SYNOPSIS
    Windows PowerShell runtime guard module.

.DESCRIPTION
    A single guard function ensuring scripts run under Windows PowerShell 5.1+.

.NOTES
    Author:  Neuraaak
    License: MIT
#>

#region Public Functions

<#
.SYNOPSIS
    Stops the script with a clear error if not running under PowerShell 5.1+.

.DESCRIPTION
    Call this at the top of every entry-point script to fail fast with an
    actionable message instead of hitting unrelated errors further down.

    5.1 is a FLOOR, not a ceiling: the guard passes under PowerShell 7 too. It
    answers "is this host new enough", never "is this host Windows PowerShell".
    A script that genuinely requires the Desktop edition must test
    $PSVersionTable.PSEdition itself - that is a different question, and folding
    it in here would make the guard lie about its name.

.PARAMETER MinimumVersion
    Minimum PowerShell version required. Default is 5.1.

.EXAMPLE
    Assert-PowerShell5
#>
function Assert-PowerShell5 {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [version]$MinimumVersion = '5.1'
    )

    if ($PSVersionTable.PSVersion -ge $MinimumVersion) {
        return
    }

    throw "This script requires Windows PowerShell $MinimumVersion or higher (currently running $($PSVersionTable.PSVersion)). Windows PowerShell 5.1 ships with Windows 10 and later; check that .ps1 files are handled by powershell.exe."
}

#endregion


#region Module Initialization

Export-ModuleMember -Function @(
    'Assert-PowerShell5'
)

#endregion
