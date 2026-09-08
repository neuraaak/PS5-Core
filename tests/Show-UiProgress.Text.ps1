<#
.SYNOPSIS
    Contrôle de la stratégie de progression « Text » : robustesse + rendu.

.DESCRIPTION
    Lanceur mince. Tous les scénarios vivent dans UiProgressChecks.ps1, partagé
    avec Show-UiProgress.Bar.ps1 : c'est la seule façon d'être sûr que les deux
    stratégies sont mesurées exactement pareil.

    Contrairement à Bar, cette stratégie n'ouvre aucune région de console : son
    rendu est donc identique en terminal, en fichier et en tâche planifiée.
    Le volet visuel reste néanmoins à comparer côte à côte avec celui de Bar,
    dans le MÊME terminal, pour que la comparaison soit honnête.

.PARAMETER SkipVisual
    N'exécute que les assertions de robustesse.

.PARAMETER OnlyVisual
    N'exécute que le volet visuel.

.PARAMETER Thorough
    Ajoute le scénario de charge d'impression (un message par item).

.EXAMPLE
    .\Show-UiProgress.Text.ps1
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

$failures = Invoke-UiProgressChecks -ProgressStyle 'Text' -SkipVisual:$SkipVisual -OnlyVisual:$OnlyVisual -Thorough:$Thorough

exit ([int]($failures -gt 0))
