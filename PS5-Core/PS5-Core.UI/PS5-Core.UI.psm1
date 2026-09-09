<#
.SYNOPSIS
    Console UI module for Windows PowerShell 5.1.

.DESCRIPTION
    Sortie console sans aucune dépendance externe, avec deux stratégies de
    progression interchangeables :

      Bar   Write-Progress, vue classique 5.1 (bandeau en haut de console).
      Text  lignes de statut périodiques dans le flux, aucune région redessinée.

    Ce que PS5-Core NE porte PAS de PS7-Core, et pourquoi :

      - le backend Spectre. PwshSpectreConsole est PS7-only, il n'a pas
        d'équivalent 5.1. Il n'y a donc rien à choisir de ce côté.
      - la vue 'Minimal' de Write-Progress. Elle arrive avec $PSStyle en
        PowerShell 7.2 et c'est elle que le backend natif de PS7-Core suppose.
        $PSStyle n'existe pas en 5.1 : seule la vue classique est disponible.

    C'est ce second point qui justifie l'existence des deux stratégies. L'axe de
    variation de PS7-Core était le backend, parce que deux moteurs de rendu
    complets s'y opposaient. Ici messages, en-tête et sélection sont identiques
    d'une stratégie à l'autre : le seul point de variation est la progression,
    et l'axe le dit.

    Les PRINCIPES de PS7-Core sont conservés tels quels :
      - la stratégie est résolue UNE FOIS par Initialize-EnhancedUI, jamais par
        appel : le choix dépend de l'environnement, pas du site d'appel ;
      - aucune fonction publique n'expose de paramètre de stratégie, et le code
        appelant est identique dans les deux modes ;
      - les deux implémentations sont dot-sourcées TOUJOURS, ce qui permet de
        forcer l'une ou l'autre depuis n'importe quel poste et rend les deux
        testables sans machine dédiée ;
      - 'Auto' annonce sa bascule par une ligne, une seule fois : jamais de
        dégradation silencieuse.

.NOTES
    Author:  Neuraaak
    License: MIT
#>

#region Module Variables

# UI context: which progress strategy is active, and whether we are initialized.
$script:UIContext = @{
    ProgressStyle = 'None'
    Initialized   = $false
}

# Activity name -> dernier palier de 10 % déjà imprimé, pour la stratégie Text.
$script:ProgressTextState = @{}

# Sentinelle d'imbrication. Aucune des deux stratégies n'ouvre de région live,
# donc rien d'autre ne permet de détecter une imbrication.
$script:InProgressScope = $false

# L'avis de bascule d'Auto est émis une fois par session, pas par appel.
$script:AutoNoticeShown = $false

# Résolution du logger de PS5-Core.Runtime, faite UNE SEULE FOIS. L'appel
# traverse la frontière de sous-module imbriqué : c'est un chemin que le projet
# n'empruntait pas avant le logging, et une sonde de test le couvre.
# Le drapeau séparé évite de re-sonder à chaque appel quand la fonction est
# absente (import direct de PS5-Core.UI, hors du méta-module).
$script:LogWriterProbed = $false
$script:LogWriter = $null

# Correspondance Type d'affichage -> niveau de log. Success et Skipped sont de
# l'information : ils ne méritent pas un niveau à eux.
$script:LogLevelForType = @{
    Info    = 'Info'
    Success = 'Info'
    Skipped = 'Info'
    Debug   = 'Debug'
    Warning = 'Warning'
    Error   = 'Error'
}

function Write-TeeLog {
    param(
        [AllowNull()][AllowEmptyString()][string]$Message,
        [string]$Level = 'Info'
    )

    if (-not $script:LogWriterProbed) {
        $script:LogWriter = Get-Command Write-Log -ErrorAction SilentlyContinue
        $script:LogWriterProbed = $true
    }
    if ($null -eq $script:LogWriter) { return }

    # Write-Log ne lève jamais, mais l'affichage passe avant la trace : si cette
    # garantie changeait un jour, le tee ne doit toujours rien casser.
    try { & $script:LogWriter -Message $Message -Level $Level } catch { }
}

#endregion


#region Strategy Loading

. (Join-Path $PSScriptRoot 'Private\Console.ps1')
. (Join-Path $PSScriptRoot 'Progress\Bar.ps1')
. (Join-Path $PSScriptRoot 'Progress\Text.ps1')

#endregion


#region Public Functions

<#
.SYNOPSIS
    Initializes the UI system and resolves the progress strategy.

