# Revue de sécurité — 14 septembre 2026

Revue du code local Aura Glass : commandes Bash, Python embarqué, imports et exports,
installation et téléchargements, intégration GDM, services utilisateur et CI.
Les corrections sont dans le dépôt ; les copies déjà installées ne sont pas mises à jour par cet audit.

## Problèmes corrigés

| Gravité | Constat | Correction |
| --- | --- | --- |
| Élevée | `bundle apply` exécutait le nom et les autres métadonnées via `eval`. Un bundle de test a effectivement créé un fichier témoin en exécutant une commande. | Suppression d’`eval`, transmission des valeurs comme données séparées par NUL, validation préalable du manifeste et arrêt sur erreur. |
| Élevée | Les noms de fichiers, descriptions de profils et plusieurs valeurs étaient injectés dans le texte de programmes Python. | Arguments `sys.argv` et heredocs protégés dans les commandes bundle, profile, wallpaper, apps, sound, bench et les raccourcis du CLI. |
| Élevée | Le vérificateur de sauvegardes acceptait un lien symbolique sortant. Les bundles utilisaient une extraction tar sans politique explicite. | Lecteur commun `lib/safe_archive.py` : refus des chemins absolus et `..`, liens symboliques et physiques, fichiers spéciaux, fichiers sparse et doublons ; taille déclarée totale limitée à 512 Mio et nombre d’entrées à 10 000. |
| Élevée | Un nom de profil importé pouvait servir de chemin hors du dossier des profils, notamment lors d’une copie ou suppression. | Validation des noms pour importer, sauvegarder, retrouver et supprimer ; nom du fichier d’export de bundle par défaut limité à des caractères sûrs. |
| Moyenne | Le téléchargement MiSans continuait après une empreinte SHA-256 incorrecte. | Échec bloquant avant décompression ; une nouvelle version nécessite de vérifier le fichier et de mettre à jour son empreinte. |
| Moyenne | La mesure PPI écrivait dans un fichier prévisible de `/tmp`, exposé à une préparation par un autre utilisateur. | Suppression de ce cache partagé ; mesure directe. |

L’extraction prépare les fichiers dans un dossier temporaire privé, ignore les propriétaires
et permissions de l’archive, ouvre les dossiers de destination sans suivre leurs liens,
et remplace les fichiers par renommage pour ne pas écrire au travers d’un lien existant.
Les sauvegardes ne peuvent plus remplacer `repo-path`, utilisé pour retrouver du code
exécutable : ce fichier est exclu des nouveaux exports et refusé à l’import.

Le helper d’archives est installé avec le CLI et supprimé par la désinstallation.
La CI limite également son jeton à `contents: read` et ne conserve plus les identifiants du checkout.

## Vérifications

- Reproduction initiale confinée : commande exécutée par les métadonnées d’un bundle ; lien sortant accepté par `backup verify`.
- `tools/check-security.py` : 13 tests, avec archives hostiles, noms et descriptions contenant des apostrophes, traversées de chemins, liens de destination préexistants, limites de taille, import depuis une installation copiée et mauvaise empreinte de téléchargement.
- Suite générale : **42 suites réussies en 26 secondes**, dans une configuration temporaire avec un bus D-Bus distinct. Le test de sécurité contenait alors 11 tests ; les deux tests supplémentaires ont été vérifiés ensuite.
- Validation Bash individuelle des scripts `bin/`, des bibliothèques Bash et de la désinstallation ; ShellCheck sur les scripts modifiés ; compilation du helper Python ; `git diff --check`.
- Recherche ciblée de formats courants de clés privées et jetons dans les fichiers du dépôt : aucune correspondance. L’historique Git n’a pas été analysé pour les secrets.

Le lanceur temporaire a rencontré un montage GVFS déconnecté pendant son nettoyage,
après le succès des tests. Le répertoire a ensuite été nettoyé. Les tests dépendant
d’un bureau installé peuvent être ignorés par leurs propres conditions : ce résultat
ne constitue pas une validation visuelle de GNOME ou une installation réelle de GDM.

## Limites et compatibilité

- Les anciennes archives contenant des liens ou `repo-path` sont désormais refusées.
  Les profils utilisent des noms de 1 à 128 caractères : lettres ASCII, chiffres,
  espaces, `_` et `-`, avec une lettre ou un chiffre au début.
- La restauration complète n’est pas transactionnelle : un échec d’écriture peut
  laisser une restauration partielle. La sauvegarde préalable est conservée.
