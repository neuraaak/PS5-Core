<#
.SYNOPSIS
    PS5-Core - PowerShell utilities suite for Windows PowerShell 5.1.

.DESCRIPTION
    Meta-module that loads all PS5-Core submodules for a one-line import:
    - PS5-Core.Runtime: Windows PowerShell version guard
    - PS5-Core.UI:      console user interface, no external dependency
    - PS5-Core.Crypto:  cryptographic utilities

.NOTES
    Author:  Neuraaak
    License: MIT

.EXAMPLE
    Import-Module PS5-Core
#>

# Meta-module: everything is provided by the nested modules declared in the .psd1.

Write-Verbose "PS5-Core modules loaded successfully"
Write-Verbose "  - PS5-Core.Runtime"
Write-Verbose "  - PS5-Core.UI"
Write-Verbose "  - PS5-Core.Crypto"
