# PS5-Core

Bibliothèque de modules PowerShell réutilisables, pour **Windows PowerShell 5.1**.

Portage de [PS7-Core](../PS7-Core) pour les scripts qui **sont lancés** par
Windows PowerShell 5.1, indépendamment de ce qui est installé sur la machine :
double-clic sur un `.ps1`, `.cmd`, tâche planifiée, SCCM, GPO — autant de
mécanismes qu'on ne contrôle pas et qui retombent sur `powershell.exe`, même
là où `pwsh` est présent par ailleurs.

Même surface publique que PS7-Core, mêmes principes de conception ; ce qui
change est documenté ci-dessous, et rien d'autre.

Le nom porte la contrainte, comme celui de PS7-Core : les deux bibliothèques
cohabitent sans conflit de nom ni de GUID, et un script choisit la sienne selon
l'hôte qu'il vise.

## Contenu

```txt
PS5-Core/                  le module (cible de la jonction d'installation)
├── PS5-Core.psd1/.psm1    méta-module : charge les trois sous-modules
├── PS5-Core.Runtime/      garde d'exécution 5.1
├── PS5-Core.UI/           console, deux stratégies de progression
│   ├── Private/           rendu invariant : messages, en-tête, sélection
│   └── Progress/          Bar.ps1 et Text.ps1
└── PS5-Core.Crypto/       hachage de fichiers et de chaînes
```

## Prérequis

Windows PowerShell **5.1**, et rien d'autre. Aucune dépendance externe, aucun
module à installer.

## Les deux stratégies de progression

**C'est le seul vrai écart de conception avec PS7-Core, et il n'est pas
gratuit.** PS7-Core s'appuie sur la vue `Minimal` de `Write-Progress` — une
ligne discrète, validée en terminal réel sous forte charge d'impression. Cette
vue arrive avec `$PSStyle` en **PowerShell 7.2** et n'existe pas en 5.1 :

```powershell
PS 5.1> [bool](Get-Variable PSStyle -ErrorAction SilentlyContinue)   # False
PS 7.6> $PSStyle.Progress.View                                       # Minimal
```

Windows PowerShell n'a donc que la **vue classique** : le bandeau pleine largeur
ancré en haut de la console. Les *paramètres* de `Write-Progress` sont pourtant
identiques dans les deux versions — le code s'exécute sans erreur en 5.1, seul
le rendu diffère. Un test qui vérifie l'absence d'exception ne détecte rien.

| Stratégie | Base                            | Rendu                                                       |
| --------- | ------------------------------- | ----------------------------------------------------------- |
| `Bar`     | `Write-Progress`, vue classique | bandeau en haut de console ; la région est effacée à la fin |
| `Text`    | lignes de statut périodiques    | une ligne tous les 10 % dans le flux ; la dernière reste    |

`Text` existe parce que les décalages d'affichage viennent tous de la
coexistence d'une **région redessinée** avec un flux de texte qui avance.
Supprimer la région supprime la classe de bug, plutôt que de la gérer — le même
arbitrage que celui déjà rendu dans PS7-Core contre la barre inline maison.

