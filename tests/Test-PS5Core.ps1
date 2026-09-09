<#
.SYNOPSIS
    Suite de tests automatisés pour PS5-Core.

.DESCRIPTION
    Vérifie PS5-Core.Runtime (garde 5.1), PS5-Core.UI (contrats et sélection de
    dossiers) et PS5-Core.Crypto (hachage comparé à des vecteurs de référence
    publics, pas à une seconde exécution du même code).

    La suite doit passer dans les DEUX stratégies de progression. Les cas qui
    inspectent des internes propres à une stratégie s'ignorent proprement dans
    l'autre passe. Elle ne juge aucun RENDU : c'est le rôle de
    Show-UiProgress.Bar.ps1 / .Text.ps1, en terminal réel.

.PARAMETER ProgressStyle
    Stratégie à tester. Bar (défaut) ou Text.

.PARAMETER OnlyRuntime
    N'exécute que les tests PS5-Core.Runtime.

.PARAMETER OnlyUI
    N'exécute que les tests PS5-Core.UI.

.EXAMPLE
    .\Test-PS5Core.ps1

.EXAMPLE
    .\Test-PS5Core.ps1 -ProgressStyle Text
#>

#Requires -Version 5.1

[CmdletBinding()]
param(
    [ValidateSet('Bar', 'Text')]
    [string]$ProgressStyle = 'Bar',

    [switch]$OnlyRuntime,
    [switch]$OnlyUI
)

$ErrorActionPreference = 'Continue'

#region Test framework
################################################################################

$script:TestStats = @{ Pass = 0; Fail = 0; Skip = 0 }
$script:TestFailures = @()

function Write-TestHeader {
    param([string]$Title)
    Write-Host ""
    Write-Host ("=" * 72) -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host ("=" * 72) -ForegroundColor Cyan
}

function Test-Case {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Body
    )
    # Libellé imprimé APRÈS l'exécution : ouvrir une ligne partielle avant
    # d'appeler le code testé produit du texte écrasé dès qu'une région de
    # progression se redessine dedans.
    try {
        $result = & $Body
        if ($result -is [string] -and $result -eq 'SKIP') {
            $script:TestStats.Skip++
            Write-Host ("  [{0,-56}] SKIP" -f $Name) -ForegroundColor Yellow
        }
        elseif ($result -eq $false) {
            $script:TestStats.Fail++
            $script:TestFailures += $Name
            Write-Host ("  [{0,-56}] FAIL" -f $Name) -ForegroundColor Red
        }
        else {
            $script:TestStats.Pass++
            Write-Host ("  [{0,-56}] OK" -f $Name) -ForegroundColor Green
        }
    }
    catch {
        $script:TestStats.Fail++
        $script:TestFailures += "$Name -> $($_.Exception.Message)"
        Write-Host ("  [{0,-56}] FAIL" -f $Name) -ForegroundColor Red
        Write-Host "    $($_.Exception.Message)" -ForegroundColor DarkRed
    }
}

#endregion


#region Setup
################################################################################

$repoRoot = Split-Path -Parent $PSScriptRoot
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "PS5-Core-Tests-$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

Write-Host ""
Write-Host "PS5-Core Test Suite" -ForegroundColor Magenta
Write-Host "  PowerShell     : $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"
Write-Host "  Language mode  : $($ExecutionContext.SessionState.LanguageMode)"
Write-Host "  Modules        : $repoRoot"
Write-Host "  Progress style : $ProgressStyle"
Write-Host "  Temp dir       : $tempDir"

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

$null = Initialize-EnhancedUI -ProgressStyle $ProgressStyle

#endregion


#region PS5-Core.Runtime tests
################################################################################

