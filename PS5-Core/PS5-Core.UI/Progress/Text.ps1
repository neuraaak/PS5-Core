<#
    Stratégie de progression « Text » — aucune région de console, uniquement des
    lignes de statut périodiques dans le flux texte.

    Écrit au départ pour supprimer une classe de bug : les décalages d'affichage
    viennent de la coexistence d'une RÉGION redessinée avec un flux de texte qui
    avance, et pas de région signifie rien à corrompre.

    Cette justification-là est TOMBÉE : le test visuel du 2026-09-08 n'a pas
    reproduit de corruption avec Bar, même sous charge d'impression. Bar est
    donc le défaut en console (voir Bar.ps1).

    Ce qui justifie de garder Text, et ce n'est pas rien :
      - il laisse une TRACE dans la sortie relue après coup, là où
        Write-Progress efface sa région et ne laisse rien ;
      - son rendu est identique en console, en fichier et en tâche planifiée,
        alors que Write-Progress ne dessine rien du tout quand la sortie est
        redirigée. C'est ce qui en fait le choix d'Auto dans ce cas.

    Ce qu'on perd : l'animation, et le pourcentage continu.

    L'API publique ne change pas d'un iota : Write-ProgressBar s'appelle
    exactement pareil dans les deux stratégies, seul le rendu diffère.
#>

# Une ligne toutes les 10 % : assez pour voir que ça avance, assez rare pour ne
# pas noyer les messages de statut que le script écrit entre deux.
$script:ProgressTextStepPercent = 10

function Write-ProgressBarAsText {
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
        # La ligne finale reste dans le flux : c'est la trace que la vue
        # classique de Write-Progress ne laisse pas.
        if ($script:ProgressTextState.ContainsKey($Activity)) {
            $script:ProgressTextState.Remove($Activity)
            Write-Host "  $Activity : 100% - termine" -ForegroundColor DarkGray
        }
        return
    }

    $percent = Get-ClampedPercentPS5 -Current $Current -Total $Total

    # Un palier franchi = une ligne. Sans ce garde-fou, une boucle de 5000
    # items ecrirait 5000 lignes et la progression noierait la sortie utile.
    $bucket = [int]($percent / $script:ProgressTextStepPercent)

    if (-not $script:ProgressTextState.ContainsKey($Activity)) {
        $script:ProgressTextState[$Activity] = -1
    }

    if ($bucket -le $script:ProgressTextState[$Activity]) {
        return
    }

    $script:ProgressTextState[$Activity] = $bucket

    $detail = if ($Status) { $Status } else { "$Current of $Total" }
    Write-Host ("  {0} : {1,3}% - {2}" -f $Activity, $percent, $detail) -ForegroundColor DarkGray
}
