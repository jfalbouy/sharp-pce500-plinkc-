# PLINKC — pilote `L:` modernisé (mise à jour 2026)

Dérivé de **PLINKC 1.62** (© 1996-99 D. Mizobata, d'après PLINK 1.04 © 1990-94 N. Kon), mis à
jour en 2026 par Jean-François Albouy. C'est le pilote **côté pocket** du lecteur `L:` ; son
serveur côté PC est `../aplinks/`.

**Compatibilité :** `aplinks32` 1.06 et les serveurs d'époque fonctionnent comme avant en 128K
et 512K. Le protocole n'a qu'un ajout : la commande **`'Q'`**, par laquelle le pilote demande
au serveur son mode réel après chaque `INIT`. Seul **APLINKS 1.07**
(`../aplinks/README-1.07.md`) y répond, et c'est lui qui sert le mode **256K** (`INIT "L:2"`). Le pilote installé ne
diffère de la 1.62 que par `INIT "L:?"`, `INIT "L:2"` et `mpb256` ; l'installateur, lui, est
réécrit en partie.

| Fichier | Rôle |
| --- | --- |
| `plinkc.asm` | la source modernisée (dialecte A62, assemblée par **xasm2026-4**) |
| `pce500.inc` | les constantes système, copie de `xasm2026-4/Exemples/INCLUDE/pce500.inc` (fichier **généré**, à ne pas éditer) |
| `PLINKC.OBJ`, `plinkc.lst` | l'objet (2957 o) et son listing |
| `plinkc.uu` | l'auto-décodeur BASIC de l'objet, pour le transfert vers le pocket |
| `verifier.py` | le contrôle de la table de relocation et de la référence (voir plus bas) |
| `reference/` | la **version d'origine** : `plinkc.a62.asm`, qui redonne à l'octet `PLINKC.OBJ` (1554 o), l'objet de l'archive `original/PLINKC-1.62-1999/` |

## Ce qui change par rapport à la 1.62

1. **Les constantes système viennent de `pce500.inc`**, sous les noms du désassembleur
   `SC62015Disassembler` (`iroot` → `d_link`, `s1top` → `s1_top`, `sio_stat_reg` → `usr`…). La
   correspondance est donnée en tête de `plinkc.asm`. Les numéros de fonction en dur ont aussi
   leur nom (`iocs_find_drive`, `d6_search_phys`, `d6_condense`, `iocs_fmt_drive`,
   `fcs_write_block`…). Cinq constantes inutilisées sont retirées (`iocs_fook`, `bpmax`,
   `keyvec`, `cdrv`, `rev`). *Vérifié : à ce stade, l'objet était encore identique à l'octet à
   `PLINKC.OBJ`.*
2. **Désinstallation par `CALL &BF000 "-U"`** (ou `"-u"`) :
   - le bloc `PLINK.SYS` est retrouvé par la **chaîne des blocs** de `S1:` (pas par `d_link`,
     qu'un amorçage peut perdre). Il est reconnu à son **en-tête** : le nom de device `L:`
     en bloc+2Ah, et non à sa taille, qui change à chaque version. Le déliage ne touche qu'à cet
     en-tête, et aucune version ne tient de vecteur au repos. Une version précédente, ou un
     PLINKC 1.62 **d'origine**, se désinstalle donc de la même façon ;
   - **refus si un autre pilote est au-dessus** de `PLINK.SYS`. Le `KILL` de `PLINK.SYS` ferait
     descendre les blocs suivants sans relocation : sans dommage pour `TEXT.BAS`/`DATA.BAS`
     (la ROM les recale), mais fatal pour un pilote (mesuré le 2026-09-25 avec `BASEXT.SYS` :
     la machine tombe). Le message nomme le pilote à désinstaller d'abord ;
   - l'en-tête est délié de `d_link` s'il y est encore. PLINKC ne détourne aucun vecteur au
     repos (il ne prend la SIO que le temps d'un appel), donc le déliage suffit ;
   - la libération de la mémoire se fait à la main : `SET` et `KILL` sont des commandes de mode
     direct, qu'un programme ne peut pas exécuter. Le pilote les affiche.
3. **Retour à BASIC** sur le modèle d'UUENCODE, validé avec PLINK2, REGISTER3 et BASEXT-DRV :
   pointeur de ligne repris puis rendu sur la pile U, quatre terminateurs (`0`, `CR`, `1Ah`,
   `0FFh`), et **carry clair** sur tous les chemins (carry armé → `Syntax error`).
4. **`INIT "L:?"`** affiche l'état du pilote, par exemple `L: 512K, device 10, block &80018` :
   - le mode choisi par le dernier `INIT "L:1"`, `"L:2"` ou `"L:5"` (128K après l'installation) ;
   - le numéro de device ;
   - l'adresse du bloc installé.

   Rien n'est envoyé au serveur et les tampons ne sont pas touchés. Dans la 1.62, une lettre
   inconnue tombait dans `buffer_clr` (`INIT "L:?"` y vidait donc le tampon) ; ici, `?` est
   traité avant.
5. **« Déjà installé » détaillé.** La 1.62 refusait par un seul `Already exists.`, sans dire
   pourquoi. L'installateur cherche maintenant le bloc, puis le lecteur `L:` :

   | Situation | Affichage |
   | --- | --- |
   | notre version, en place | l'état du pilote (il est interrogé par `INIT "L:?"`), puis `Already exists.` |
   | un `PLINK.SYS` d'une autre taille (1.62 d'origine…) | `Already exists (other version).` |
   | le bloc est là mais `L:` n'est plus chaîné | `PLINK.SYS in S1: but not linked.` + `SET`/`KILL` |
   | pas de bloc, mais un `L:` existe | `Error: L: used by another driver.` |

   La fonction 41h reçoit maintenant `(ch)` = 0 (slot `S1:`) explicitement ; la 1.62 le
   laissait tel que l'appel précédent l'avait laissé.
6. **Mode 256K, `INIT "L:2"`, et commande `'Q'`.** Le nouveau bloc de paramètres `mpb256` suit
   la règle des deux autres : FAT de 24 secteurs, répertoire de 24 à 55, données dès 56, 1992
   secteurs.

   Après chaque `INIT "L:1"`, `"L:2"` ou `"L:5"`, le pilote envoie `'S'` et le mode, comme la
   1.62, puis **`'Q'`**. Il attend ensuite environ 1 s que le serveur réponde par le mode qu'il
   utilise réellement, et il adopte ce mode.
   - S'il diffère du mode demandé, le pilote l'affiche : `Server mode: 512K`.
   - Sans réponse (serveur 1.06 ou DOS 1.03, qui ignorent `'Q'`), le pilote garde le mode
     demandé pour 128K et 512K, comme la 1.62. Pour 256K, il passe en 128K et l'affiche :
     `No 256K reply from server: 128K.`
   - Avec un serveur ancien, un `INIT "L:1"` ou `"L:5"` prend donc environ 1 s de plus.

   Détail et géométries : `../aplinks/README-1.07.md`.
7. **`INIT "L:H"`** affiche l'aide, ici sur quatre lignes :
   ```
   PLINKC 1.62-2026.1, 3008 bytes
   L: 256K, device 10, block &80018
   INIT "L:x"  1/2/5 = 128K/256K/512K
   D disc, I clear, ? state, H help [key]
   ```
   **Puis le pilote attend une touche** (ajout du 2026-10-06). L'écran n'a que 4 lignes : la
   dernière est donc écrite **sans** retour à la ligne, sinon l'écran défilerait avant la pause
   et la première ligne serait déjà perdue. Le tampon clavier est vidé d'abord, puis la fonction
   clavier IOCS `43h` attend en basse consommation ; le retour à la ligne vient après la
   touche.
   On y lit la version, la taille du bloc en mémoire, la ligne d'état de `INIT "L:?"` et les
   commandes. La taille est écrite en décimal **à l'assemblage**, puisque `blen` est une
   constante. Les parenthèses y sont indispensables : `%` lie moins fort que `+` dans ce
   langage, comme dans le moteur C.
8. **Option inconnue signalée.** `INIT "L:X"`, avec une lettre qui n'est ni `1`/`2`/`5`, ni
   `D`/`I`/`?`/`H`, affiche `Unknown INIT option. Help: INIT "L:H"` et ne touche à rien. La
   1.62 vidait le tampon sans rien dire. L'option **vide** (`INIT "L:"`, ainsi que l'appel de
   l'installateur avec `"L:",0`) garde le comportement de la 1.62. Les minuscules sont
   acceptées (`INIT "l:h"`).
9. La bannière ajoute une ligne `Update 2026.1 by J-F.Albouy`. Les deux lignes de crédit
   d'origine sont intactes. La révision `2026.1` est définie une seule fois (macro `drvrev`),
   pour la bannière et pour `INIT "L:H"`.

Le modèle d'installation **reste celui de PLINKC** : insertion avant le premier bloc qui n'est
pas un pilote, décalage des blocs suivants, puis recalage de `TEXT.BAS`/`DATA.BAS` (`linkbas`).
L'ajout en fin de chaîne, essayé dans PLINK2, est faux : il a été démenti par la mesure le
2026-09-16.

## Utilisation sur le pocket

Réserver d'abord la zone langage machine en `0BF000h`, puis charger et lancer :

```basic
LOADM "PLINKC.OBJ"
CALL &BF000           : REM installe   -> Installed.
CALL &BF000 "-U"      : REM desinstalle -> Uninstalled. + les deux commandes :
SET  "S1:PLINK.SYS"," "
KILL "S1:PLINK.SYS"
```

Messages de la désinstallation :

| Message | Cause |
| --- | --- |
| `Uninstalled. To free memory :` + `SET`/`KILL` | délié (ou déjà absent de `d_link`) |
| `PLINK.SYS not in S1:.` | aucun bloc `PLINK   SYS` |
| `Error: PLINK.SYS without L: header.` | un bloc de ce nom, mais sans l'en-tête `L:` attendu |
| `Error: driver above PLINK.SYS :` + nom + `Uninstall it first.` | un pilote est installé au-dessus |

⚠️ Mettre `CALL &BF000 "-U"` **seul sur sa ligne** (ou en dernière instruction). Comme chez
UUENCODE, la lecture de l'argument court jusqu'à la fin de la ligne : un `:` suivi d'autres
instructions serait sauté.

## Assembler et vérifier

```powershell
xasm2026-4 plinkc.asm -O PLINKC.OBJ -L plinkc.lst -S -K -B plinkc.uu
python verifier.py          # ou : python verifier.py <chemin de xasm2026-4.exe>
```

Seul **xasm2026-4** ([XASM2026_CSharp](https://github.com/jfalbouy/XASM2026_CSharp), à mettre
dans le PATH ou à désigner par la variable `XASM2026_4`) assemble cette source : il reproduit le dialecte A62 (préfixe `rel` et
table de relocation générée, `#defmacro`, `suborg`/`byte`/`pntr`, blocs `{ }`). `-K` raccourcit
le listing aux constantes de `pce500.inc` effectivement utilisées.

`verifier.py` contrôle que **la table de relocation couvre toutes les adresses du corps**. Il
assemble `plinkc.asm` à deux origines (`0BF000h` et `0BE000h`), reloge chaque corps par **sa
propre** table, exactement comme le fait l'installateur, vers quatre destinations, et exige des
résultats identiques à l'octet (1629 o, 109 sites). Une adresse oubliée, c'est-à-dire un `rel`
manquant, garderait la trace de son origine d'assemblage. Témoin négatif : un `rel` retiré le
fait échouer. Le script contrôle aussi que la référence redonne l'objet d'origine.

Trois `assert` en fin de source verrouillent les invariants dont dépend l'installateur :
- `entry` reste à l'`org`, parce que la boucle de relocation part de `btop-entry` ;
- l'en-tête IOCS est en `bloc+22h` ;
- la table `mb` tient sous 256 octets.

Un quatrième vérifie que `blen` diffère de `blen_162` (2336), puisque la taille sert à
distinguer les deux versions.

## État

- Vérifié à l'assemblage : relocation complète (`verifier.py`) et désassemblage conforme
  (variables du cadre en `(BP+n)`, `(cl)` en absolu par `pre $30`/`pre $32`, cadre rendu, `rc`).
- ✅ **`INIT "L:?"` : « fonctionne parfaitement » sur le Sharp (J.-F. Albouy, 2026-10-05)** ;
  l'affichage par le FCS depuis l'intérieur du pilote ne pose donc pas de problème.
- ✅ **Mode 256K sur le Sharp avec APLINKS 1.07 (J.-F. Albouy, 2026-10-06) : « tout a fonctionné ».**
  Session `aplinks32_107.exe -p com3 -b 19200 -2 -d Disk_7` : poignée de main `[256K]`, `SAVE` de
  `INIT.BAS` (975 o, 27 écritures) écrit sur le PC à la déconnexion, puis relecture (18 lectures),
  trois connexions successives.
- ⚠️ **Vu en essai (2026-10-06) : un serveur au disque préchargé en 512K garde son mode, même si le
  pocket demande 128K.** Le pocket lit alors la FAT comme un répertoire et demande des secteurs
  absurdes : APLINKS 1.06 **plante** (reproduit au banc par une lecture du secteur 65000).
  Depuis, la 1.07 refuse un secteur hors du disque, avec un avertissement, sans planter. La
  désynchronisation elle-même reste possible : lancer le serveur dans le mode voulu.
- ✅ **Commande `'Q'` (J.-F. Albouy, 2026-10-06)** : avec la 1.07 et un disque en 256K,
  `INIT "L:5"` et `INIT "L:1"` affichent bien `Server mode: 256K`. Le serveur journalise sa
  mise en garde et garde 256K, et la session se termine proprement.
- ⏳ **À éprouver (2026-10-06, après l'ajout de `INIT "L:H"`) :**
  - (fait) `INIT "L:H"` avec sa pause, l'option inconnue, les minuscules, `INIT "L:"` et le
    `-U` de la version précédente : **« tout fonctionne parfaitement »** sur le Sharp
    (J.-F. Albouy, 2026-10-06) ;
  - **avec la 1.06**, `INIT "L:2"` : `No 256K reply from server: 128K.`, puis tout en 128K ;
    et `INIT "L:5"` sur disque vide : 512K, après environ 1 s d'attente ;
  - les quatre cas de « déjà installé ».
- ✅ **Émulateur (J.-F. Albouy, 2026-10-05)** : installation, désinstallation, `Already exists.` si
  déjà installé, réinstallation après déliage, réinstallation après `SET`/`KILL`.
- ✅ **PC-E500S réel (J.-F. Albouy, 2026-10-05) : « tout fonctionne parfaitement ».** Le scénario
  proposé pour cet essai partait de la machine du relevé du 2026-09-18, avec `PLINK.SYS` 1.62
  d'origine et `BASEXT.SYS` au-dessus. Il enchaînait :
  - le refus « pilote au-dessus » ;
  - la désinstallation de BASEXT-DRV ;
  - la désinstallation de la **1.62 d'origine** par le nouvel installateur ;
  - l'installation de la nouvelle version.
- Ordre à respecter pour reproduire le refus : installer **PLINKC d'abord, puis BASEXT-DRV**.
  L'installateur de PLINKC saute les pilotes déjà en place, donc installé en second, il se place
  derrière BASEXT et rien n'est au-dessus de lui. Recharger ensuite `PLINKC.OBJ`, car
  l'installateur de BASEXT a écrasé `0BF000h`, avant `CALL &BF000 "-U"`.
