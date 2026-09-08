<#
    Stratégie de progression « Bar » — Write-Progress, vue classique 5.1.

    C'est le portage direct du backend natif de PS7-Core, et c'est précisément
    là qu'il ne se transporte PAS tel quel. PS7-Core s'appuie sur la vue
    'Minimal' de Write-Progress, introduite avec $PSStyle en PowerShell 7.2 et
    devenue le défaut : une ligne discrète en bas de région, validée en terminal
    réel sous forte charge d'impression.

    $PSStyle n'existe pas avant 7.2 — vérifié : absent en 5.1.26100. Windows
    PowerShell n'a donc que la vue CLASSIQUE, le bandeau pleine largeur ancré
    en haut de la console. Les PARAMÈTRES de Write-Progress sont identiques
    (Id, ParentId, SecondsRemaining...), si bien que ce code s'exécute sans la
    moindre erreur en 5.1 : ce qui diffère est le rendu, pas le contrat d'appel.
    Un test qui se contente de vérifier l'absence d'exception ne verra rien.

    Ce bandeau a été SOUPÇONNÉ de produire des décalages avec les Write-Host
    entrelacés. Le soupçon a été testé et ÉCARTÉ : vérifié le 2026-09-08 en
    terminal réel (Windows Terminal, 5.1.26100), progression avec messages
    entrelacés, ligne partielle suivie d'une progression, puis 400 items avec un
    message par item — aucune ligne perdue, aucun texte écrasé, aucun résidu de
    bandeau après complétion.

    C'est pourquoi Bar est le défaut d'Auto en console : par mesure, pas par
    absence d'alternative. Ne pas ré-instruire ce procès sans élément nouveau.
    Non couvert : le conhost hérité, où le rendu peut différer.
#>

function Write-ProgressBarAsBar {
    param(
        [string]$Activity,
        [int]$Current,
        [int]$Total,
        [string]$Status,
        [int]$Id,
        [int]$ParentId,
        [switch]$Completed
    )

    if ($Completed) {
        # Write-Progress EFFACE sa région : après un -Completed il ne reste
        # aucune trace dans la sortie relue après coup. C'est une différence
        # observable avec la stratégie Text, qui laisse sa dernière ligne.
        Write-Progress -Activity $Activity -Id $Id -Completed
        return
    }

    $percent = Get-ClampedPercentPS5 -Current $Current -Total $Total

    $progressParams = @{
        Activity        = $Activity
        Status          = if ($Status) { $Status } else { "$Current of $Total" }
        PercentComplete = $percent
        Id              = $Id
    }

    if ($ParentId -ge 0) {
        $progressParams['ParentId'] = $ParentId
    }

    Write-Progress @progressParams
}
