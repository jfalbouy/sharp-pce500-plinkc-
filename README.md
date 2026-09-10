# Sharp PC-E500 — Pocket Link System (PLINK / PLINKC / APLINKS)

**🇬🇧 English** · [🇫🇷 Français](README.fr.md)

Preservation and modernization of the **Pocket Link System**, a family of 1990s
Japanese freeware that turns a **Sharp PC-E500 series** pocket computer into a
client of a PC over a serial cable. The pocket computer sees an ordinary disk
drive **`L:`** — but that drive has no physical storage: every sector read or
written is carried over the serial link to a small **server program running on
the PC**, where the files live as real files.

This repository keeps the **original author archives intact** (`original/`) and
adds a **modernized, portable server** that still talks to real hardware in 2026
(`modernized/`).

```
   Sharp PC-E500(S)                         PC (Windows / Linux / macOS)
  ┌────────────────┐   9600–19200 bps      ┌──────────────────────────┐
  │  BASIC + PLINKC │◄─── serial cable ───►│  APLINKS server          │
  │  driver  → L:   │   (sectors on wire)  │  L: files ⇄ PC folder    │
  └────────────────┘                        └──────────────────────────┘
```

---

## The story

The Pocket Link System was created by **N.Kon (近成人)** and first published in
the Japanese magazine *Pokecon Journal* in June 1990: a resident device driver
`PLINK.SYS` for the PC-E500 plus a companion PC server `PLINKM`. It has grown
through several authors over the years:

| Year | Component | Author | What it added |
|------|-----------|--------|---------------|
| 1990–94 | **PLINK** (`PLINK.SYS` + `PLINKM`) | N.Kon | The original driver, server and serial **wire protocol**. |
| 1992–93 | **APLINKS** (MS-DOS) | N.Kon | A server that exposes **real PC files directly** as the virtual disk (no single "filed-drive" image needed). |
| 1996–97 | **APLINKS for Win32** | Y.Akagawa | A Windows GUI port of APLINKS, with **512 KB** disk support. |
| 1996–99 | **PLINKC** ("Pocket Link **Cache**") | D.Mizobata | A faster driver: adds an **8-sector cache** to `PLINK.SYS` and supports the **512 KB** `L:` drive. Version 1.62 is the last. |
| 2026 | **APLINKS modernized** | J-F Albouy | This repo: the 1993 DOS server **ported to portable C** and extended — see below. |

All of it is freeware. The original archives are preserved here byte-for-byte;
see [`NOTICE`](NOTICE) for authors, copyrights and the exact license terms.

---

## What's in this repository

```
original/                     ← the untouched author archives (pristine)
├── PLINK-1.04-1994/          N.Kon    — driver + server + docs + SC62015 source
├── PLINKC-1.62-1999/         Mizobata — the cache driver (installer, BASIC, docs)
├── APLINKS-DOS-1.03-1993/    N.Kon    — the MS-DOS server (C source + EXE + docs)
└── APLINKS-Win32-1.02-1997/  Akagawa  — the Windows GUI server

modernized/
└── aplinks/                  ← 2026 derivative: the portable, extended server
    ├── APLINKS.C             C99 reference source (Win32 + POSIX)
    ├── APLINKS_C17.C         C17 readability variant (identical behavior)
    ├── aplinks32.exe         prebuilt Windows binary
    ├── aplinks32_c17.exe     prebuilt Windows binary (C17 build)
    ├── build.ps1 / build_c17.ps1 / Makefile
    └── README.md             full usage & troubleshooting guide (French)

NOTICE                        attribution + license terms + list of changes
CLAUDE.md                     deep technical notes (protocol, architecture, gotchas)
```

The `original/` archives are redistributed **unmodified**, exactly as their
freeware licenses permit. The `modernized/` server is a **clearly separated
derivative** of N.Kon's APLINKS; its on-wire protocol is byte-for-byte identical
to the original.

---

## The modernized server (2026)

`modernized/aplinks/` is N.Kon's 1993 DOS `APLINKS.C` **ported off `<dos.h>` to
ISO C** with a `#ifdef _WIN32` / POSIX platform layer, so it builds and runs on
current Windows, Linux and macOS. On top of the unchanged protocol it adds:

- **128 KB and 512 KB** disk modes (`-1` / `-5`, or auto-negotiated at `INIT`);
- a **disk-folder model** (`-d Folder`): a PC folder *is* the virtual disk — its
  files auto-load, and files the pocket saves are written back to it;
- **file timestamps**, **runtime serial options** (`-p`, `-b`, `--rts/--dtr`),
  **verbose logging** (`-v`, `-l`), **free-space** and **session-history** display;
- validated end-to-end on **real PC-E500 hardware**, 9600 and 19200 bps, 128K/512K,
  in both directions.

### Build

```sh
# Windows (MinGW-w64 gcc, clang, or MSVC)
gcc -x c -std=c99 -O2 -o aplinks32.exe APLINKS.C     # or:  .\build.ps1
# Linux / macOS
cc -std=c99 -O2 -o aplinks APLINKS.C                 # or:  make
```

*(The `.C` extension makes gcc/clang assume C++ — pass `-x c`.)*

### Run (quick start)

```
# PC:
aplinks32 -p com3 -b 19200 -5 -d "MyDisk"
# Pocket (BASIC):
OPEN "9600,N,8,1,A,L,&1A,N,N":CLOSE
INIT "L:5"
FILES "L:" : SAVE "L:PROG.BAS" : LOAD "L:PROG.BAS"
INIT "L:D"          ' disconnect + flush files to the PC folder
```

One non-obvious hardware detail: the PC must assert **RTS=ON** or the pocket
never transmits (its CS input is driven by the PC's RTS). The full usage and
troubleshooting guide — including S2 memory-card (`RAMFILE`) backup/restore — is
in **[`modernized/aplinks/README.md`](modernized/aplinks/README.md)** (French).

---

## Credits

- **N.Kon (近成人)** — PLINK / Pocket Link System and the wire protocol (1990–94);
  original APLINKS server (1992–93).
- **Daisuke Mizobata (溝端大介)** — PLINKC "Pocket Link Cache" driver (1996–99).
- **Y.Akagawa (赤川裕一)** — APLINKS for Win32 (1996–97).
- **Jean-François Albouy** — 2026 port and extensions of the APLINKS server.

## License

Each original component keeps its own 1990s freeware terms (redistribution of the
**unmodified** archive is permitted; no commercial sale). The 2026 derivative is
offered in good faith for a long-abandoned platform. Full details, per-author
copyrights, and a contact/removal statement are in **[`NOTICE`](NOTICE)**.