if (-not $OnlyUI) {
    Write-TestHeader "PS5-Core.Runtime - Assert-PowerShell5"

    Test-Case "no-op sous l'hote courant (5.1 est un plancher)" {
        try { Assert-PowerShell5; return $true } catch { return $false }
    }

    Test-Case "no-op avec un plancher volontairement bas" {
        try { Assert-PowerShell5 -MinimumVersion '3.0'; return $true } catch { return $false }
    }

    Test-Case "leve quand l'hote est sous le plancher demande" {
        try { Assert-PowerShell5 -MinimumVersion '99.0'; return $false }
        catch { return ($_.Exception.Message -match '99\.0') }
    }

    Test-Case "le garde passe aussi sous PowerShell 7 (plancher, pas plafond)" {
        # Le garde repond 'assez recent ?', jamais 'est-ce Windows PowerShell ?'.
        # Sous PS7 il doit donc passer : c'est la definition d'un plancher.
        try { Assert-PowerShell5; return $true } catch { return $false }
    }
}

#endregion


#region PS5-Core.Runtime logging tests
################################################################################

if (-not $OnlyUI) {
    Write-TestHeader "PS5-Core.Runtime - Logging"

    Test-Case "no log file before Initialize-Logging" {
        $p = Join-Path $tempDir 'never-created.log'
        Write-Log -Message 'ignored'
        return (-not (Test-Path $p)) -and ((Get-LogContext).Enabled -eq $false)
    }

    Test-Case "Initialize-Logging creates the file and Write-Log appends a line" {
        $p = Join-Path $tempDir 'basic.log'
        Initialize-Logging -Path $p
        Write-Log -Message 'hello world'
        if (-not (Test-Path $p)) { return $false }
        $line = @(Get-Content -Path $p | Where-Object { $_ -ne '' })[-1]
        return ($line -match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} \[INFO   \] hello world$')
    }

    Test-Case "Get-LogContext reports the active path and level" {
        $p = Join-Path $tempDir 'context.log'
        Initialize-Logging -Path $p -MinimumLevel Debug
        $ctx = Get-LogContext
        return ($ctx.Enabled -eq $true) -and ($ctx.MinimumLevel -eq 'Debug') -and ($ctx.Path -eq $p)
    }

    Test-Case "MinimumLevel filters out lower levels" {
        $p = Join-Path $tempDir 'filter.log'
        Initialize-Logging -Path $p -MinimumLevel Warning
        Write-Log -Message 'dropped' -Level Info
        Write-Log -Message 'kept' -Level Error
        $content = Get-Content -Path $p -Raw
        return ($content -notmatch 'dropped') -and ($content -match 'kept')
    }

    Test-Case "a write failure disables logging instead of throwing" {
        $sub = Join-Path $tempDir 'doomed'
        $p = Join-Path $sub 'ok-then-broken.log'
        Initialize-Logging -Path $p
        Write-Log -Message 'first'
        # Le repertoire parent disparait : l'ecriture suivante ne peut pas aboutir.
        Remove-Item -Path $sub -Recurse -Force
        try {
            Write-Log -Message 'boom' -WarningAction SilentlyContinue
        }
        catch { return $false }
        return ((Get-LogContext).Enabled -eq $false)
    }

    Test-Case "Initialize-Logging throws on an unusable path" {
        try {
            Initialize-Logging -Path 'Z:\no-such-volume\deep\x.log'
            return $false
        }
        catch { return $true }
    }

    Test-Case "PROBE: .UI can resolve Write-Log across the nested boundary" {
        $ui = (Get-Module PS5-Core).NestedModules | Where-Object Name -eq 'PS5-Core.UI'
        if (-not $ui) { return $false }
        $resolved = & $ui { Get-Command Write-Log -ErrorAction SilentlyContinue }
        return ($null -ne $resolved)
    }

    Test-Case "Write-StatusMessage feeds the log with its Type as level" {
        $p = Join-Path $tempDir 'tee.log'
        Initialize-Logging -Path $p
        Write-StatusMessage 'teed message' -Type Warning 6>$null
        $content = Get-Content -Path $p -Raw
        return ($content -match '\[WARNING\] teed message')
    }

    Test-Case "Write-Header feeds the log at Info level" {
        $p = Join-Path $tempDir 'tee-header.log'
        Initialize-Logging -Path $p
        Write-Header 'Section title' 6>$null
        $content = Get-Content -Path $p -Raw
        return ($content -match '\[INFO   \] Section title')
    }

    Test-Case "Write-ProgressBar does NOT feed the log" {
        $p = Join-Path $tempDir 'tee-progress.log'
        Initialize-Logging -Path $p
        Write-ProgressBar -Activity 'Work' -Current 1 -Total 2 6>$null
        Write-ProgressBar -Activity 'Work' -Current 2 -Total 2 -Completed 6>$null
        $content = Get-Content -Path $p -Raw
        return ($content -notmatch 'Work')
    }

    Test-Case "the tee stays silent once logging has disabled itself" {
        $sub = Join-Path $tempDir 'tee-doomed'
        $p = Join-Path $sub 'off.log'
        Initialize-Logging -Path $p
        Remove-Item -Path $sub -Recurse -Force
        try {
            Write-StatusMessage 'no crash' -Type Info -WarningAction SilentlyContinue 6>$null
            return ((Get-LogContext).Enabled -eq $false)
        }
        catch { return $false }
    }
}