.DESCRIPTION
    'Auto' choisit Text quand la sortie est redirigée — il n'y a alors aucune
    région de console où dessiner un bandeau, et Write-Progress ne rendrait
    rien du tout — et Bar sinon. La bascule est annoncée une fois.

    'Bar' et 'Text' forcent la stratégie, y compris là où Auto aurait choisi
    l'autre. C'est ainsi que les deux sont comparées côte à côte sur un même
    poste, ce qui est le seul moyen de trancher la question du rendu.

    Contrairement à PS7-Core, cette fonction ne touche NI à l'encodage de
    sortie NI au mode VT100 de la console. Le VT100 n'y servait qu'aux invites
    Spectre, absentes ici ; et forcer [Console]::OutputEncoding sur un hôte 5.1
    a des effets de bord sur tout ce qui écrit ensuite. On observe l'encodage
    (voir Get-RuleCharPS5), on ne le modifie pas.

.PARAMETER ProgressStyle
    Auto (défaut), Bar, ou Text. Passer ce paramètre re-résout la stratégie même
    si l'UI est déjà initialisée.

.EXAMPLE
    Initialize-EnhancedUI

.EXAMPLE
    Initialize-EnhancedUI -ProgressStyle Text
    Force les lignes de statut, y compris dans un vrai terminal.

.OUTPUTS
    Hashtable containing UI context information.
#>
function Initialize-EnhancedUI {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateSet('Auto', 'Bar', 'Text')]
        [string]$ProgressStyle = 'Auto'
    )

    $styleRequested = $PSBoundParameters.ContainsKey('ProgressStyle')

    if ($script:UIContext.Initialized -and -not $styleRequested) {
        Write-Verbose "UI already initialized (progress style: $($script:UIContext.ProgressStyle))."
        return $script:UIContext
    }

    switch ($ProgressStyle) {
        'Bar' {
            $script:UIContext.ProgressStyle = 'Bar'
        }
        'Text' {
            $script:UIContext.ProgressStyle = 'Text'
        }
        default {
            $redirected = $false
            try { $redirected = [Console]::IsOutputRedirected }
            catch { Write-Verbose "Cannot determine output redirection: $_" }

            if ($redirected) {
                $script:UIContext.ProgressStyle = 'Text'

                # Never degrade silently: say it once, then stay quiet.
                if (-not $script:AutoNoticeShown) {
                    $script:AutoNoticeShown = $true
                    Write-Host "Output is redirected - using textual progress lines." -ForegroundColor DarkGray
                }
            }
            else {
                $script:UIContext.ProgressStyle = 'Bar'
            }
        }
    }

    $script:UIContext.Initialized = $true

    Write-Verbose "UI initialized: progressStyle=$($script:UIContext.ProgressStyle)"

    return $script:UIContext
}


<#
.SYNOPSIS
    Returns the current UI context (progress strategy, initialization state).

.DESCRIPTION
    The only supported way to read the UI context. The module state lives in
    $script:UIContext and is NOT exported: Export-ModuleMember -Variable does
    not cross the nested-module boundary, so when PS5-Core.UI is loaded as a
    nested module of PS5-Core the variable would never reach the caller.

.EXAMPLE
    if ((Get-UIContext).ProgressStyle -eq 'Text') { ... }

.OUTPUTS
    Hashtable. Keys: ProgressStyle, Initialized.
#>
function Get-UIContext {
    [CmdletBinding()]
    param ()

    return $script:UIContext
}


<#
.SYNOPSIS
    Runs a scriptblock inside a progress scope.

.DESCRIPTION
    Aucune des deux stratégies n'ouvre de région live : il n'y a rien à monter
    ni à démonter, et Write-ProgressBar fonctionne aussi bien hors de tout
    scope. La fonction est néanmoins conservée, et reste un VRAI scope invoqué
    via '&', pour deux raisons.

    D'abord la parité d'API : un script écrit pour PS7-Core s'exécute ici sans
    modification. Ensuite, et surtout, la parité de PIÈGE — le piège de portée
    enfant ci-dessous se comporte à l'identique dans les deux bibliothèques. Un
    passe-plat qui n'ouvrirait pas de scope ferait « marcher » du code qui
    casserait une fois porté sous PS7-Core, ce qui est bien pire qu'un scope
    inutile.

    Ne supporte pas l'imbrication, dans aucune des deux stratégies.

    IMPORTANT (scope enfant) : le scriptblock s'exécute dans un scope enfant.
    Toute variable réaffectée dedans (=, +=, ++) crée une copie locale perdue à
    la sortie. Muter un membre d'objet ($table[$k] = $v, $liste.Add(...))
    fonctionne. Pour accumuler, utiliser
    [System.Collections.Generic.List[object]] et .Add() plutôt que += sur un tableau.

