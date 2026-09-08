@{
    # Script module or binary module file associated with this manifest.
    RootModule        = 'PS5-Core.UI.psm1'

    # Version number of this module. Single source of truth for the whole
    # library: the four manifests move together. The submodules never ship on
    # their own, so a version of their own would inform nobody and only drift.
    ModuleVersion     = '1.0.0'

    # ID used to uniquely identify this module
    GUID              = '79c6cb38-da66-4543-af14-c03f59666479'

    # Author of this module
    Author            = 'Neuraaak'

    # Company or vendor of this module
    CompanyName       = 'Neuraaak'

    # Copyright statement for this module
    Copyright         = '(c) 2026 Neuraaak. MIT License.'

    # Description of the functionality provided by this module
    Description       = 'Console UI for Windows PowerShell 5.1, no external dependency. Two interchangeable progress strategies: Bar (Write-Progress) and Text (periodic status lines).'

    # Minimum version of the PowerShell engine required by this module.
    # 5.1 is a FLOOR, not a ceiling: CompatiblePSEditions is deliberately left
    # unset so the module also loads under PowerShell 7, which is what lets the
    # two progress strategies be compared side by side on a single machine.
    PowerShellVersion = '5.1'


    # Functions to export from this module
    FunctionsToExport = @(
        'Initialize-EnhancedUI',
        'Get-UIContext',
        'Write-StatusMessage',
        'Write-ProgressBar',
        'Start-ProgressScope',
        'Write-Header',
        'Write-Summary',
        'Read-Selection',
        'Read-FolderSelection'
    )

    # Cmdlets to export from this module
    CmdletsToExport   = @()

    # Variables to export from this module. Deliberately empty: Export-ModuleMember
    # -Variable does not cross the nested-module boundary, so declaring a context
    # variable here would promise an export that never materialises.
    VariablesToExport = @()

    # Aliases to export from this module
    AliasesToExport   = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess
    PrivateData       = @{
        PSData = @{
            Tags         = @('UI', 'Console', 'Progress', 'Output', 'Color')
            LicenseUri   = ''
            ProjectUri   = ''
        }
    }
}