#endregion


#region PS5-Core.UI tests
################################################################################

if (-not $OnlyRuntime) {
    Write-TestHeader "PS5-Core.UI - contrats"

    Test-Case "Get-UIContext expose la strategie active" {
        (Get-UIContext).ProgressStyle -eq $ProgressStyle
    }

    Test-Case "Get-UIContext signale l'initialisation" {
        (Get-UIContext).Initialized -eq $true
    }

    Test-Case "Initialize-EnhancedUI refuse une strategie inconnue" {
        try { Initialize-EnhancedUI -ProgressStyle 'Inexistante' | Out-Null; return $false }
        catch { return $true }
    }

    Test-Case "Initialize-EnhancedUI sans parametre ne re-resout pas" {
        $avant = (Get-UIContext).ProgressStyle
        $null = Initialize-EnhancedUI
        (Get-UIContext).ProgressStyle -eq $avant
    }

    Test-Case "Write-StatusMessage declare AllowNull ET AllowEmptyString" {
        # Contrat verifie par les metadonnees : sans les DEUX, passer `$null a un
        # parametre Mandatory ouvre une invite et fige le script.
        $attrs = (Get-Command Write-StatusMessage).Parameters['Message'].Attributes
        $hasNull = @($attrs | Where-Object { $_ -is [System.Management.Automation.AllowNullAttribute] }).Count -eq 1
        $hasEmpty = @($attrs | Where-Object { $_ -is [System.Management.Automation.AllowEmptyStringAttribute] }).Count -eq 1
        $hasNull -and $hasEmpty
    }

    Test-Case "Write-StatusMessage accepte `$null sans lever ni figer" {
        Write-StatusMessage $null -Type Info
        $true
    }

    Test-Case "les six types de message sont acceptes" {
        foreach ($t in 'Info', 'Success', 'Warning', 'Error', 'Skipped', 'Debug') {
            Write-StatusMessage "type $t" -Type $t
        }
        $true
    }

    Test-Case "aucune fonction publique n'expose de parametre de strategie" {
        # Le choix depend de l'environnement, pas du site d'appel : si un
        # parametre de strategie apparaissait ailleurs, ce principe serait rompu.
        $fautives = @()
        foreach ($n in 'Write-StatusMessage', 'Write-ProgressBar', 'Write-Header', 'Write-Summary', 'Read-Selection', 'Read-FolderSelection', 'Start-ProgressScope') {
            if ((Get-Command $n).Parameters.Keys -contains 'ProgressStyle') { $fautives += $n }
        }
        $fautives.Count -eq 0
    }

    Test-Case "Start-ProgressScope refuse l'imbrication" {
        try { Start-ProgressScope { Start-ProgressScope { } }; return $false }
        catch { return $true }
    }

    Test-Case "Start-ProgressScope remet l'etat a plat apres une exception" {
        try { Start-ProgressScope { throw 'boom' } } catch { }
        Start-ProgressScope { $true }
    }

    Test-Case "Start-ProgressScope ouvre un VRAI scope enfant" {
        # Parite de piege avec PS7-Core : une reaffectation est perdue, une
        # mutation d'objet est conservee. Un passe-plat sans scope ferait
        # 'marcher' ici du code qui casserait une fois porte sous PS7-Core.
        $compteur = 0
        $sac = @{ n = 0 }
        Start-ProgressScope { $compteur = 99; $sac['n'] = 42 } | Out-Null
        ($compteur -eq 0) -and ($sac['n'] -eq 42)
    }

    Test-Case "Write-ProgressBar tolere Total = 0" {
        Write-ProgressBar -Activity "Zero" -Current 0 -Total 0
        Write-ProgressBar -Activity "Zero" -Completed
        $true
    }

    Test-Case "Write-Header tolere un titre plus large que la console" {
        Write-Header ("T" * 400)
        $true
    }

    if ($ProgressStyle -eq 'Text') {
        Test-Case "Text : le nombre de lignes est borne par les paliers" {
            $lignes = @(& {
                    for ($i = 1; $i -le 200; $i++) { Write-ProgressBar -Activity 'Palier' -Current $i -Total 200 }
                    Write-ProgressBar -Activity 'Palier' -Completed
                } 6>&1)
            $paliers = @($lignes | Where-Object { "$_" -match 'Palier' })
            $paliers.Count -le 12 -and $paliers.Count -ge 2
        }

        Test-Case "Text : Completed laisse une trace dans le flux" {
            $lignes = @(& {
                    Write-ProgressBar -Activity 'Trace' -Current 1 -Total 10
                    Write-ProgressBar -Activity 'Trace' -Completed
                } 6>&1)
            @($lignes | Where-Object { "$_" -match 'termine' }).Count -eq 1
        }
    }
    else {
        Test-Case "Text : le nombre de lignes est borne par les paliers" { 'SKIP' }
        Test-Case "Text : Completed laisse une trace dans le flux" { 'SKIP' }
    }

    Write-TestHeader "PS5-Core.UI - Read-FolderSelection"

    $rfsRoot = Join-Path $tempDir 'rfs'
    New-Item -ItemType Directory -Path $rfsRoot -Force | Out-Null
    foreach ($n in 'kept-a', 'kept-b', 'excluded-a') {
        New-Item -ItemType Directory -Path (Join-Path $rfsRoot $n) -Force | Out-Null
    }
    New-Item -ItemType Directory -Path (Join-Path (Join-Path $rfsRoot 'kept-a') 'child') -Force | Out-Null

    Test-Case "non interactif retourne les sous-dossiers directs" {
        (@(Read-FolderSelection -Path $rfsRoot)).Count -eq 3
    }

    Test-Case "les sous-dossiers imbriques ne sont pas retournes" {
        $r = @(Read-FolderSelection -Path $rfsRoot)
        -not ($r -contains (Join-Path (Join-Path $rfsRoot 'kept-a') 'child'))
    }

    Test-Case "les noms exclus sont laisses de cote" {
        $r = @(Read-FolderSelection -Path $rfsRoot -ExcludeName 'excluded-a')
        ($r.Count -eq 2) -and -not ($r -contains (Join-Path $rfsRoot 'excluded-a'))
    }

    Test-Case "l'exclusion est insensible a la casse" {
        (@(Read-FolderSelection -Path $rfsRoot -ExcludeName 'EXCLUDED-A')).Count -eq 2
    }

    Test-Case "un chemin inexistant leve" {
        try { Read-FolderSelection -Path (Join-Path $tempDir 'nexiste-pas') | Out-Null; return $false }
        catch { return $true }
    }

    Test-Case "-Interactive avec entree redirigee conserve tout" {
        if (-not [Console]::IsInputRedirected) { return 'SKIP' }
        (@(Read-FolderSelection -Path $rfsRoot -ExcludeName 'excluded-a' -Interactive)).Count -eq 2
    }
}

