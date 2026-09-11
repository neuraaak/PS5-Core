<#
    Rendu console invariant de PS5-Core.UI — la partie qui ne dépend PAS de la
    stratégie de progression : messages de statut, en-tête, invite de sélection.

    Dot-sourcé par PS5-Core.UI.psm1 au chargement, donc ces fonctions vivent
    dans la portée du module et voient les variables $script:*. Elles sont
    internes : seules les fonctions publiques du .psm1 sont exportées.

    Contrainte 5.1 assumée partout ici : cmdlets d'abord, aucun appel .NET qui
    ne soit pas une simple lecture de propriété. Concrètement, pas de
    [Math]::Min et pas d'Add-Type — ce sont les deux premières choses qu'un
    hôte verrouillé en Constrained Language Mode refuse, et aucune des deux
    n'apporte quoi que ce soit ici.

    Différence délibérée avec le backend natif de PS7-Core : celui-ci active le
    traitement VT100 par P/Invoke Win32, nécessaire aux invites Spectre. Il n'y
    a pas de Spectre en 5.1, et Write-Host -ForegroundColor passe par l'API
    console, pas par des séquences ANSI. Le P/Invoke n'est donc pas porté.
#>

# Largeur de console utilisable, avec repli quand il n'y a pas de vrai hôte
# (sortie redirigée, tâche planifiée) : RawUI.WindowSize y lève ou renvoie 0.
function Get-ConsoleWidthPS5 {
    try {
        $width = $Host.UI.RawUI.WindowSize.Width
        if ($width -gt 20) {
            $usable = $width - 1
            if ($usable -gt 120) { return 120 }
            return $usable
        }
    }
    catch {
        Write-Verbose "Console width unavailable, using default: $_"
    }
    return 78
}

# Borne un pourcentage sans [Math]::Min / [Math]::Max, bloqués en Constrained
# Language Mode.
function Get-ClampedPercentPS5 {
    param(
        [int]$Current,
        [int]$Total
    )

    if ($Total -le 0) { return 0 }

    $percent = [int](($Current / $Total) * 100)
    if ($percent -lt 0) { return 0 }
    if ($percent -gt 100) { return 100 }
    return $percent
}

function Write-StatusMessagePS5 {
    param(
        [string]$Message,
        [string]$Type
    )

    # Mêmes préfixes et mêmes couleurs que PS7-Core, afin qu'un script produise
    # une sortie reconnaissable quelle que soit la bibliothèque qui le porte.
    switch ($Type) {
        'Info' { Write-Host $Message -ForegroundColor Cyan }
        'Success' { Write-Host "OK: " -ForegroundColor Green -NoNewline; Write-Host $Message }
        'Warning' { Write-Host "WARN: " -ForegroundColor Yellow -NoNewline; Write-Host $Message }
        'Error' { Write-Host "ERROR: " -ForegroundColor Red -NoNewline; Write-Host $Message }
        'Skipped' { Write-Host "SKIP: " -ForegroundColor DarkGray -NoNewline; Write-Host $Message }
        'Debug' { Write-Host "DEBUG: " -ForegroundColor DarkGray -NoNewline; Write-Host $Message }
        default { Write-Host $Message }
    }
}

# Caractère de filet. U+2500 n'est lisible que si la sortie est réellement en
# UTF-8. En 5.1 la page de code par défaut d'une console Windows est souvent
# 850 ou 437, où le trait fin ressort en mojibake — le repli ASCII est donc le
# cas NORMAL ici, pas l'exception qu'il est en PS7.
#
# PS5-Core ne force jamais [Console]::OutputEncoding : l'écriture de cette
# propriété est refusée en Constrained Language Mode, et changer l'encodage de
# sortie d'un hôte 5.1 a des effets de bord sur tout ce qui écrit après nous.
# On observe l'encodage, on ne le modifie pas.
function Get-RuleCharPS5 {
    try {
        # Sortie redirigée : [Console]::OutputEncoding ne dit rien du décodeur
        # en aval (fichier, pipe, capture CI). L'ASCII garde les journaux lisibles.
        if ([Console]::IsOutputRedirected) { return '-' }

        if ([Console]::OutputEncoding.CodePage -eq 65001) { return [string][char]0x2500 }
    }
    catch {
        Write-Verbose "Output encoding unavailable: $_"
    }
    return '-'
}

function Write-HeaderPS5 {
    param(
        [string]$Title,
        [string]$Color = 'Cyan'
    )

    $consoleColor = try { [System.ConsoleColor]$Color } catch { [System.ConsoleColor]::Cyan }

    $width = Get-ConsoleWidthPS5
    $label = " $Title "
    $lead = 2
    $trail = $width - $lead - $label.Length
    if ($trail -lt 0) { $trail = 0 }
    $rule = Get-RuleCharPS5

    Write-Host ($rule * $lead) -ForegroundColor DarkGray -NoNewline
    Write-Host $label -ForegroundColor $consoleColor -NoNewline
    Write-Host ($rule * $trail) -ForegroundColor DarkGray
}

