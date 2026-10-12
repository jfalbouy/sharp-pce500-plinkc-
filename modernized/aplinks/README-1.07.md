# APLINKS 1.07 — mode 256 Ko et mode capture `COM:`

`APLINKS107.C` → `aplinks32_107.exe` (`build_107.ps1`). C'est **une source à part**, dérivée
d'`APLINKS.C` 1.06. **La 1.06 reste le serveur de référence**, validé sur matériel, et n'est pas
modifiée : `APLINKS.C`, `APLINKS_C17.C`, leurs binaires, `build*.ps1`, `Makefile` et
`README.md` sont identiques à l'octet à ce qu'ils étaient.

La 1.07 sert le **pilote PLINKC modernisé** (`../plinkc/`), qui ajoute `INIT "L:2"`. Elle
ajoute aussi le **mode capture `COM:`** (`--capture`) et l'écriture des fichiers sans nom (voir
« Deux modes de fonctionnement »). Tout le reste est le comportement de la 1.06 : options,
dossier-disque, historique, uuencode/uudecode.

## Les trois géométries

Les trois modes suivent la même règle. On trouve d'abord la FAT, en 12 bits, puis 32 secteurs de
répertoire (128 fichiers), puis les données, pour exactement *capacité/128* secteurs.

| Mode | Option | `INIT` sur le pocket | FAT | Répertoire | Données dès | Secteurs de données | Capacité |
|---|---|---|---|---|---|---|---|
| 128K | `-1` (défaut) | `INIT "L:1"` | 12 | 12–43 | 44 | 980 | 122 Ko |
| **256K** | **`-2`** | **`INIT "L:2"`** | **24** | **24–55** | **56** | **1992** | **249 Ko** |
| 512K | `-5` | `INIT "L:5"` | 48 | 48–79 | 80 | 4016 | 502 Ko |

## Le seul ajout au protocole : la commande `'Q'`

À l'`INIT`, le pilote annonce sa taille par `'S'` suivi de `'1'`, `'2'` ou `'5'`. Comme en 1.06,
**`'S'` ne reçoit aucune réponse** : un pilote 1.62 n'en attend pas, et un octet en trop le
désynchroniserait. La 1.07 sert donc aussi le PLINKC d'origine.

Le pilote modernisé envoie ensuite **`'Q'`**, et la 1.07 répond par la lettre du mode qu'elle
utilise **réellement** (`'1'`, `'2'` ou `'5'`). Le pilote adopte ce mode, et l'affiche
(`Server mode: 512K`) quand il diffère du mode demandé.
- C'est ce qui manquait le 2026-10-06. Un serveur au disque préchargé en 512K a gardé son
  mode, et le pocket, resté en 128K, a lu la FAT comme un répertoire. Les secteurs absurdes
  qu'il a ensuite demandés ont fait planter la 1.06.

Face à un serveur **ancien** (1.06, DOS 1.03), `'Q'` est ignoré : la 1.06 l'écarte dans son cas
`default`, et la 1.03 n'a pas de `default`. Le pilote attend alors environ 1 s, puis :
- pour `"L:1"` et `"L:5"`, il garde le mode demandé, comme la 1.62 ;
- pour `"L:2"`, il passe en 128K et l'affiche (`No 256K reply from server: 128K.`). Ces serveurs
  comprennent tout ce qui n'est pas `'5'` comme 128K, et se mettent eux-mêmes en 128K sur un
  disque vide.
- ⚠️ Avec un serveur ancien au disque préchargé dans un autre mode, la désynchronisation reste
  possible, exactement comme avec la 1.62.
- La réaction d'APLINKS for Win32 (binaire de 1997) à `'Q'` n'est pas connue.

## Deux modes de fonctionnement : `L:` ou `COM:` (2026-10-12)

Le pocket peut envoyer des données au PC par le câble série de deux façons. APLINKS doit être
lancé dans le mode qui correspond. **Un seul mode par session.**

| | Mode disque `L:` (par défaut) | Mode capture `COM:` (`--capture`) |
|---|---|---|
| Côté pocket | `SAVE`, `LOAD`, `COPY`, `OPEN "L:NOM.EXT" FOR OUTPUT`/`PRINT #` | `OPEN "COM:" FOR OUTPUT`/`PRINT #`/`CLOSE` |
| Ce qui passe sur le câble | des **secteurs** de 128 octets, par le protocole PLINK (`R`, `W`, `S`, `Q`, `D`) | **le texte lui-même**, octet par octet |
| Pilote PLINKC | nécessaire | non utilisé |
| Lancement | `aplinks32_107 -p com3 -b 19200 -5 -v -l disque.log` | `aplinks32_107 -p com3 -b 19200 --capture FICHIER.TXT -v -l capture.log` |
| Fichier écrit sur le PC | à l'**`INIT "L:D"`** (ou Ctrl-D), sous le nom donné sur le pocket | au **`1Ah`** final du `CLOSE`, sous le nom donné à `--capture` |
| Sens | dans les deux sens (`LOAD` et `SAVE`) | du pocket vers le PC seulement |

### Mode disque `L:`