.PARAMETER ScriptBlock
    The work to run. Reçoit un argument positionnel, toujours $null : il
    n'existe pas de contexte de progression en 5.1. Le paramètre existe pour que
    la signature reste celle de PS7-Core.

.EXAMPLE
    Start-ProgressScope -ScriptBlock {
        for ($i = 1; $i -le $total; $i++) {
            Write-ProgressBar -Activity "Scanning" -Current $i -Total $total
        }
        Write-ProgressBar -Activity "Scanning" -Completed
    }
#>
function Start-ProgressScope {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock
    )

    if (-not $script:UIContext.Initialized) {
        $null = Initialize-EnhancedUI
    }

    if ($script:InProgressScope) {
        throw "Start-ProgressScope does not support nesting."
    }

    $script:InProgressScope = $true
    try {
        return & $ScriptBlock $null
    }
    finally {
        $script:InProgressScope = $false
        $script:ProgressTextState = @{}
    }
}


<#
.SYNOPSIS
    Writes colored status messages.

.PARAMETER Message
    The message to display.

.PARAMETER Type
    Info, Success, Warning, Error, Skipped or Debug.

.EXAMPLE
    Write-StatusMessage "Operation completed" -Type Success
#>
function Write-StatusMessage {
    [CmdletBinding()]
    param (
        # AllowNull + AllowEmptyString : sans eux, passer $null à un paramètre
        # Mandatory ne lève PAS, PowerShell ouvre une invite interactive et le
        # script se fige indéfiniment. Pour une fonction d'affichage, un blocage
        # est le pire résultat possible : on accepte, et on imprime une ligne
        # vide. Piège hérité de PS7-Core, payé une fois, pas deux.
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Skipped', 'Debug')]
        [string]$Type = 'Info'
    )

    if (-not $script:UIContext.Initialized) {
        $null = Initialize-EnhancedUI
    }

    Write-TeeLog -Message $Message -Level $script:LogLevelForType[$Type]

    Write-StatusMessagePS5 -Message $Message -Type $Type
}


<#
.SYNOPSIS
    Displays a progress indicator for operations.

.DESCRIPTION
    Route vers la stratégie résolue à l'initialisation. L'appel est identique
    dans les deux cas ; seul le rendu diffère.

.PARAMETER Activity
    The activity description.

.PARAMETER Current
    The current item number being processed.

.PARAMETER Total
    The total number of items to process.

.PARAMETER Status
    Additional status information to display.

.PARAMETER Id
    Progress bar ID for nested bars. Stratégie Bar uniquement : la stratégie
    Text n'a pas de région, donc rien à imbriquer.

.PARAMETER ParentId
    Parent progress bar ID. Stratégie Bar uniquement.

.PARAMETER Completed
    Marque l'activité terminée. En Bar la région est effacée ; en Text une
    dernière ligne est écrite et reste dans le flux.

.EXAMPLE
    Write-ProgressBar -Activity "Processing files" -Current 50 -Total 100
#>
function Write-ProgressBar {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Activity,

        [Parameter(Mandatory = $false)]
        [int]$Current = 0,

        [Parameter(Mandatory = $false)]
        [int]$Total = 100,

        [Parameter(Mandatory = $false)]
        [string]$Status,

        [Parameter(Mandatory = $false)]
        [int]$Id = 0,

        [Parameter(Mandatory = $false)]
        [int]$ParentId = -1,

        [Parameter(Mandatory = $false)]
        [switch]$Completed
    )

    if (-not $script:UIContext.Initialized) {
        $null = Initialize-EnhancedUI
    }

    if ($script:UIContext.ProgressStyle -eq 'Text') {
        Write-ProgressBarAsText -Activity $Activity -Current $Current -Total $Total -Status $Status -Id $Id -ParentId $ParentId -Completed:$Completed
        return
    }

    Write-ProgressBarAsBar -Activity $Activity -Current $Current -Total $Total -Status $Status -Id $Id -ParentId $ParentId -Completed:$Completed
}


<#
.SYNOPSIS
    Displays a formatted header.

.DESCRIPTION
    Un titre encadré de traits horizontaux. Le filet retombe sur '-' dès que la
    sortie est redirigée ou que la page de code n'est pas UTF-8 — ce qui, sur
    une console 5.1, est le cas courant.

.PARAMETER Title
    The header title.

.PARAMETER Color
    The header color.

.EXAMPLE
    Write-Header "My Application"
#>
function Write-Header {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $false)]
        [string]$Color = 'Cyan'
    )

    if (-not $script:UIContext.Initialized) {
        $null = Initialize-EnhancedUI
    }

    Write-TeeLog -Message $Title -Level 'Info'

    Write-HeaderPS5 -Title $Title -Color $Color

    Write-Host ""
}


