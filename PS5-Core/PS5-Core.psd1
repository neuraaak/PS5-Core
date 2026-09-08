@{
    # Script module or binary module file associated with this manifest.
    RootModule        = 'PS5-Core.psm1'

    # Version number of this module. Single source of truth for the whole
    # library: the four manifests move together. The submodules never ship on
    # their own, so a version of their own would inform nobody and only drift.
    ModuleVersion     = '1.0.0'

    # ID used to uniquely identify this module
    GUID              = '72f309e7-8582-4cb1-8fe9-202e71a4cc43'

    # Author of this module
    Author            = 'Neuraaak'

    # Company or vendor of this module
    CompanyName       = 'Neuraaak'

    # Copyright statement for this module
    Copyright         = '(c) 2026 Neuraaak. MIT License.'

    # Description of the functionality provided by this module
    Description       = 'PS5-Core - PowerShell utilities for Windows PowerShell 5.1: runtime guard, console UI, cryptographic hashing. Cmdlet-first, no external dependency.'

    # Minimum version of the PowerShell engine required by this module.
    # 5.1 is a FLOOR, not a ceiling: CompatiblePSEditions is deliberately left
    # unset so the module also loads under PowerShell 7, which is what lets the
    # two progress strategies be compared side by side on a single machine.
    PowerShellVersion = '5.1'

    NestedModules     = @(
        'PS5-Core.Runtime\PS5-Core.Runtime.psd1',
        'PS5-Core.UI\PS5-Core.UI.psd1',
        'PS5-Core.Crypto\PS5-Core.Crypto.psd1'
    )

    # Functions to export from this module
    FunctionsToExport = @(
        'Assert-PowerShell5',
        'Initialize-EnhancedUI',
        'Get-UIContext',
        'Write-StatusMessage',
        'Write-ProgressBar',
        'Start-ProgressScope',
        'Write-Header',
        'Write-Summary',
        'Read-Selection',
        'Read-FolderSelection',
        'Get-FileHashExtended',
        'Get-StringHash',
        'Test-FileIntegrity'
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
            Tags         = @('PowerShell', 'Utilities', 'UI', 'Crypto', 'Runtime', 'Core', 'WindowsPowerShell')
            LicenseUri   = ''
            ProjectUri   = ''
            ReleaseNotes = @'
v1.0.0
- Port of PS7-Core to Windows PowerShell 5.1, same public surface.
- PS5-Core.UI: two progress strategies (Bar / Text) resolved once by
  Initialize-EnhancedUI. Spectre has no 5.1 equivalent and $PSStyle does not
  exist before 7.2, so the Minimal progress view PS7-Core relies on is not
  available here.
- PS5-Core.Runtime: Assert-PowerShell5 floor guard.
- PS5-Core.Crypto: file and string hashing, paths resolved literally.
'@
        }
    }
}