APLINKS sert un disque virtuel. Le pocket y lit et y écrit des secteurs, comme sur une disquette.
Pour APLINKS, un fichier écrit par `PRINT #` est donc identique à un `SAVE`.

```basic
INIT "L:5"                                   : REM 512K, comme -5
OPEN "L:LBASIC.TXT" FOR OUTPUT AS #1 : PRINT #1,"..." : CLOSE #1
INIT "L:D"                                   : REM ecrit les fichiers sur le PC
```

- **Faire `INIT "L:D"` avant tout autre usage du câble.** Le pilote garde le secteur de
  répertoire en cache. Il ne l'écrit pas au `CLOSE`, mais seulement à l'`INIT "L:D"`. Jusque-là,
  le fichier n'est pas complet côté serveur. Un arrêt d'APLINKS ou une sortie sur `COM:` avant
  ce moment le perd.
- **Donner un nom complet : `L:NOM.EXT`.** `OPEN "L:" FOR OUTPUT`, avec l'appareil seul comme on
  l'écrit pour `COM:`, crée un fichier **sans nom** (onze espaces dans le répertoire).
  - La 1.06 ne savait pas l'écrire sur le PC et le sautait sans rien dire.
  - La 1.07 l'enregistre sous `NONAME.TXT`, puis `NONAME2.TXT`, `NONAME3.TXT`, etc. S'il a une
    extension, elle est gardée.
  - Un message s'affiche et l'événement entre dans l'historique, ainsi que tout échec de création
    (`Can't open`).
- Avec `-v`, le vidage liste chaque entrée du répertoire : nom, attribut, premier cluster,
  taille et décision. Par exemple :
  `[D] dir 'LBASIC  .TXT' attr 20 start 2 size 5309 -> flush`.

### Mode capture `COM:`

APLINKS ne sert plus `L:`. Il enregistre les octets reçus et ne renvoie rien au pocket.

```basic
OPEN "19200,N,8,1,A,L,&1A,N,N":CLOSE         : REM meme vitesse que -b
OPEN "COM:" FOR OUTPUT AS #1 : PRINT #1,"..." : CLOSE #1
```

- La vitesse de l'`OPEN` du pocket doit être celle de `-b`.
- Les octets sont écrits tels quels, en CR LF grâce au champ `L` de l'`OPEN`.
- Le `1Ah` envoyé par `CLOSE` (code de fin `&1A`) ferme le fichier. Il n'est pas écrit.
- Chaque transmission suivante va dans un nouveau fichier : `FICHIER-2.TXT`, `FICHIER-3.TXT`,
  etc. Un fichier existant est écrasé.
- **Ctrl-D** ferme le fichier en cours, même sans `1Ah`, puis arrête APLINKS. **Ctrl-C** garde
  aussi ce qui a été reçu. **`h`** affiche l'historique.
- Avec `-v`, le texte s'affiche pendant la réception : CR omis, autres octets de contrôle en
  `<XX>`. `-l` le recopie dans le journal.

### Pourquoi ne pas mélanger les deux

En mode disque, le texte envoyé à `COM:` arrive sur la ligne qu'APLINKS lit comme des commandes
PLINK. Ses lettres `D`, `R`, `W` ou `S` sont indiscernables des vraies commandes.

L'essai `export6.log` a fait une sortie `L:`, puis une sortie `COM:`, puis `INIT "L:D"`, dans une
seule session. Résultat : **aucun fichier enregistré**.
- Le `S` puis le `I` de `LBASIC` ont fait passer le disque en 128K.
- Le premier `D`, dans `MOTS-CLES`, a vidé ce disque, en cherchant le répertoire au mauvais
  endroit, puis l'a remis à zéro.
- Le fichier écrit sur `L:` était perdu avant que l'`INIT "L:D"` n'envoie son entrée de
  répertoire.

**Protection depuis la 1.07 :** un `'S'` qui n'est pas suivi de `'1'`, `'2'` ou `'5'` est ignoré et
noté dans l'historique. La 1.06 le prenait pour 128K. Aucun pilote n'envoie autre chose : la
1.62 envoie `'1'` ou `'5'`, et le pilote 2026 y ajoute `'2'`. Les `D`, `R` et `W`, eux, ne
peuvent pas être filtrés.

### Vérifié sur le PC-E500 (2026-10-12, 512K, 19200 bps)

Programme `LBASIC.BAS` (`C:\Claude\ROUTINES\LBASIC`), rapport de 171 lignes :

| Sortie | Mode APLINKS | Résultat |
|---|---|---|
| `COM:` | `--capture LBASIC.TXT` | `LBASIC.TXT`, 5 308 octets |
| `L:` seul (ancien LBASIC) | disque, puis `INIT "L:D"` | `NONAME.TXT`, 5 309 octets (`export4.log`) |
| `L:LBASIC.TXT` | disque, puis `INIT "L:D"` | `LBASIC.TXT`, 5 309 octets (`export5.log`) |
| `L:` seul, LBASIC complété en `L:LBASIC.TXT` | disque, puis `INIT "L:D"` | `LBASIC.TXT`, 5 309 octets (`export8.log`) |
| `L:` puis `COM:` dans une seule session | disque | rien (`export6.log`, avant la protection sur `'S'`) |

