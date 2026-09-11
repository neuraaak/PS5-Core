<#
.SYNOPSIS
    Scénarios partagés par Show-UiProgress.Bar.ps1 et Show-UiProgress.Text.ps1.

.DESCRIPTION
    Un seul fichier de scénarios, deux lanceurs minces. Deux scripts autonomes
    auraient dérivé l'un de l'autre, or c'est justement un outil censé COMPARER
    les deux stratégies : s'ils ne mesurent pas exactement la même chose, la
    comparaison ne vaut rien.

    Deux volets :

      Robustesse  assertions exécutables sans terminal (-SkipVisual). Elles
                  vérifient que rien ne lève et que les contrats tiennent.
      Rendu       sortie à inspecter À L'ŒIL (-OnlyVisual). Aucune assertion :
                  c'est l'humain qui tranche, parce que la question posée est
                  « est-ce que ça s'affiche proprement », et qu'aucune
                  assertion ne sait répondre à ça.

    Le volet Rendu n'a de sens que dans un VRAI terminal. En sortie redirigée,
    Write-Progress ne dessine rien du tout : le volet Bar y serait vide et la
    comparaison serait truquée en faveur de Text.
#>

#Requires -Version 5.1

$script:CheckStats = @{ Pass = 0; Fail = 0 }
$script:CheckFailures = @()

function Assert-Check {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Body
    )

    # Le libellé est imprimé APRÈS l'exécution, en une ligne complète. Ouvrir
    # une ligne partielle avant d'appeler le code testé produit du texte écrasé
    # dès qu'une région de progression se redessine dedans — piège payé une
    # fois dans PS7-Core, pas deux.
    $ok = $false
    $err = $null
    try { $ok = (& $Body) -ne $false }
    catch { $ok = $false; $err = $_.Exception.Message }

    if ($ok) {
        $script:CheckStats.Pass++
        Write-Host ("  [{0,-58}] OK" -f $Name) -ForegroundColor Green
    }
    else {
        $script:CheckStats.Fail++
        $script:CheckFailures += $(if ($err) { "$Name -> $err" } else { $Name })
        Write-Host ("  [{0,-58}] FAIL" -f $Name) -ForegroundColor Red
        if ($err) { Write-Host "    $err" -ForegroundColor DarkRed }
    }
}

function Write-ScenarioTitle {
    param([string]$Text, [string]$Watch)

    Write-Host ""
    Write-Host ("=" * 78) -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    if ($Watch) { Write-Host "  A REGARDER : $Watch" -ForegroundColor DarkCyan }
    Write-Host ("=" * 78) -ForegroundColor Cyan
}