#endregion


#region PS5-Core.Crypto tests
################################################################################

if (-not $OnlyRuntime -and -not $OnlyUI) {
    Write-TestHeader "PS5-Core.Crypto - hachage"

    # Vecteurs de reference publics : le hachage est un contrat exact, on compare
    # a des constantes connues plutot qu'a une seconde execution du meme code.
    $abcSha256 = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
    $abcMd5 = '900150983cd24fb0d6963f7d28e17f72'

    $cryptoDir = Join-Path $tempDir 'crypto'
    New-Item -ItemType Directory -Path $cryptoDir -Force | Out-Null

    $abcFile = Join-Path $cryptoDir 'abc.txt'
    [System.IO.File]::WriteAllBytes($abcFile, [System.Text.Encoding]::ASCII.GetBytes('abc'))

    # Nom canonique d'un doublon telecharge, et motif joker pour -Path : c'est le
    # cas qui distingue Test-Path -Path de -LiteralPath.
    $bracketFile = Join-Path $cryptoDir 'copie[1].txt'
    [System.IO.File]::WriteAllBytes($bracketFile, [System.Text.Encoding]::ASCII.GetBytes('abc'))

    Test-Case "Get-StringHash SHA256 correspond au vecteur de reference" {
        (Get-StringHash -String 'abc') -eq $abcSha256
    }

    Test-Case "Get-StringHash honore -Algorithm et -UpperCase" {
        ((Get-StringHash -String 'abc' -Algorithm MD5) -eq $abcMd5) -and
        ((Get-StringHash -String 'abc' -UpperCase) -eq $abcSha256.ToUpper())
    }

    Test-Case "Get-StringHash tient compte de l'encodage" {
        (Get-StringHash -String 'abc' -Encoding Unicode) -ne $abcSha256
    }

    Test-Case "Get-FileHashExtended correspond au vecteur de reference" {
        (Get-FileHashExtended -Path $abcFile) -eq $abcSha256
    }

    Test-Case "Get-FileHashExtended hache un nom contenant des crochets" {
        (Get-FileHashExtended -Path $bracketFile) -eq $abcSha256
    }

    Test-Case "Get-FileHashExtended signale un fichier absent" {
        $null -eq (Get-FileHashExtended -Path (Join-Path $cryptoDir 'absent.txt') -ErrorAction SilentlyContinue)
    }

    Test-Case "Get-FileHashExtended refuse un repertoire" {
        $null -eq (Get-FileHashExtended -Path $cryptoDir -ErrorAction SilentlyContinue)
    }

    Test-Case "Test-FileIntegrity accepte le hash attendu, quelle que soit la casse" {
        (Test-FileIntegrity -Path $abcFile -ExpectedHash $abcSha256) -and
        (Test-FileIntegrity -Path $abcFile -ExpectedHash $abcSha256.ToUpper())
    }

    Test-Case "Test-FileIntegrity refuse un hash different" {
        -not (Test-FileIntegrity -Path $abcFile -ExpectedHash ('0' * 64) -WarningAction SilentlyContinue)
    }

    Test-Case "Test-FileIntegrity compare avec l'algorithme demande" {
        Test-FileIntegrity -Path $abcFile -ExpectedHash $abcMd5 -Algorithm MD5
    }

    Test-Case "Test-FileIntegrity retourne faux sur un fichier absent" {
        -not (Test-FileIntegrity -Path (Join-Path $cryptoDir 'absent.txt') -ExpectedHash $abcSha256 -ErrorAction SilentlyContinue)
    }
}

#endregion


#region Final report
################################################################################

Write-Host ""
Write-Host ("=" * 72) -ForegroundColor Cyan
Write-Host "  Results ($ProgressStyle)" -ForegroundColor Cyan
Write-Host ("=" * 72) -ForegroundColor Cyan
Write-Host ("  PASS : {0}" -f $script:TestStats.Pass) -ForegroundColor Green
Write-Host ("  FAIL : {0}" -f $script:TestStats.Fail) -ForegroundColor Red
Write-Host ("  SKIP : {0}" -f $script:TestStats.Skip) -ForegroundColor Yellow

if ($script:TestFailures.Count -gt 0) {
    Write-Host ""
    Write-Host "  Failures:" -ForegroundColor Red
    foreach ($f in $script:TestFailures) {
        Write-Host "    - $f" -ForegroundColor Red
    }
}

try { Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue } catch { }

Write-Host ""
exit ([int]($script:TestStats.Fail -gt 0))

#endregion
