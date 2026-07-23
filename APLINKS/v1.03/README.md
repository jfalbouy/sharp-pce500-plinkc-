# APLINKS — Serveur de fichiers pour Sharp PC-E500 (128 / 512 Ko)

**Version 1.04** — © 1992,93 N.Kon (programme d'origine) · © 2026 mise à jour Jean-François Albouy

`aplinks32` est le **programme côté PC** qui dialogue avec le pilote **PLINKC** installé
sur un pocket **Sharp PC-E500 (S)**. Une fois les deux lancés, le pocket voit un lecteur
de disque **`L:`** qui n'existe pas physiquement : chaque lecture/écriture de secteur est
transmise par la **liaison série** au PC, où les fichiers sont stockés dans un disque en
mémoire, puis écrits sur le disque du PC à la déconnexion.

C'est le portage moderne (C99, Windows / Linux / macOS) du serveur DOS d'origine
*APLINKS 1.03* de N.Kon (1992-93), avec en plus le **mode 512 Ko** et le réglage série
adapté au PC-E500. Le binaire DOS d'origine `APLINKS.EXE` (1993) est conservé tel quel.

---

## 1. Prérequis

- **Côté PC** : Windows (le binaire fourni `aplinks32.exe`), un **port série** — vrai
  RS-232 ou adaptateur USB-série — et le câble Sharp.
- **Côté pocket** : le pilote **PLINKC** installé et résident (voir `PLINKC.BAS` /
  `PLINKC.DOC` à la racine du projet).
- Réglages de la liaison : **9600 bps, 8 bits, sans parité, 1 bit de stop, sans contrôle
  de flux** (identiques des deux côtés).

---

## 2. Démarrage rapide

**Sur le PC** — lancer le serveur (ici port COM1, 9600 bps, mode 512 Ko, verbeux) :

```
.\aplinks32.exe -p com1 -b 9600 -5 -v
```

Le serveur affiche par exemple :

```
Plink server started on com1 (9600 bps), 512K mode, RTS=ON DTR=OFF.
```

**Sur le Sharp** — configurer le SIO (une seule fois), puis se connecter :

```
OPEN "9600,N,8,1,A,L,&1A,N,N":CLOSE
INIT "L:5"
```

À partir de là, `L:` s'utilise comme n'importe quel lecteur :

```
SAVE "L:TEST.BAS"        ' enregistre le programme courant sur L:
FILES "L:"               ' liste le contenu de L:
LOAD "L:TEST.BAS"        ' recharge un programme depuis L:
```

**Pour terminer** et écrire les fichiers sur le disque du PC :

```
INIT "L:D"
```

Le serveur affiche alors `Plink server halted. Syncing...`, écrit les fichiers créés,
puis **se ferme**. (Relancez-le pour une nouvelle session.)

---

## 3. Options du serveur (`aplinks32`)

```
aplinks32 [-p port] [-b baud] [-1|-5] [-v] [-d dossier] [-l fichier] [--rts on|off] [--dtr on|off] [fichiers...]
```

> ⚠️ Mettez les **options avant** les éventuels fichiers : tout ce qui suit le premier
> fichier est considéré comme un fichier.

| Option | Rôle | Défaut |
|--------|------|--------|
| `-p port` | Port série (`com1`, `com3`, …) | `COM1` |
| `-b baud` | Vitesse (9600 ou **19200** — max du PC-E500) | `9600` |
| `-1` | Disque **128 Ko** | (défaut) |
| `-5` | Disque **512 Ko** | — |
| `-d dossier` | **Dossier-disque** : charge tous ses fichiers et y réécrit (voir §5) | dossier courant |
| `-v` | Mode **verbeux** : journalise chaque commande + secteur | désactivé |
| `-l fichier` | Écrit aussi le journal verbeux dans `fichier` | — |
| `--rts on\|off` | Ligne RTS | `on` |
| `--dtr on\|off` | Ligne DTR | `off` |
| `fichiers...` | Fichiers précis à **précharger** (au lieu de tout le dossier) | — |
| `-h` | Aide | — |

> **Précharger des fichiers précis** : `aplinks32 -5 TEST.BAS JEU.BAS`. Le serveur affiche
> `Reading "TEST.BAS" ... done` et le pocket les verra avec `FILES "L:"`.

---

## 4. Commandes côté Sharp

| Commande | Effet |
|----------|-------|
| `OPEN "9600,N,8,1,A,L,&1A,N,N":CLOSE` | Configure le SIO (voir §6 pour les champs) |
| `INIT "L:5"` | Connexion en **512 Ko** |
| `INIT "L:1"` | Connexion en **128 Ko** |
| `INIT "L:D"` | **Déconnexion** : écrit les fichiers sur le PC et ferme le serveur |
| `SAVE "L:NOM.BAS"` | Enregistre en format interne (tokenisé, binaire) |
| `SAVE "L:NOM.BAS",A` | Enregistre en **texte ASCII** |
| `LOAD "L:NOM.BAS"` | Charge un programme depuis `L:` |
| `FILES "L:"` | Liste le contenu de `L:` |
| `COPY "L:A.BAS" TO "E:A.BAS"` | Copie entre lecteurs |

---

## 5. Dossiers-disque (Disk 1 / Disk 2 / …)

L'option `-d <dossier>` fait d'un dossier du PC un **disque interchangeable** :

- **Au démarrage**, tous les fichiers du dossier sont **chargés automatiquement** dans le
  disque virtuel — donc `FILES "L:"` les liste **sans** avoir à préciser de fichier.
- **À la déconnexion** (`INIT "L:D"`), les fichiers créés/modifiés par le pocket sont
  **réécrits dans ce dossier**.

Exemple — trois disquettes virtuelles :

```
.\aplinks32.exe -p com1 -b 9600 -5 -d "Disk 1"
```

Placez vos programmes Sharp dans `Disk 1`, `Disk 2`, `Disk 3`… et pointez `-d` sur celui
voulu. Sans `-d`, le disque démarre **vide** et les fichiers sont lus/écrits dans le dossier
courant. Les **dates des fichiers** sont préservées dans les deux sens.

> Astuce : utilisez un **dossier dédié** par disque. Évitez de pointer `-d` sur un dossier
> contenant des fichiers non-Sharp (ex. le dossier du programme), ils seraient chargés aussi.

### Sessions multiples (sans redémarrer le serveur)

Depuis cette version, `INIT "L:D"` **n'arrête plus le serveur** : il écrit les fichiers,
recharge le dossier-disque et **reste prêt** pour une nouvelle connexion. Pour arrêter :

- **Ctrl-D** dans la console → écrit les fichiers puis quitte.
- **Ctrl-C** → quitte immédiatement, **sans** écrire les fichiers.

### Espace disque restant

Le serveur affiche l'espace libre du disque virtuel — en Ko et en pourcentage — **après le
chargement** du dossier-disque, à **chaque déconnexion**, et à la **sortie** (Ctrl-D / Ctrl-C) :

```
Reading "Disk1\BIG.BAS" ... done
Disk free: 443 KB of 502 KB (88.3%)
```

Le calcul se fait à partir de la FAT, donc il tient compte **aussi bien** des fichiers
préchargés que de ceux écrits depuis le Sharp. Capacités utiles : **122 Ko** en mode 128 Ko,
**502 Ko** en mode 512 Ko.

---

## 6. Modes 128 Ko et 512 Ko

Le mode ne change que la **géométrie** du disque virtuel (le protocole est identique) :

| | 128 Ko | 512 Ko |
|---|---|---|
| Capacité data | ~122 Ko (980 secteurs) | ~502 Ko (4016 secteurs) |
| Fichiers max | 128 | 128 |

- Choisi au lancement par `-1` / `-5` (fixe le mode des fichiers **préchargés**).
- **Bascule automatique** sur un disque vide selon l'`INIT "L:1"` / `INIT "L:5"` du pocket.
- Les deux côtés doivent finir dans le **même mode**.

---

## 7. Le réglage série (important)

Deux points sont indispensables et non évidents :

1. **RTS = ON** côté PC. Le pocket ne transmet que si son entrée **CS** est haute, et CS
   est piloté par le **RTS du PC** (Tech Ref PC-E500 p.54). Sans RTS=ON, *le PC ne reçoit
   rien* (symptôme : en `-v`, on ne voit que les points `.` sans aucune commande). C'est le
   défaut du serveur ; réglable via `--rts`.

2. **Pas de contrôle de flux XON/XOFF.** PLINK transporte des secteurs **binaires** : un
   octet de données valant 0x11 ou 0x13 serait pris pour un XON/XOFF et corromprait le
   transfert (symptôme : *Bad drive name* côté Sharp). D'où le `N` dans le `OPEN` côté
   pocket, et XON/XOFF désactivé côté PC.

Champs du `OPEN "9600,N,8,1,A,L,&1A,N,N"` : vitesse, parité **N**, 8 bits, 1 stop, `A`,
`L` (fin de ligne CR+LF), `&1A` (code de fin de fichier), **`N`** (flux : *aucun*, surtout
pas `X`), `N`.

---

## 8. Compilation (facultatif)

Le binaire `aplinks32.exe` est fourni. Pour recompiler depuis `APLINKS.C` :

```
# Windows : script fourni
.\build.ps1
# ou à la main (MinGW gcc, clang, ou MSVC)
gcc -x c -std=c99 -O2 -o aplinks32.exe APLINKS.C

# Linux / macOS : Makefile fourni
make
# ou à la main
cc -std=c99 -O2 -o aplinks APLINKS.C
```

> L'extension `.C` (majuscule) fait croire à gcc/clang qu'il s'agit de C++ : d'où le
> `-x c`. Ne pas nommer le binaire `aplinks.exe` sous Windows (collision avec le
> `APLINKS.EXE` DOS d'origine, système de fichiers insensible à la casse).

---

## 9. Dépannage

| Symptôme | Cause probable | Solution |
|----------|----------------|----------|
| `FILES "L:"` ne renvoie rien | Disque virtuel **vide** (normal) | Précharger un fichier en argument, ou faire un `SAVE "L:…"` d'abord |
| En `-v`, que des points `.`, aucune commande | RTS pas à ON, ou câble/port | Vérifier `RTS=ON` dans la bannière ; tester `--rts on --dtr off` |
| `Bad drive name` côté Sharp | Contrôle de flux XON/XOFF actif | `OPEN` avec le champ flux à **`N`** (pas `X`) |
| `Can't open serial port` | Port occupé ou inexistant | Fermer les autres logiciels série ; vérifier `-p` |
| Fichier reçu « binaire » | `SAVE` tokenise par défaut | Utiliser `SAVE "L:…",A` pour de l'ASCII |
| Rien n'est écrit sur le PC | Pas de `INIT "L:D"` | Terminer par `INIT "L:D"` (déclenche l'écriture) |

Le mode **`-v`** est l'outil de diagnostic : il montre chaque commande reçue
(`[S]` handshake, `[R]` lecture, `[W]` écriture, `[D]` déconnexion, `[?]` octet ignoré) et
un battement `.` prouvant que le serveur est vivant et en attente.

---

## 10. Fichiers de ce dossier

- `APLINKS.C` — source C99 portable (Win32 + POSIX), compatible 128/512 Ko.
- `aplinks32.exe` — binaire Windows recompilé.
- `build.ps1` / `Makefile` — scripts de compilation (Windows / POSIX).
- `APLINKS.EXE` — binaire **MS-DOS d'origine** (1993), conservé intact.
- `APLINKS.DOC` — documentation d'origine (japonais) + addendum.
- `README.md` — ce fichier.

Serveur d'origine © 1992-93 N.Kon. Pilote PLINKC © 1996-99 D.Mizobata / N.Kon.
