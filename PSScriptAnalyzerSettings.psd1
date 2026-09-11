<#
    Configuration PSScriptAnalyzer de PS5-Core.

    Detectee automatiquement par l'extension PowerShell de VS Code : c'est la
    valeur par defaut de `powershell.scriptAnalysis.settingsPath`, a condition
    d'ouvrir CE dossier comme racine du workspace. Si le workspace ouvert est
    E:\dev\powershell (les deux depots a la fois), pointer explicitement :

        "powershell.scriptAnalysis.settingsPath": "PS5-Core/PSScriptAnalyzerSettings.psd1"

    Le meme fichier sert au formatage : les regles PSPlaceOpenBrace & consorts
    sont celles qu'appliquent `Invoke-Formatter` ET le formateur de l'extension,
    ce qui evite qu'un formatage a la main diverge de ce que verifie le lint.

    Style retenu : Stroustrup (accolade ouvrante en fin de ligne, `else` et
    `catch` sur leur propre ligne), 4 espaces. Ce n'est pas un gout : c'est ce
    que fait deja tout le code de ce depot.

    Jumeau : PS7-Core/PSScriptAnalyzerSettings.psd1. Les deux fichiers sont
    identiques a UNE regle pres, PSUseBOMForUnicodeEncodedFile — voir plus bas.
#>

@{
    # Les regles par defaut, moins les exclusions ci-dessous.
    IncludeDefaultRules = $true

    ExcludeRules        = @(
        # Cette bibliotheque EST une couche d'affichage console : Write-Host y
        # est l'outil, pas un defaut. 89 occurrences, toutes deliberees.
        'PSAvoidUsingWriteHost',

        # `Start-ProgressScope` ouvre une region d'affichage
        # et n'alterent aucun etat systeme : -WhatIf n'aurait rien a annoncer.
        # C'est le verbe qui declenche la regle, pas le comportement.
        'PSUseShouldProcessForStateChangingFunctions',

        # Severity Information, et se declenche sur des fonctions dont le type
        # de retour est deja documente dans l'aide.
        'PSUseOutputTypeCorrectly',

        # Ne remonte que sur des helpers internes aux harnais de test
        # (Test-Throws, Test-Rejects, Invoke-RobustnessChecks) : renommer
        # nuirait a la lisibilite des tests sans rien apporter a la surface
        # publique, qui est la seule que cette regle protege utilement.
        'PSUseSingularNouns',

        # Faux positif verifie : `Get-Command Write-Log` ne renvoie RIEN dans un
        # `pwsh -NoProfile` vierge. La base de la regle reference un cmdlet
        # d'un module Windows absent d'ici.
        'PSAvoidOverwritingBuiltInCmdlets'
    )

    # Volontairement LAISSEES ACTIVES, bien qu'elles remontent aujourd'hui :
    #   PSAvoidUsingEmptyCatchBlock       les catch vides d'ici sont deliberes,
    #                                     mais la regle attrape aussi les vrais
    #                                     oublis - le bruit est le prix du filet.
    #   PSAvoidUsingBrokenHashAlgorithms  MD5 est supporte expres par la lib de
    #                                     hachage ; le signal securite reste utile.
    #   PSReviewUnusedParameter           signale un parametre mort.
    #   PSUseDeclaredVarsMoreThanAssignments  variable assignee jamais relue.

    # PSUseBOMForUnicodeEncodedFile est ACTIVE ici, contrairement a PS7-Core :
    # sans BOM, Windows PowerShell 5.1 lit les .ps1 en ANSI et corrompt les
    # accents. Le depot est deja a 0 remontee sur cette regle - elle sert de
    # garde-fou, pas de dette.

    Rules               = @{

        # --- Formatage : accolades -------------------------------------
        # OnSameLine + NewLineAfter sur la fermante = Stroustrup. En OTBS, le
        # `else` remonterait coller la fermante, ce que ce depot ne fait pas.
        PSPlaceOpenBrace           = @{
            Enable             = $true
            OnSameLine         = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
        }

        PSPlaceCloseBrace          = @{
            Enable             = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
            NoEmptyLineBefore  = $false
        }

        # --- Formatage : indentation et espaces ------------------------
        PSUseConsistentIndentation = @{
            Enable              = $true
            Kind                = 'space'
            IndentationSize     = 4
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
        }

        PSUseConsistentWhitespace  = @{
            Enable          = $true
            CheckInnerBrace = $true
            CheckOpenBrace  = $true
            CheckOpenParen  = $true
            CheckPipe       = $true
            CheckSeparator  = $true

            # $false, et ce n'est PAS un oubli : CheckOperator exige un espace
            # unique autour de `=`, ce qui defait l'alignement que
            # PSAlignAssignmentStatement pose juste en dessous. Les deux regles
            # se contredisent ; ce depot aligne, donc celle-ci cede.
            CheckOperator   = $false
        }

        # Les hashtables de ce depot sont alignees sur le `=` (voir
        # $script:UIContext) : la regle entretient cet alignement au lieu de le
        # defaire a chaque formatage.
        PSAlignAssignmentStatement = @{
            Enable         = $true
            CheckHashtable = $true
        }

        # Desactivee : la regle reclame de reecrire l'operateur `-eq` en `EQ`,
        # ce qui n'est pas une correction de casse mais un defaut connu de son
        # implementation.
        PSUseCorrectCasing         = @{
            Enable = $false
        }
    }
}