function Read-SelectionPS5 {
    param(
        [object[]]$Items,
        [PSCustomObject[]]$Choices,
        [string]$Message
    )

    # Invite texte numérotée. Il n'y a pas d'équivalent 5.1 au prompt à cases à
    # cocher de Spectre : Read-Host est le seul mécanisme disponible sans
    # dépendance, et il a l'avantage de fonctionner sur n'importe quel hôte.
    Write-Host ""
    Write-StatusMessagePS5 -Message $Message -Type Info

    for ($i = 0; $i -lt $Choices.Count; $i++) {
        Write-Host ("  [{0}] {1}" -f ($i + 1), $Choices[$i].Label)
    }

    Write-Host ""
    $answer = Read-Host "Entries to keep (e.g. 1,3,5 - '*' for all - empty for none)"
    $answer = $answer.Trim()

    if ([string]::IsNullOrEmpty($answer)) {
        return @()
    }

    if ($answer -eq '*') {
        return $Items
    }

    $picked = @()

    foreach ($token in $answer.Split(',')) {
        $token = $token.Trim()
        $index = 0

        if ([int]::TryParse($token, [ref]$index) -and $index -ge 1 -and $index -le $Choices.Count) {
            $picked += $Choices[$index - 1].Value
        }
        else {
            Write-StatusMessagePS5 -Message "Ignored invalid entry: $token" -Type Warning
        }
    }

    return $picked
}


function Read-ConfirmationPS5 {
    param(
        [string]$Message,
        [bool]$DefaultValue
    )

    # Le libellé porte le défaut en majuscule : c'est la seule indication que
    # reçoit l'utilisateur quand il valide une ligne vide.
    $hint = if ($DefaultValue) { '[O/n]' } else { '[o/N]' }

    while ($true) {
        Write-Host ''
        $answer = (Read-Host "$Message $hint").Trim()

        if ([string]::IsNullOrEmpty($answer)) {
            return $DefaultValue
        }

        switch -Regex ($answer) {
            '^(o|oui|y|yes)$' { return $true }
            '^(n|non|no)$' { return $false }
            default {
                Write-StatusMessagePS5 -Message "Répondre 'o' ou 'n'." -Type Warning
            }
        }
    }
}

function Get-TextInputRejectionPS5 {
    <#
        Retourne $null quand la valeur est acceptable, sinon le motif du refus.
        Partagé par l'invite ET par la garde non interactive : c'est le seul
        endroit qui décide ce qu'est une saisie valide, pour qu'une valeur
        refusée à l'invite ne puisse pas être acceptée comme défaut.
    #>
    param(
        [string]$Value,
        [bool]$AllowEmpty,
        [scriptblock]$Validate
    )

    if ([string]::IsNullOrEmpty($Value) -and -not $AllowEmpty) {
        return 'Une valeur est requise.'
    }

    if ($null -eq $Validate) {
        return $null
    }

    # $_ dans le scriptblock de validation : c'est la convention PowerShell
    # (ValidateScript), et l'appelant l'attend plutôt qu'un paramètre nommé.
    $accepted = ForEach-Object -InputObject $Value -Process $Validate

    if ($accepted) {
        return $null
    }

    return "La valeur '$Value' n'est pas valide."
}

function Read-TextInputPS5 {
    param(
        [string]$Message,
        [string]$Default,
        [bool]$HasDefault,
        [bool]$AllowEmpty,
        [scriptblock]$Validate
    )

    $hint = if ($HasDefault -and -not [string]::IsNullOrEmpty($Default)) { " [$Default]" } else { '' }

    while ($true) {
        Write-Host ''
        $answer = (Read-Host "$Message$hint").Trim()

        if ([string]::IsNullOrEmpty($answer) -and $HasDefault) {
            $answer = $Default
        }

        $rejection = Get-TextInputRejectionPS5 -Value $answer -AllowEmpty $AllowEmpty -Validate $Validate

        if ($null -eq $rejection) {
            return $answer
        }

        Write-StatusMessagePS5 -Message $rejection -Type Warning
    }
}

function Start-SpinnerPS5 {
    param(
        [string]$Message,
        [scriptblock]$ScriptBlock
    )

    # Pas d'animation : la faire tourner demanderait un runspace concurrent pour
    # un gain purement cosmétique. On annonce, puis on exécute — exactement ce
    # que fait la stratégie Text pour la progression.
    Write-StatusMessagePS5 -Message "$Message..." -Type Info
    return & $ScriptBlock
}