> **Prémisse testée, et écartée.** `Text` a été écrit en supposant que la vue
> classique produisait des décalages avec les `Write-Host` entrelacés. **C'est
> faux** — vérifié le 2026-09-08 en terminal réel (Windows Terminal, 5.1.26100),
> scénarios 3 et 5 puis `-Thorough` : aucune ligne perdue, aucun texte écrasé,
> aucun résidu de bandeau après complétion. `Bar` est donc le défaut en console,
> par mesure et non par défaut d'alternative. Ne pas ré-instruire ce procès sans
> élément nouveau.
>
> Ce qui reste vrai de `Text` : il est le seul à laisser une **trace** dans la
> sortie relue après coup, et son rendu est identique en console, en fichier et
> en tâche planifiée. C'est ce qui lui vaut d'être conservé, et choisi par
> `Auto` dès que la sortie est redirigée.
>
> Non couvert : le **conhost hérité** (un `.cmd` double-cliqué depuis
> l'Explorateur), où le rendu de la vue classique peut différer.

Comme dans PS7-Core, la stratégie est résolue **une fois**, par
`Initialize-EnhancedUI`, jamais par appel :

```powershell
Initialize-EnhancedUI                        # Auto
Initialize-EnhancedUI -ProgressStyle Bar     # force le bandeau
Initialize-EnhancedUI -ProgressStyle Text    # force les lignes de statut
```

`Auto` choisit `Text` quand la sortie est **redirigée** — il n'y a alors aucune
région où dessiner, et `Write-Progress` ne rendrait rien du tout — et `Bar`
sinon. La bascule affiche **une ligne, une seule fois** : jamais de dégradation
silencieuse. La stratégie active se lit par `(Get-UIContext).ProgressStyle`.

> **`Get-UIContext` est le seul accès.** L'état vit dans une variable de module
> non exportée : `Export-ModuleMember -Variable` ne traverse pas la frontière de
> sous-module imbriqué. Piège hérité de PS7-Core, payé une fois.

## Ce qui n'est pas porté de PS7-Core, et pourquoi

| Élément                            | Raison                                                                                                  |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------- |
| Backend Spectre                    | `PwshSpectreConsole` est PS7-only, sans équivalent 5.1                                                  |
| Invite à cases à cocher            | c'est ce que Spectre apportait ; `Read-Host` numéroté la remplace                                       |
| Vue `Minimal` de `Write-Progress`  | `$PSStyle` n'existe pas avant 7.2                                                                       |
| P/Invoke VT100 (`Add-Type`)        | ne servait qu'aux invites Spectre ; `Write-Host -ForegroundColor` passe par l'API console, pas par ANSI |
| `[Console]::OutputEncoding = UTF8` | effets de bord sur tout ce qui écrit ensuite ; on **observe** l'encodage, on ne le modifie pas          |

Deux conséquences directes :

- le filet de `Write-Header` retombe sur `-` dès que la page de code n'est pas
  UTF-8, ce qui sur une console 5.1 est le cas **courant** (souvent 850 ou 437),
  là où c'était l'exception en PS7 ;
- le code évite `[Math]::Min` et `Add-Type`. Ce sont les premières choses qu'un
  hôte verrouillé en **Constrained Language Mode** refuse, et aucune n'apportait
  quoi que ce soit. `Get-FileHashExtended` passe d'ailleurs par la cmdlet
  `Get-FileHash` plutôt que par un flux `[SHA256]` — plus court, et plus
  susceptible de survivre là-bas.

> **CLM mesuré sur le poste cible, et écarté.** Diagnostic du 2026-09-09, sous
> 5.1 et sous pwsh 7.5.4 : `LanguageMode = FullLanguage` dans les deux, Code
> Integrity usermode `Off`, AppLocker `NotConfigured`. Les précautions ci-dessus
> restent, elles ne coûtent rien et couvrent un autre poste — mais **ce n'est
> pas une contrainte active ici**. `Get-StringHash` utilise toujours .NET
> (aucune cmdlet n'équivaut) et tomberait en CLM ; le mode se lit par
> `$ExecutionContext.SessionState.LanguageMode`.

**Deux contraintes réelles relevées sur ce poste, et celles-là mordent :**

- **`ExecutionPolicy = MachinePolicy=RemoteSigned` sous 5.1**, imposée par GPO,
  donc non contournable par `Set-ExecutionPolicy -Scope CurrentUser`. Tout
  `.ps1` arrivé par zip — PS5-Core compris — doit passer par `Unblock-File`.
- **Le dossier de modules de 5.1 n'est pas celui de PS7** :
  `Documents\WindowsPowerShell\Modules`, et non `Documents\PowerShell\Modules`
  que Windows PowerShell ignore. Voir la section Installation.

## Utilisation

Le dossier **parent** de `PS5-Core/` va sur `PSModulePath`, puis un import
unique — `NestedModules` charge les trois sous-modules :

```powershell
$env:PSModulePath += ";<dossier parent de PS5-Core>"
Import-Module PS5-Core
```

> **Piège.** Après l'import, les sous-modules ne sont plus des modules de
> premier niveau : `Get-Module PS5-Core.UI` retourne `$null`. Pour les
> atteindre :
> `(Get-Module PS5-Core).NestedModules | Where-Object Name -eq 'PS5-Core.UI'`.

Dans un script, épingler la version **après** l'import :

```powershell
#Requires -Version 5.1

$env:PSModulePath += ";<dossier parent de PS5-Core>"
try { Import-Module PS5-Core -ErrorAction Stop }
catch { throw "PS5-Core introuvable. Lancez le script d'installation du projet." }

$ps5Core = Get-Module PS5-Core
if ($ps5Core.Version -lt [version]'1.0.0') {
    throw "PS5-Core $($ps5Core.Version) est trop ancien, 1.0.0 minimum requis."
}
```

> **N'utilisez pas `#Requires -Modules`.** La directive est évaluée *avant* le
> corps du script, donc avant que celui-ci ait complété `PSModulePath` : avec
> une liaison par jonction elle échoue systématiquement. Le contrôle se fait
> après l'import, et **hors du `try`** — sinon une version insuffisante serait
> rapportée comme un module introuvable.

`CompatiblePSEditions` est délibérément **non déclaré** : le module se charge
aussi sous PowerShell 7. `PowerShellVersion = '5.1'` est un plancher, pas un
plafond. C'est ce qui permet de comparer les deux stratégies de progression sur
un seul poste.

## Installation

PS5-Core ne s'installe pas lui-même : le bootstrap ne peut pas vivre dans le
dépôt qu'il doit cloner. **C'est au projet consommateur** de porter son script
d'installation — un clone hors dossier synchronisé, puis une jonction de
répertoire vers `PS5-Core/`.

## Fonctions exportées

La surface est **identique à celle de PS7-Core**, au nom du garde près : un
script écrit pour l'une s'exécute sur l'autre sans modification.

### PS5-Core.Runtime

| Fonction             | Rôle                                                                              |
| -------------------- | --------------------------------------------------------------------------------- |
| `Assert-PowerShell5` | Lève si PS < 5.1 (ou `-MinimumVersion`). C'est un plancher : passe aussi sous PS7 |

### PS5-Core.UI

| Fonction                | Rôle                                                                     |
| ----------------------- | ------------------------------------------------------------------------ |
| `Initialize-EnhancedUI` | Initialise l'UI et résout la stratégie (`Auto`/`Bar`/`Text`)             |
| `Get-UIContext`         | Stratégie active et état d'initialisation                                |
| `Write-Header`          | En-tête de section                                                       |
| `Write-StatusMessage`   | Message typé (`Info`, `Success`, `Warning`, `Error`, `Skipped`, `Debug`) |
| `Write-ProgressBar`     | Progression, rendue selon la stratégie résolue                           |
| `Write-Summary`         | Résumé de fin d'exécution                                                |
| `Read-Selection`        | Invite texte numérotée générique                                         |
| `Read-FolderSelection`  | Racine + sous-dossiers directs, exclusion par nom, sélection optionnelle |
| `Start-ProgressScope`   | Scope d'exécution ; voir le piège ci-dessous                             |
| `Read-Confirmation`     | Question oui/non ; rend `-DefaultValue` quand l'entrée est redirigée     |
| `Read-TextInput`        | Saisie d'une ligne, avec `-Default`, `-AllowEmpty` et `-Validate`        |
| `Start-Spinner`         | Indicateur d'activité pour un travail de durée inconnue                  |

> **Piège de scope.** Aucune stratégie n'ouvre de région live, donc
> `Start-ProgressScope` n'a rien à monter — mais **c'est un vrai scope**,
> invoqué via `&` comme celui de PS7-Core. C'est délibéré : un passe-plat sans
> scope ferait « marcher » ici du code qui casserait une fois porté sous
> PS7-Core. Toute variable réaffectée dans le scriptblock (`=`, `+=`, `++`) crée
> une copie locale perdue à la sortie ; muter un membre d'objet
> (`$table[$k] = $v`, `$liste.Add(...)`) fonctionne. Pour accumuler, utiliser
> `[System.Collections.Generic.List[object]]`.

`Start-Spinner` couvre le travail dont on ignore la durée, là où
`Write-ProgressBar` n'a aucun pourcentage à afficher. Il **n'anime rien** ici :
il annonce, puis exécute — animer demanderait un runspace concurrent pour un
gain purement cosmétique.

`Start-Spinner` et `Start-ProgressScope` se refusent mutuellement, **dans les
deux sens**. La contrainte vient de PS7-Core, où Spectre ne sait empiler ni un
Status dans un Progress ni l'inverse. Elle n'a pas de raison technique d'être
ici, et c'est délibéré : autoriser en 5.1 ce que PS7-Core refuse ferait
« marcher » du code qui casserait une fois porté — le même raisonnement que
pour le scope ci-dessus.

#### Invites sans console

`Read-Confirmation` et `Read-TextInput` ne peuvent pas bloquer sur un hôte où
l'entrée est redirigée (CI, pipe, harnais de test). La règle est unique :
**rendre le défaut s'il existe, lever sinon.**

| Appel                                              | Entrée redirigée           |
| -------------------------------------------------- | -------------------------- |
| `Read-Confirmation -Message m`                     | `$false` (+ avertissement) |
| `Read-Confirmation -Message m -DefaultValue $true` | `$true` (+ avertissement)  |
| `Read-TextInput -Message m -Default d`             | `d` (+ avertissement)      |
| `Read-TextInput -Message m`                        | **lève**                   |

`Read-Confirmation` a toujours un défaut, donc ne lève jamais : une exécution
sans surveillance ne confirme rien que personne n'a approuvé. `Read-TextInput`
n'en a pas toujours, et rendre `''` en silence laisserait un script continuer
avec une valeur que personne n'a choisie. `-Default` est soumis aux mêmes
règles qu'une saisie : vide sans `-AllowEmpty`, ou refusé par `-Validate`, il
lève plutôt que de passer sans contrôle.

Il n'y a **pas** de commutateur `-Force` : l'appelant qui veut piloter le mode
non interactif fournit déjà `-DefaultValue` / `-Default`.

Le paramètre `-Spinner` de `Start-Spinner` est accepté mais ignoré : il existe
pour que la signature reste identique à celle de PS7-Core, où il choisit le
style d'animation Spectre.

### PS5-Core.Crypto

| Fonction               | Rôle                                                     |
| ---------------------- | -------------------------------------------------------- |
| `Get-FileHashExtended` | Hash d'un fichier (SHA256 / SHA1 / MD5), chemin littéral |
| `Get-StringHash`       | Hash d'une chaîne                                        |
| `Test-FileIntegrity`   | Compare un fichier à un hash attendu                     |

### Logging fichier

Le logging est **opt-in** : tant que `Initialize-Logging` n'a pas ete
appele, rien n'est ecrit et aucun fichier n'est cree.

```powershell
Import-Module PS5-Core
Initialize-Logging -Path "$env:LOCALAPPDATA\MonScript\run.log"

Write-StatusMessage "Traitement demarre" -Type Info   # affiche ET logue
Write-Log -Message "detail interne" -Level Debug      # logue seulement
```

| Fonction | Role |
| --- | --- |
| `Initialize-Logging -Path <f> [-MinimumLevel <n>]` | Active le log. Peut lever si le chemin est inutilisable. |
| `Write-Log -Message <m> [-Level <n>]` | Ecrit une ligne. Ne leve jamais. |
| `Get-LogContext` | Etat courant : `Enabled`, `Path`, `MinimumLevel`. |

Niveaux : `Debug` < `Info` (defaut) < `Warning` < `Error`.

`Write-StatusMessage` et `Write-Header` alimentent le log automatiquement.
`Write-ProgressBar` non : la progression noierait la trace.

Il n'y a **pas de rotation** : pour un fichier par execution, mettre un
horodatage dans le `-Path`. Un echec d'ecriture desactive le log et emet un
avertissement, sans interrompre le script.

## Encodage des fichiers source

Les `.ps1`, `.psm1` et `.psd1` sont en **UTF-8 avec BOM**, et doivent le rester.
Sans BOM, Windows PowerShell 5.1 lit un script comme de l'ANSI et corrompt tout
caractère accentué — y compris dans les chaînes littérales. C'est une contrainte
propre à 5.1 : PowerShell 7 suppose UTF-8 par défaut et ne la partage pas.

## Versionnage

**Un seul numéro pour toute la bibliothèque** : les quatre manifestes portent le
même `ModuleVersion` et bougent ensemble. Les sous-modules ne s'expédient jamais
seuls, donc une version propre à chacun ne renseignerait personne et ne ferait
que dériver. `ModuleVersion` fait foi ; les blocs `.NOTES` ne portent pas de
numéro, et l'historique cumulatif vit dans le seul `ReleaseNotes` de la racine.

## Ajouter une fonction

Mettre à jour `FunctionsToExport` du `.psd1` **du sous-module et de la
racine** — sinon la fonction n'est pas visible à l'import.

## Tests

```powershell
.\tests\Test-PS5Core.ps1                        # suite automatisée, stratégie Bar
.\tests\Test-PS5Core.ps1 -ProgressStyle Text    # même suite, stratégie Text
```

La suite doit passer dans les **deux** stratégies. Elle ne juge aucun rendu :
elle vérifie des contrats (bornes, refus, parité du piège de portée) et compare
le hachage à des vecteurs de référence publics.

### Comparaison des deux stratégies

```powershell
.\tests\Show-UiProgress.Bar.ps1
.\tests\Show-UiProgress.Text.ps1
```

Deux volets, définis dans `tests/UiProgressChecks.ps1` — partagé par les deux
lanceurs, pour que les stratégies soient mesurées exactement pareil et ne
dérivent pas l'une de l'autre :

- **Robustesse** — assertions exécutables sans terminal (`-SkipVisual`) :
  bornes, paramètres refusés, `$null` sur paramètre obligatoire, imbrication de
  scope, remise à plat après exception, parité du piège de portée enfant.
- **Rendu** — six scénarios à inspecter **à l'œil** (`-OnlyVisual`), dont les
  trois qui décident : progression avec messages entrelacés, ligne partielle
  (`-NoNewline`) suivie d'une progression, et ce qu'il reste dans la sortie une
  fois l'activité terminée. `-Thorough` ajoute la charge d'impression.

> Le volet rendu n'a de sens que dans un **vrai terminal**. En sortie redirigée
> `Write-Progress` ne dessine rien : le volet `Bar` serait vide et la
> comparaison truquée en faveur de `Text`. Le script le signale s'il détecte une
> redirection.

C'est ce volet qui doit trancher la stratégie par défaut. Aucune assertion ne
sait répondre à « est-ce que ça s'affiche proprement » — seul un humain devant
une vraie console le peut.

## Licence

MIT
