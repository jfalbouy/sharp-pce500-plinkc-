# APLINKS 1.07 — mode 256 Ko

`APLINKS107.C` → `aplinks32_107.exe` (`build_107.ps1`). C'est **une source à part**, dérivée
d'`APLINKS.C` 1.06. **La 1.06 reste le serveur de référence**, validé sur matériel, et n'est pas
modifiée : `APLINKS.C`, `APLINKS_C17.C`, leurs binaires, `build*.ps1`, `Makefile` et
`README.md` sont identiques à l'octet à ce qu'ils étaient.

La 1.07 sert le **pilote PLINKC modernisé** (`../plinkc/`), qui ajoute `INIT "L:2"`. Tout le
reste est le comportement de la 1.06 : options, dossier-disque, historique, uuencode/uudecode.

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