<#
.SYNOPSIS
    Displays a formatted summary section.

.PARAMETER Title
    The summary title (default: "Summary").

.EXAMPLE
    Write-Summary
    Write-StatusMessage "Total: 100" -Type Info
#>
function Write-Summary {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Title = 'Summary'
    )

    Write-Host ""
    Write-Header $Title -Color Green
}


<#
.SYNOPSIS
    Prompts the user to pick a subset of items.

.DESCRIPTION
    Invite texte numérotée : "1,3,5", "*" pour tout, vide pour rien. Les
    éléments sont retournés tels quels, type d'origine préservé.

    Il n'y a pas d'invite à cases à cocher en 5.1 — c'est ce que Spectre
    apportait à PS7-Core, et il n'a pas d'équivalent sans dépendance.

    L'invite exige une vraie console. Quand l'entrée est redirigée (tâche
    planifiée, appel par pipe), aucune invite n'est possible : la fonction
    avertit et retourne tous les éléments inchangés, de sorte que l'appelant se
    comporte comme si aucun filtrage n'avait été demandé.

.PARAMETER Items
    The items to choose from. Returned as-is, so any type is preserved.

.PARAMETER Message
    The prompt title.

.PARAMETER LabelProperty
    Name of the property used to label each item. Defaults to its string form.

.EXAMPLE
    $keep = Read-Selection -Items $folders -Message "Folders to process"
#>
function Read-Selection {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [AllowEmptyCollection()]
        [object[]]$Items,

        [Parameter(Mandatory = $false)]
        [string]$Message = 'Select the entries to keep',

        [Parameter(Mandatory = $false)]
        [string]$LabelProperty
    )

    if (-not $script:UIContext.Initialized) {
        $null = Initialize-EnhancedUI
    }

    if ($Items.Count -eq 0) {
        return @()
    }

    # No console to prompt on: keep everything rather than silently dropping items
    if ([Console]::IsInputRedirected) {
        Write-StatusMessage "Input is redirected, interactive selection skipped: all $($Items.Count) entrie(s) kept." -Type Warning
        return $Items
    }

    # Wrap each item so the prompt shows a label while we return the original object
    $choices = @(
        foreach ($item in $Items) {
            $label = if ($LabelProperty) { [string]$item.$LabelProperty } else { [string]$item }

            [PSCustomObject]@{
                Label = $label
                Value = $item
            }
        }
    )

    return Read-SelectionPS5 -Items $Items -Choices $choices -Message $Message
}


<#
.SYNOPSIS
    Scans a root folder's direct subfolders, then prompts the user to pick which to keep.

.DESCRIPTION
    Les candidats sont les sous-dossiers DIRECTS du dossier racine, jamais la
    racine elle-même ni un descendant plus profond. Tout candidat dont le nom
    matche -ExcludeName (insensible à la casse) est écarté.

    Sans -Interactive, tous les candidats sont retournés tels quels. Avec,
    Read-Selection affiche l'invite et seuls les dossiers cochés sont retournés.

.PARAMETER Path
    The root folder to scan. Must exist.

.PARAMETER ExcludeName
    Direct-subfolder names to exclude from the candidates, case-insensitive.

.PARAMETER Interactive
    Show the prompt. Without it, all candidates are returned as-is.

.PARAMETER Message
    The prompt title, used only when -Interactive is set.

.OUTPUTS
    String[]. Full paths of the selected direct subfolders.

.EXAMPLE
    $folders = Read-FolderSelection -Path 'C:\Projects' -ExcludeName '.git' -Interactive
#>
function Read-FolderSelection {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [string[]]$ExcludeName = @(),

        [Parameter(Mandatory = $false)]
        [switch]$Interactive,

        [Parameter(Mandatory = $false)]
        [string]$Message = 'Folders to process'
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Path not found or not a directory: $Path"
    }

    $rootFolder = Get-Item -LiteralPath $Path -Force
    $excludeSet = @($ExcludeName | ForEach-Object { $_.ToLower() })

    $candidates = @()

    foreach ($sub in @(Get-ChildItem -LiteralPath $rootFolder.FullName -Directory -ErrorAction SilentlyContinue)) {
        if ($excludeSet -contains $sub.Name.ToLower()) {
            continue
        }

        $candidates += [PSCustomObject]@{
            Path  = $sub.FullName
            Label = $sub.Name
        }
    }

    if (-not $Interactive) {
        return @($candidates | ForEach-Object { $_.Path })
    }

    $selected = @(Read-Selection -Items $candidates -Message $Message -LabelProperty 'Label')
    return @($selected | ForEach-Object { $_.Path })
}

#endregion


#region Module Initialization

Export-ModuleMember -Function @(
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

#endregion