- Les dépendances tierces ne sont pas intégralement auditées : extensions GNOME,
  scripts du thème utilisés avec `sudo` pour GDM, paquets AUR, bibliothèques et
  décodeurs d’images/polices du système. Aucune certification d’absence de failles
  ou analyse exhaustive des CVE de ces composants n’est revendiquée.
- Aucun installateur privilégié ni modification de GDM n’a été exécuté pour cette revue.

Référence technique : la [documentation officielle de `tarfile`](https://docs.python.org/3/library/tarfile.html#extraction-filters)
décrit les risques des chemins, liens et fichiers spéciaux, ainsi que le changement
du filtre d’extraction par défaut en Python 3.14. La politique du projet est explicite
et ne dépend pas de ce défaut.

## Seconde passe — daemon, Flatpak et contrôles automatiques

Quatre améliorations supplémentaires ont été appliquées :

1. **Écriture au travers d’un lien depuis un dossier Flatpak — élevée.**
   Une application peut préparer `gtk.css.aurabackup` comme lien vers un fichier
   extérieur à son dossier. La copie exécutée par le programme hôte écrasait cette
   cible avec le contenu CSS choisi par l’application. Reproduit sur un fichier
   témoin temporaire avec l’ancien code. Les dossiers sont maintenant ouverts
   avec `O_NOFOLLOW`, les sauvegardes créées exclusivement et les liens de thème
   remplacés par renommage. Le premier original est conservé ; les liens étrangers
   ne sont pas supprimés lors du retrait du thème.
2. **Arrêt d’un processus arbitraire via `daemon.pid` — moyenne.**
   L’ancien code arrêtait effectivement un processus `sleep` de test après
   remplacement du PID enregistré. Le code vérifie maintenant la commande, le
   chemin du script et l’argument `run`, puis envoie les signaux via un descripteur
   Linux `pidfd`. Le descripteur évite qu’un PID réutilisé pendant l’attente dirige
   le signal vers un autre processus. Les PID nuls, négatifs ou invalides sont refusés.
3. **Suppression des restrictions Flatpak personnelles — moyenne.**
   `flatpak revert` utilisait un `--reset` global. Il révoque désormais uniquement
   les quatre accès de fichiers accordés par cette commande de thème et retire
   `GTK_THEME`, en préservant les autres dérogations. Les échecs de la commande
   Flatpak sont propagés au lieu d’afficher un succès. Ce retrait ne restaure pas
   d’éventuelles anciennes valeurs personnelles sur ces quatre mêmes accès.
4. **Contrôle de syntaxe incomplet et durcissement du service.**
   `bash -n fichier1 fichier2` n’analyse que `fichier1`. Chaque script est désormais
   vérifié séparément dans la suite, le hook, le Makefile et la CI. La compilation
   Python de la suite inclut aussi `lib/`. Le service généré pour le daemon reçoit
   notamment `NoNewPrivileges`, les protections système déjà utilisées par les
   autres services et un `UMask=0077`.

Validation de cette passe : **22 tests de sécurité réussis et 42 suites réussies
 en 28 secondes**, dans une configuration et une session D-Bus temporaires.
Les tests vérifient aussi l’arrêt normal du vrai daemon lancé dans la fixture,
la conservation du premier CSS sauvegardé et la détection d’une erreur de syntaxe
dans un deuxième script. ShellCheck passe sur les commandes modifiées ; pour les
lanceurs de tests, seul SC2317 est exclu car leurs fonctions sont appelées indirectement.
`make` n’est pas présent sur cette machine : la recette n’a pas été lancée via Make,
mais les contrôles Bash et Python ont été exécutés directement et par la suite.

Aucune permission Flatpak réelle, unité installée ou configuration GDM de la machine
n’a été changée. Le contrôle du daemon nécessite Python et Linux avec prise en charge
de `pidfd` ; il refuse d’envoyer les signaux si cette prise en charge manque.

Référence : la [documentation officielle de Flatpak override](https://docs.flatpak.org/en/latest/flatpak-command-reference.html#flatpak-override)
décrit les effets de `--reset`, `--nofilesystem` et `--unset-env`.

## Troisième passe — chemins privilégiés et téléchargements

- **Restauration GDM : source de copie contrôlable par une configuration importée.**
  `uninstall_gdm` lisait `gdm-backup-path` et plaçait ce fichier en tête des sources
  essayées avec `sudo cp` vers la ressource GDM. Cette entrée utilisateur n’est plus
  consultée : seules les sauvegardes système prévues sont utilisées. Le mémo est
  également exclu des nouveaux exports et refusé dans les imports. Une copie échouée
  n’est plus déclarée comme une restauration réussie. Le test remplace `sudo` par une
  fonction d’enregistrement ; aucune ressource système réelle n’est écrite.
- **Téléchargements : durcissement du transport.** Les appels curl de téléchargement
  imposent HTTPS pour l’URL et les redirections, limitent celles-ci à cinq et définissent
  des délais par requête ainsi qu’une durée de relance. Le téléchargement d’extension
  échoue aussi explicitement sur une erreur HTTP. Un serveur trop lent peut désormais
  faire échouer l’installation au lieu de la laisser attendre indéfiniment.
- **Extensions GNOME : validation des métadonnées.** L’URL renvoyée par EGO doit être
  un chemin relatif attendu `/download-extension/`, sans autorité distante, fragment,
  antislash ou caractère de contrôle. Le UUID de l’archive doit correspondre à
  l’extension demandée, en plus de la version GNOME. Les métadonnées malformées sont
  refusées. L’API officielle a été interrogée en lecture seule pour confirmer le
  format de chemin actuellement renvoyé. Le UUID est un contrôle de cohérence,
  pas une signature ni une preuve d’innocuité du code de l’extension.
- **CI : références immuables.** Les actions sont fixées aux SHA complets correspondant
  aux références `v4` et `v5` vérifiées sur leurs dépôts officiels pendant cette revue :
  [checkout, 11d5960a326750d5838078e36cf38b85af677262](https://github.com/actions/checkout/commit/11d5960a326750d5838078e36cf38b85af677262)
  et [setup-python, a26af69be951a213d495a4c3e4e4022e16d87065](https://github.com/actions/setup-python/commit/a26af69be951a213d495a4c3e4e4022e16d87065).
  Ces références devront être mises à jour explicitement pour bénéficier des futures corrections.

Validation : **28 tests de sécurité réussis ; 42 suites réussies en 30 secondes**
avec configuration et bus D-Bus temporaires. Les tests supplémentaires couvrent
les mauvaises URL, un UUID inattendu, des métadonnées invalides, une URL HTTP refusée
par curl, l’exclusion du mémo GDM des exports et son absence des copies privilégiées.
ShellCheck, compilation Python et `git diff --check` passent. La CI distante n’a pas
été déclenchée pendant cette revue.

Le chantier GDM restant est plus large : les scripts tiers WhiteSur du cache utilisateur
sont toujours exécutés avec `sudo` lors de certaines installations/désinstallations.
Supprimer cette exécution demanderait de déplacer la compilation hors privilèges et
réduire la phase privilégiée aux opérations système nécessaires, puis de valider le
résultat dans une session GDM dédiée. Les changements de cette passe ne prétendent
pas résoudre ce risque architectural.

Références : [options de protocole et délais de curl](https://curl.se/docs/manpage.html),
[recommandations officielles de GitHub pour sécuriser les actions](https://docs.github.com/en/actions/reference/security/secure-use).

## Quatrième passe — suppression des scripts tiers privilégiés pour GDM

Le risque décrit à la fin de la troisième passe est maintenant traité pour le
chemin GDM : **l’installation et la désinstallation n’exécutent plus `tweaks.sh`
ou les bibliothèques shell WhiteSur avec `sudo`.**

Le nouveau `tools/build-gdm-resource.py` lit seulement neuf fichiers statiques
attendus dans le checkout WhiteSur épinglé. Il refuse les assets absents ou liés,
construit son propre manifeste XML sans préprocesseur, conserve les autres ressources
du thème de la distribution et compile dans un dossier temporaire privé avec
`glib-compile-resources`, sous le compte utilisateur. Il vérifie ensuite la liste
des ressources produites. Les CSS des variantes sombre, claire et contraste élevé
référencent le fond dynamique Aura Glass. Les scripts et le manifeste XML tiers
ne sont ni exécutés ni utilisés pour piloter la compilation.

La phase privilégiée installe les octets compilés, lus sur l’entrée standard ouverte
par le shell utilisateur. La désinstallation restaure directement une sauvegarde
système. Les sauvegardes existantes sont validées, les liens refusés, et la première
copie `.aura-backup` est conservée lors des réinstallations. Une création/validation
de sauvegarde échouée bloque le remplacement de la ressource. Cette protection ne
reconstruit pas une sauvegarde qui aurait déjà été écrasée avec l’ancien code.

Vérifications effectuées :

- Compilation réelle, sans privilèges, des assets du commit WhiteSur `1912dee2e48d`
  avec une copie logique des ressources du GDM Ubuntu présent sur cette machine.
  Le résultat contient 18 entrées ; les ressources spécifiques à Ubuntu sont
  conservées. Aucun fichier système source n’a été modifié.
- Copie réelle de la ressource compilée via `/dev/stdin` vers un fichier temporaire,
  sans `sudo`, pour vérifier ce mécanisme de transmission.
- **7 nouveaux tests GDM** : compilation, conservation des assets de distribution,
  refus des liens et assets manquants, scripts tiers ignorés, deux installations
  suivies d’une restauration, échec ou invalidité de sauvegarde.
- **43 suites réussies en 30 secondes**, dont les 28 tests de sécurité précédents
  et les 7 nouveaux tests GDM, soit **35 tests de sécurité**. ShellCheck, compilation
  Python et contrôle du diff passent. Les opérations `sudo` sont simulées dans les tests.

Le compilateur manquant a été téléchargé depuis les dépôts configurés et extrait
uniquement sous `/tmp` pour ces vérifications ; aucun paquet n’a été installé sur
la machine. La CI installe désormais également le paquet fournissant ce compilateur.

Limite : le fichier compilé et les chemins d’installation/restauration sont testés,
mais le rendu et la connexion dans une véritable session GDM ne le sont pas. Aucun
redémarrage de GDM ni déploiement du thème système n’a été effectué. Les autres
opérations privilégiées du projet, notamment l’installation de composants natifs,
ne sont pas couvertes par cette suppression spécifique aux scripts GDM.

La sélection des fichiers statiques reprend les assets du thème GDM moderne présents
au [commit WhiteSur utilisé par le projet](https://github.com/vinceliuice/WhiteSur-gtk-theme/tree/1912dee2e48d/other/gdm),
sans reprendre son mécanisme d’installation privilégié.

## Cinquième passe — préservation des réglages des éditeurs

L’application du thème VS Code, VSCodium et Cursor ignorait toute erreur de lecture
ou de parsing de `settings.json`, puis écrivait un objet contenant uniquement les
couleurs du thème. Un fichier avec commentaires ou virgule finale pouvait donc
perdre ses préférences personnelles, y compris de sécurité. Les commentaires et
virgules finales sont pourtant acceptés dans les fichiers de configuration de
[VS Code en mode JSONC](https://code.visualstudio.com/docs/languages/json).

Le correctif dans `bin/aura-glass-apps` :

- Refuse toute entrée que le parseur JSON strict ne peut pas préserver : JSONC,
  JSON incomplet, UTF-8 invalide, clés dupliquées, valeurs non finies, racine ou
  personnalisation des couleurs d'un type inattendu. La validation précède les
  écritures. Pour JSONC, le message indique de fusionner le résultat de
  `aura-glass apps snippet vscode` depuis l’éditeur ; le fichier reste intact.
- Refuse les liens symboliques, liens physiques multiples et fichiers spéciaux
  pour les réglages et leur sauvegarde. La lecture est limitée à 8 Mio.
- Crée la première sauvegarde sans écraser une entrée existante, avec publication
  d’un fichier complet. Une sauvegarde impossible bloque la modification.
- Écrit le résultat dans un fichier privé, puis le remplace par renommage atomique.
  Une erreur d’écriture laisse le fichier de réglages précédent intact.

Huit tests supplémentaires couvrent la conservation des préférences et de la
première sauvegarde après deux applications, les entrées non prises en charge,
les liens existants ou pendants, l’encodage invalide, l’échec de sauvegarde, la
création initiale et un échec de remplacement simulé avec nettoyage du temporaire.
Les tests de refus des formats et des liens échouaient avant la correction.

Validation finale : **43 suites réussies en 31 secondes**, dont **36 tests de
sécurité généraux et 7 tests GDM**. ShellCheck et les contrôles de syntaxe passent.
L’exécution utilise une configuration temporaire et un bus D-Bus distinct ; aucun
réglage personnel d’éditeur ni composant système n’a été déployé ou modifié.

Périmètre : la correction porte sur `apps apply vscode`. Elle ne garantit pas la
coordination avec un éditeur qui enregistrerait simultanément les mêmes réglages,
ni une transaction entre plusieurs installations d’éditeurs. Elle ne récupère
pas les préférences perdues auparavant. Les chemins ancêtres de la configuration
utilisateur restent considérés comme fiables. L’installation native par
`sudo meson install` et les écritures dans les profils Firefox méritent encore
une passe dédiée ; elles ne sont pas corrigées par cette modification.