Les quatre fichiers ont le même contenu. L'octet de plus en mode `L:` est le `1Ah` final, écrit
par le pocket comme pour tout fichier texte. La protection sur `'S'` n'a pas encore été essayée
sur la machine.

## Débit mesuré (2026-10-07) : transférer les programmes **tokenisés**

Mesures sur PC-E500S à 19200 bauds, avec le journal horodaté de la 1.07 (`-v` : `cycle`
depuis le `R` précédent, `idle` = silence du pocket après la réponse, `io` = transfert de la
commande), sur le même programme de 20 Ko :

| Opération | Par secteur | Total | Ce qui limite |
|---|---|---|---|
| `LOAD` du BASIC en texte ASCII (`,A`) | ~517 ms | ~75 s | la **tokenisation** sur le Sharp (~440 ms par secteur) |
| `LOAD` du même programme tokenisé | **71,7 ms** | ~10-12 s | le fil (68,8 ms) : 96 % du maximum |
| `SAVE` tokenisé | ~73 ms (4,4 ms d'attente) | ~10 s | le fil |

- **Le conseil d'usage :** échanger les programmes BASIC **tokenisés**, par `SAVE "L:…"` sans
  `,A`, ou en les convertissant en `.BSA` sur le PC (Sharp Basic Converter). C'est six fois
  plus rapide. Le texte ASCII se transfère aussi lentement par PLINK que par `COM:` : c'est la
  même limite, déjà mesurée par l'outil « Sharp transfert serial » (~305 octets/s).
- **Pistes écartées par la mesure :**
  - lire plusieurs secteurs en une requête : il reste 4 % à gagner ;
  - envoyer un secteur en un seul appel d'écriture plutôt qu'octet par octet : aucune
    différence mesurée, donc pas conservé.

  19200 bauds étant la vitesse maximale du Sharp, la liaison est au plafond.

## Vérifié sur PC (2026-10-05)

- Compilation sans avertissement : gcc 14.2 et clang, `-std=c99 -Wall -Wextra`.
- Capacité affichée au démarrage : 122 / 249 / 502 Ko pour `-1` / `-2` / `-5`.
- Un fichier de 200 Ko est refusé en `-1` (« not enough disk ») et chargé en `-2` (48 Ko
  libres ensuite).
- **Garde-fou ajouté le 2026-10-06** : un numéro de secteur hors du disque n'est plus lu ni
  écrit. Le serveur affiche `Warning: pocket read sector N, outside the ... disk` et l'inscrit
  dans l'historique.
  - Pourquoi : la 1.06 **plantait**, et le défaut est reproduit au banc par une lecture du
    secteur 65000 en 512K.
  - Quand ça arrive : en essai réel, quand le pocket et le serveur sont dans des modes
    différents. Exemple : un disque préchargé en 512K, que le serveur garde, face à un pocket
    en 128K. Le pocket lit alors la FAT comme un répertoire.
  - Ce garde-fou empêche le plantage, pas la désynchronisation.

- **Déconnexion durcie le 2026-10-06.** À la déconnexion, la 1.06 suivait la chaîne FAT de
  chaque fichier du pocket sans aucun contrôle. Au banc, elle plante sur un cluster hors du
  disque ou sur un secteur jamais écrit, et se fige sur une chaîne qui boucle. La 1.07 coupe le
  fichier là où la chaîne casse, affiche `Warning: FAT chain of "X" broken at cluster N (...)`
  et ajoute un diagnostic à `aplinks_diag.txt`, dans le dossier courant et non dans le dossier
  du disque. Ce diagnostic contient :
  - la géométrie ;
  - chaque entrée du répertoire, avec sa chaîne ;
  - la liste des secteurs de données présents.

  ⏳ La **cause** du cas réel reste à trouver. Le serveur, en 128K, avait `PLINKC.OBJ`
  préchargé. Sur le pocket : `INIT "L:2"`, puis `INIT "L:5"` (ramenés à 128K par `'Q'`), puis
  `SAVE "L:AA.BAS"`, puis `INIT "L:D"`. Le serveur a planté en écrivant `AA.BAS`.
  **Non reproduit** en trois rejeux de la même séquence, tracés avec `-v -l` : le fichier est
  allé chaque fois aux secteurs 76-79, avec la FAT au secteur 0 et le répertoire au secteur
  13, puis il a été écrit sur le PC. Hypothèse retenue : l'état d'avant (serveur relancé ou
  changé de disque sans nouvel `INIT` sur le pocket).

## Vérifié sur le Sharp (J.-F. Albouy, 2026-10-06) : « tout a fonctionné »

`aplinks32_107.exe -p com3 -b 19200 -2 -d "Disk_7"` :
- poignée de main `[256K]` ;
- `SAVE "L:INIT.BAS"`, soit 27 écritures, écrit sur le PC à la déconnexion (975 o) ;
- relecture (18 lectures) ;
- trois connexions successives, puis arrêt par Ctrl-D avec l'historique complet.
