# Sharp PC-E500 — Pocket Link System (PLINK / PLINKC / APLINKS)

[🇬🇧 English](README.md) · **🇫🇷 Français**

Préservation et modernisation du **Pocket Link System**, une famille de logiciels
libres japonais des années 1990 qui transforme un ordinateur de poche **Sharp
PC-E500** en client d'un PC via un câble série. Le pocket voit un lecteur de
disque ordinaire **`L:`** — mais ce lecteur n'a aucun stockage physique : chaque
secteur lu ou écrit est transporté par la liaison série jusqu'à un petit
**programme serveur tournant sur le PC**, où les fichiers existent réellement.

Ce dépôt conserve les **archives d'origine intactes** (`original/`) et ajoute un
**serveur modernisé et portable** qui dialogue encore avec du vrai matériel en
2026 (`modernized/`).

```
   Sharp PC-E500(S)                         PC (Windows / Linux / macOS)
  ┌────────────────┐   9600–19200 bps      ┌──────────────────────────┐
  │  BASIC + PLINKC │◄─── câble série ────►│  serveur APLINKS         │
  │  pilote  → L:   │  (secteurs sur fil)  │  fichiers L: ⇄ dossier PC │
  └────────────────┘                        └──────────────────────────┘
```

---

## L'histoire

Le Pocket Link System a été créé par **N.Kon (近成人)** et publié pour la première
fois dans le magazine japonais *Pokecon Journal* en juin 1990 : un pilote de
périphérique résident `PLINK.SYS` pour le PC-E500 et un serveur PC compagnon
`PLINKM`. Il a évolué au fil des ans à travers plusieurs auteurs :

| Année | Composant | Auteur | Apport |
|-------|-----------|--------|--------|
| 1990–94 | **PLINK** (`PLINK.SYS` + `PLINKM`) | N.Kon | Le pilote, le serveur et le **protocole série** d'origine. |
| 1992–93 | **APLINKS** (MS-DOS) | N.Kon | Un serveur qui expose **directement de vrais fichiers PC** comme disque virtuel (plus besoin d'une image « filed-drive »). |
| 1996–97 | **APLINKS for Win32** | Y.Akagawa | Un portage Windows (GUI) d'APLINKS, avec la capacité **512 Ko**. |
| 1996–99 | **PLINKC** (« Pocket Link **Cache** ») | D.Mizobata | Un pilote plus rapide : ajoute un **cache de 8 secteurs** à `PLINK.SYS` et gère le lecteur `L:` en **512 Ko**. La version 1.62 est la dernière. |
| 2026 | **APLINKS modernisé** | J-F Albouy | Ce dépôt : le serveur DOS de 1993 **porté en C portable** et étendu — voir plus bas. |

Le tout est un logiciel libre (freeware). Les archives d'origine sont conservées
ici byte-pour-byte ; voir le [`NOTICE`](NOTICE) pour les auteurs, copyrights et
les conditions exactes de licence.

---

## Contenu du dépôt

```
original/                     ← les archives d'auteur intactes (pristine)
├── PLINK-1.04-1994/          N.Kon    — pilote + serveur + docs + source SC62015
├── PLINKC-1.62-1999/         Mizobata — le pilote à cache (installeur, BASIC, docs)
├── APLINKS-DOS-1.03-1993/    N.Kon    — le serveur MS-DOS (source C + EXE + docs)
└── APLINKS-Win32-1.02-1997/  Akagawa  — le serveur GUI Windows

modernized/
└── aplinks/                  ← dérivé 2026 : le serveur portable et étendu
    ├── APLINKS.C             source de référence C99 (Win32 + POSIX)
    ├── APLINKS_C17.C         variante C17 (comportement identique)
    ├── aplinks32.exe         binaire Windows précompilé
    ├── aplinks32_c17.exe     binaire Windows précompilé (build C17)
    ├── build.ps1 / build_c17.ps1 / Makefile
    └── README.md             guide d'utilisation & dépannage complet (français)

NOTICE                        attribution + conditions de licence + modifications
CLAUDE.md                     notes techniques détaillées (protocole, architecture)
```

Les archives d'`original/` sont redistribuées **sans modification**, exactement
comme le permettent leurs licences freeware. Le serveur de `modernized/` est un
**dérivé clairement séparé** d'APLINKS de N.Kon ; son protocole sur le fil est
byte-pour-byte identique à l'original.

---

## Le serveur modernisé (2026)

`modernized/aplinks/` est l'`APLINKS.C` DOS de 1993 de N.Kon **porté hors de
`<dos.h>` vers du C ISO** avec une couche `#ifdef _WIN32` / POSIX, qui compile et
tourne sur Windows, Linux et macOS actuels. Par-dessus le protocole inchangé, il
ajoute :

- les modes disque **128 Ko et 512 Ko** (`-1` / `-5`, ou auto-négociés à l'`INIT`) ;
- un modèle de **dossier-disque** (`-d Dossier`) : un dossier PC *est* le disque
  virtuel — ses fichiers se chargent automatiquement et ceux enregistrés par le
  pocket y sont réécrits ;
- l'**horodatage des fichiers**, des **options série runtime** (`-p`, `-b`,
  `--rts/--dtr`), un **journal verbeux** (`-v`, `-l`), l'affichage de l'**espace
  libre** et de l'**historique de session** ;
- validé de bout en bout sur **vrai matériel PC-E500**, 9600 et 19200 bps,
  128/512 Ko, dans les deux sens.

### Compilation

```sh
# Windows (MinGW-w64 gcc, clang, ou MSVC)
gcc -x c -std=c99 -O2 -o aplinks32.exe APLINKS.C     # ou :  .\build.ps1
# Linux / macOS
cc -std=c99 -O2 -o aplinks APLINKS.C                 # ou :  make
```

*(L'extension `.C` fait croire à gcc/clang qu'il s'agit de C++ — passez `-x c`.)*

### Utilisation (démarrage rapide)

```
# PC :
aplinks32 -p com3 -b 19200 -5 -d "MonDisque"
# Pocket (BASIC) :
OPEN "9600,N,8,1,A,L,&1A,N,N":CLOSE
INIT "L:5"
FILES "L:" : SAVE "L:PROG.BAS" : LOAD "L:PROG.BAS"
INIT "L:D"          ' déconnexion + écriture des fichiers dans le dossier PC
```

Un détail matériel non évident : le PC doit forcer **RTS=ON**, sinon le pocket
n'émet jamais (son entrée CS est pilotée par le RTS du PC). Le guide complet
d'utilisation et de dépannage — dont la sauvegarde/restauration de carte mémoire
S2 (`RAMFILE`) — est dans
**[`modernized/aplinks/README.md`](modernized/aplinks/README.md)** (en français).

---

## Crédits

- **N.Kon (近成人)** — PLINK / Pocket Link System et le protocole (1990–94) ;
  serveur APLINKS d'origine (1992–93).
- **Daisuke Mizobata (溝端大介)** — pilote PLINKC « Pocket Link Cache » (1996–99).
- **Y.Akagawa (赤川裕一)** — APLINKS for Win32 (1996–97).
- **Jean-François Albouy** — portage et extensions du serveur APLINKS (2026).

## Licence

Chaque composant d'origine garde ses propres conditions freeware des années 1990
(redistribution de l'archive **non modifiée** autorisée ; pas de vente
commerciale). Le dérivé 2026 est proposé de bonne foi pour une plateforme depuis
longtemps abandonnée. Les détails complets, les copyrights par auteur et une
clause de contact/retrait figurent dans le **[`NOTICE`](NOTICE)**.
