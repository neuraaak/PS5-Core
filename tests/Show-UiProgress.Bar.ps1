<#
.SYNOPSIS
    Contrôle de la stratégie de progression « Bar » : robustesse + rendu.

.DESCRIPTION
    Lanceur mince. Tous les scénarios vivent dans UiProgressChecks.ps1, partagé
    avec Show-UiProgress.Text.ps1 : c'est la seule façon d'être sûr que les deux
    stratégies sont mesurées exactement pareil.

    Le volet rendu n'a de sens que dans un VRAI terminal : en sortie redirigée,
    Write-Progress ne dessine rien et la comparaison serait faussée.

.PARAMETER SkipVisual
    N'exécute que les assertions de robustesse. Utilisable sans terminal.

.PARAMETER OnlyVisual
    N'exécute que le volet visuel.

.PARAMETER Thorough
    Ajoute le scénario de charge d'impression (un message par item).

.EXAMPLE
    .\Show-UiProgress.Bar.ps1
#>

#Requires -Version 5.1

[CmdletBinding()]
param(
    [switch]$SkipVisual,
    [switch]$OnlyVisual,
    [switch]$Thorough
)

$repoRoot = Split-Path -Parent $PSScriptRoot

if ($env:PSModulePath -notlike "*$repoRoot*") {
    $env:PSModulePath += ";$repoRoot"
}

try {
    Import-Module PS5-Core -Force -ErrorAction Stop
}
catch {
    Write-Host "FATAL: cannot load PS5-Core: $_" -ForegroundColor Red
    exit 2
}

. (Join-Path $PSScriptRoot 'UiProgressChecks.ps1')

$failures = Invoke-UiProgressChecks -ProgressStyle 'Bar' -SkipVisual:$SkipVisual -OnlyVisual:$OnlyVisual -Thorough:$Thorough

exit ([int]($failures -gt 0))