function Invoke-UiProgressChecks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Bar', 'Text')]
        [string]$ProgressStyle,

        [switch]$SkipVisual,
        [switch]$OnlyVisual,
        [switch]$Thorough
    )

    $null = Initialize-EnhancedUI -ProgressStyle $ProgressStyle

    # Les helpers internes (Get-ClampedPercentPS5...) ne sont pas exportes. Pour
    # les atteindre il faut la portee du sous-module — et apres l'import du
    # meta-module, PS5-Core.UI n'est PAS un module de premier niveau :
    # Get-Module PS5-Core.UI retourne $null. On passe par NestedModules.
    $uiModule = @((Get-Module PS5-Core).NestedModules | Where-Object { $_.Name -eq 'PS5-Core.UI' })[0]
    if (-not $uiModule) { $uiModule = Get-Module PS5-Core.UI }

    Write-Host ""
    Write-Host "Strategie : $ProgressStyle" -ForegroundColor Magenta
    Write-Host "Hote      : $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"
    Write-Host "Sortie redirigee : $([Console]::IsOutputRedirected)   Entree redirigee : $([Console]::IsInputRedirected)"

    # Cadence : sans pause, tout défile trop vite pour qu'un œil humain juge
    # quoi que ce soit. 15 ms est assez lent pour voir, assez rapide pour que
    # la passe complète tienne en une poignée de secondes.
    $tick = 15

    #region Robustesse
    if (-not $OnlyVisual) {
        Write-Host ""
        Write-Host ("-" * 78) -ForegroundColor DarkGray
        Write-Host "  Robustesse" -ForegroundColor White
        Write-Host ("-" * 78) -ForegroundColor DarkGray

        Assert-Check "Get-UIContext expose la strategie reellement active" {
            (Get-UIContext).ProgressStyle -eq $ProgressStyle
        }

        Assert-Check "Total = 0 ne leve pas et ne divise pas par zero" {
            Write-ProgressBar -Activity "Zero" -Current 0 -Total 0
            Write-ProgressBar -Activity "Zero" -Completed
            $true
        }

        Assert-Check "acces a la portee du sous-module imbrique" {
            $null -ne $uiModule
        }

        Assert-Check "Current negatif est borne a 0" {
            (& $uiModule { param($c, $t) Get-ClampedPercentPS5 -Current $c -Total $t } -50 100) -eq 0
        }

        Assert-Check "Current au-dela de Total est borne a 100" {
            (& $uiModule { param($c, $t) Get-ClampedPercentPS5 -Current $c -Total $t } 500 100) -eq 100
        }

        Assert-Check "Total = 0 donne 0 pour cent, sans division par zero" {
            (& $uiModule { param($c, $t) Get-ClampedPercentPS5 -Current $c -Total $t } 5 0) -eq 0
        }

        Assert-Check "Completed sans progression prealable ne leve pas" {
            Write-ProgressBar -Activity "Jamais commencee" -Completed
            $true
        }

        Assert-Check "Activity vide est refusee par la liaison de parametre" {
            # $null / '' passes EXPLICITEMENT : omettre un parametre obligatoire
            # ouvrirait une invite interactive en terminal reel et figerait la
            # suite. On verifie le refus, on ne le provoque pas par omission.
            try { Write-ProgressBar -Activity '' -Current 1 -Total 2; return $false }
            catch { return $true }
        }

        Assert-Check "Write-StatusMessage accepte `$null sans figer" {
            Write-StatusMessage $null -Type Info
            $true
        }

        Assert-Check "Write-StatusMessage accepte une chaine vide" {
            Write-StatusMessage '' -Type Info
            $true
        }

        Assert-Check "les six types de message sont acceptes" {
            foreach ($t in 'Info', 'Success', 'Warning', 'Error', 'Skipped', 'Debug') {
                Write-StatusMessage "type $t" -Type $t
            }
            $true
        }

        Assert-Check "un type inconnu est refuse par le ValidateSet" {
            try { Write-StatusMessage 'x' -Type 'Inexistant'; return $false }
            catch { return $true }
        }

        Assert-Check "le balisage facon Spectre sort en litteral, sans etre interprete" {
            # PS5-Core n'a pas de moteur de markup : '[red]x[/]' doit s'imprimer
            # tel quel. Si un jour on en ajoutait un, ce test le signalerait.
            Write-StatusMessage '[red]texte litteral[/] et [[double]]' -Type Info
            $true
        }

        Assert-Check "un titre plus large que la console ne leve pas" {
            Write-Header ("T" * 400)
            $true
        }

        Assert-Check "Write-Header accepte une couleur invalide et retombe sur Cyan" {
            Write-Header "Couleur invalide" -Color 'CouleurQuiNexistePas'
            $true
        }

        Assert-Check "Read-Selection avec une collection vide retourne vide" {
            (@(Read-Selection -Items @() -Message 'vide')).Count -eq 0
        }

        Assert-Check "Read-Selection avec entree redirigee conserve tout" {
            # Ne vaut QUE si l'entree est reellement redirigee : sinon la
            # fonction pose une vraie question a l'utilisateur, qu'aucune
            # assertion ne peut piloter.
            if (-not [Console]::IsInputRedirected) {
                Write-Host "    (ignore : entree non redirigee)" -ForegroundColor DarkGray
                return $true
            }
            (@(Read-Selection -Items @('a', 'b', 'c') -Message 'garder')).Count -eq 3
        }

        Assert-Check "Start-ProgressScope refuse l'imbrication" {
            try { Start-ProgressScope { Start-ProgressScope { } }; return $false }
            catch { return $true }
        }

        Assert-Check "Start-ProgressScope remet l'etat a plat apres une exception" {
            try { Start-ProgressScope { throw 'boom' } } catch { }
            # Si la sentinelle etait restee levee, ce second scope leverait.
            Start-ProgressScope { $true }
        }

        Assert-Check "Start-ProgressScope propage la sortie du scriptblock" {
            (Start-ProgressScope { 'valeur' }) -eq 'valeur'
        }

        Assert-Check "Start-ProgressScope refuse un scriptblock `$null" {
            try { Start-ProgressScope -ScriptBlock $null; return $false }
            catch { return $true }
        }

        # --- Start-Spinner : contrat et parite avec PS7-Core ---------------

        Assert-Check "Start-Spinner propage la sortie du scriptblock" {
            (Start-Spinner -Message 'travail' -ScriptBlock { 'valeur-de-retour' }) -eq 'valeur-de-retour'
        }

        Assert-Check "Start-Spinner refuse l imbrication" {
            try { Start-Spinner -Message 'a' -ScriptBlock { Start-Spinner -Message 'b' -ScriptBlock { } }; return $false }
            catch { return $true }
        }

        Assert-Check "Start-Spinner et Start-ProgressScope se refusent mutuellement" {
            # Les deux sens sont refuses explicitement, comme dans PS7-Core ou la
            # contrainte vient de Spectre : la surface publique des deux
            # bibliotheques doit rester la meme.
            $unSens = $false
            $autreSens = $false
            try { Start-ProgressScope { Start-Spinner -Message 'x' -ScriptBlock { } } } catch { $unSens = $true }
            try { Start-Spinner -Message 'x' -ScriptBlock { Start-ProgressScope { } } } catch { $autreSens = $true }
            $unSens -and $autreSens
        }

        Assert-Check "Start-Spinner remet l etat a plat apres une exception" {
            try { Start-Spinner -Message 'travail' -ScriptBlock { throw 'boum' } } catch { }
            # Un second appel doit reussir : sinon le sentinelle est reste arme.
            Start-Spinner -Message 'travail' -ScriptBlock { } | Out-Null
            return $true
        }

        Assert-Check "Start-Spinner refuse un scriptblock `$null" {
            try { Start-Spinner -Message 'travail' -ScriptBlock $null; return $false }
            catch { return $true }
        }

        # --- Invites : contrat non interactif -----------------------------

        Assert-Check "Read-Confirmation avec entree redirigee rend le defaut" {
            # Valide uniquement quand stdin EST redirige : sinon la fonction
            # affiche une vraie invite et attend une saisie, ce qu une assertion
            # ne peut ni piloter ni interpreter.
            if (-not [Console]::IsInputRedirected) { return "SKIP" }
            ((Read-Confirmation -Message 'continuer ?') -eq $false) -and
            ((Read-Confirmation -Message 'continuer ?' -DefaultValue $true) -eq $true)
        }

        Assert-Check "Read-TextInput avec entree redirigee rend -Default" {
            if (-not [Console]::IsInputRedirected) { return "SKIP" }
            (Read-TextInput -Message 'nom ?' -Default 'repli') -eq 'repli'
        }

        Assert-Check "Read-TextInput redirige sans -Default leve" {
            if (-not [Console]::IsInputRedirected) { return "SKIP" }
            try { Read-TextInput -Message 'nom ?' | Out-Null; return $false }
            catch { return $true }
        }

        Assert-Check "le piege de portee enfant se comporte comme dans PS7-Core" {
            # Reaffectation : perdue a la sortie. Mutation d'objet : conservee.
            # C'est la parite qui compte, pas le comportement en soi.
            # La valeur vue DANS le scope est rangee dans le sac, qui survit :
            # sans cette relecture, le cas passerait aussi si l'affectation
            # n'avait aucun effet, et ne prouverait pas que c'est la SORTIE qui
            # la perd.
            $compteur = 0
            $sac = @{ n = 0 }
            Start-ProgressScope {
                $compteur = 99
                $sac['vu'] = $compteur
                $sac['n'] = 42
            } | Out-Null
            ($compteur -eq 0) -and ($sac['vu'] -eq 99) -and ($sac['n'] -eq 42)
        }

        if ($ProgressStyle -eq 'Text') {
            Assert-Check "Text : une seule ligne par palier de 10 pour cent" {
                # Mesure par la SORTIE, pas en fouillant l'etat interne : depuis
                # PS 5.0, Write-Host passe par le flux d'information, donc 6>&1
                # le capture. Sans le garde-fou, 200 appels donneraient 200
                # lignes et la progression noierait la sortie utile.
                $lignes = @(& {
                        for ($i = 1; $i -le 200; $i++) {
                            Write-ProgressBar -Activity 'Palier' -Current $i -Total 200
                        }
                        Write-ProgressBar -Activity 'Palier' -Completed
                    } 6>&1)

                $paliers = @($lignes | Where-Object { "$_" -match 'Palier' })
                Write-Host "    ($($paliers.Count) ligne(s) pour 200 appels)" -ForegroundColor DarkGray
                $paliers.Count -le 12 -and $paliers.Count -ge 2
            }
        }
        else {
            Write-Host "  [Text : une seule ligne par palier de 10 pour cent    ] SKIP" -ForegroundColor Yellow
        }

        Write-Host ""
        Write-Host ("  Robustesse : PASS {0}  FAIL {1}" -f $script:CheckStats.Pass, $script:CheckStats.Fail) -ForegroundColor $(if ($script:CheckStats.Fail -gt 0) { 'Red' } else { 'Green' })
        if ($script:CheckFailures.Count -gt 0) {
            foreach ($f in $script:CheckFailures) { Write-Host "    - $f" -ForegroundColor Red }
        }
    }
    #endregion

    #region Rendu
    if (-not $SkipVisual) {

        if ([Console]::IsOutputRedirected) {
            Write-Host ""
            Write-Host "AVERTISSEMENT : sortie redirigee. Write-Progress ne dessine RIEN dans ce mode," -ForegroundColor Yellow
            Write-Host "la comparaison serait faussee en faveur de Text. Relancez dans un vrai terminal." -ForegroundColor Yellow
        }

        Write-ScenarioTitle "1. Les six types de message" "les prefixes et les couleurs, rien d'autre"
        foreach ($t in 'Info', 'Success', 'Warning', 'Error', 'Skipped', 'Debug') {
            Write-StatusMessage "Message de type $t" -Type $t
        }

        Write-ScenarioTitle "2. Progression seule" "l'avancee, et ce qu'il RESTE une fois termine"
        Start-ProgressScope {
            for ($i = 1; $i -le 120; $i++) {
                Write-ProgressBar -Activity "Analyse" -Current $i -Total 120 -Status "element $i"
                Start-Sleep -Milliseconds $tick
            }
            Write-ProgressBar -Activity "Analyse" -Completed
        }
        Write-Host "<- au-dessus de cette ligne : reste-t-il une trace de la progression ?" -ForegroundColor DarkCyan

        Write-ScenarioTitle "3. Progression + messages entrelaces" "LE cas critique : lignes ecrasees, ordre melange, decalages"
        Start-ProgressScope {
            for ($i = 1; $i -le 120; $i++) {
                Write-ProgressBar -Activity "Traitement" -Current $i -Total 120
                if ($i % 12 -eq 0) {
                    Write-StatusMessage "element $i traite" -Type Success
                }
                Start-Sleep -Milliseconds $tick
            }
            Write-ProgressBar -Activity "Traitement" -Completed
        }

        Write-ScenarioTitle "4. Deux activites simultanees" "les deux avancent-elles lisiblement, ou se marchent-elles dessus ?"
        Start-ProgressScope {
            for ($i = 1; $i -le 100; $i++) {
                Write-ProgressBar -Activity "Lecture" -Current $i -Total 100 -Id 1
                Write-ProgressBar -Activity "Ecriture" -Current (101 - $i) -Total 100 -Id 2
                Start-Sleep -Milliseconds $tick
            }
            Write-ProgressBar -Activity "Lecture" -Id 1 -Completed
            Write-ProgressBar -Activity "Ecriture" -Id 2 -Completed
        }

        Write-ScenarioTitle "5. Ligne partielle + progression" "motif CONNU comme destructeur dans PS7-Core"
        Write-Host "  Verification en cours : " -NoNewline
        Start-ProgressScope {
            for ($i = 1; $i -le 60; $i++) {
                Write-ProgressBar -Activity "Verification" -Current $i -Total 60
                Start-Sleep -Milliseconds $tick
            }
            Write-ProgressBar -Activity "Verification" -Completed
        }
        Write-Host "termine."
        Write-Host "<- la ligne ci-dessus est-elle intacte, ou coupee/ecrasee ?" -ForegroundColor DarkCyan

        if ($Thorough) {
            Write-ScenarioTitle "6. Charge d'impression (-Thorough)" "un message PAR item : la progression tient-elle ?"
            Start-ProgressScope {
                for ($i = 1; $i -le 400; $i++) {
                    Write-ProgressBar -Activity "Charge" -Current $i -Total 400
                    Write-StatusMessage "ligne $i" -Type Debug
                }
                Write-ProgressBar -Activity "Charge" -Completed
            }
        }
        else {
            Write-Host ""
            Write-Host "  (scenario 6, charge d'impression : ajouter -Thorough)" -ForegroundColor DarkGray
        }

        Write-Host ""
        Write-Host ("=" * 78) -ForegroundColor Magenta
        Write-Host "  Strategie testee : $ProgressStyle" -ForegroundColor Magenta
        Write-Host "  Remontez la sortie : la trace de progression est-elle encore la ?" -ForegroundColor Magenta
        Write-Host ("=" * 78) -ForegroundColor Magenta
    }
    #endregion

    return $script:CheckStats.Fail
}
