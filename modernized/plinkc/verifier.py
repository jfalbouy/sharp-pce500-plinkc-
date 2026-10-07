#!/usr/bin/env python3
# Verifie la table de relocation du pilote modernise, et la reference d'origine.
#
# 1. reference/plinkc.a62.asm doit redonner reference/PLINKC.OBJ (l'objet de 1999).
# 2. plinkc.asm est assemble a DEUX origines (la sienne et 01000h plus bas). Chaque corps est
#    reloge par SA table, exactement comme le fait l'installateur (boucle de deltas
#    de Kon : bit 80h = champ de 3 octets, 7Eh = ecart long sur 2 octets, 0FFh = fin),
#    vers plusieurs destinations. Les deux resultats doivent etre identiques a l'octet :
#    une adresse absolue oubliee (un 'rel' manquant) garderait la trace de son origine
#    d'assemblage et ferait echouer la comparaison.
# 3. A titre d'information : le meme controle contre le corps de la 1.62 dit si le
#    pilote installe a change.
#
#   python verifier.py [chemin de xasm2026-4.exe]
import os, re, subprocess, sys, tempfile

ICI = os.path.dirname(os.path.abspath(__file__))
# xasm2026-4 : 1er argument, sinon variable XASM2026_4, sinon le PATH.
# https://github.com/jfalbouy/XASM2026_CSharp
XASM = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("XASM2026_4", "xasm2026-4")
DECALAGE = 0x1000          # la 2e origine d'assemblage est 01000h plus bas
DESTINATIONS = (0x80018, 0x80938, 0x9F000, 0xAFF00)

def assembler(src, tmp, org=None):
    """Assemble src dans tmp (avec son pce500.inc) ; org : une autre origine que la sienne.
    Rend (objet, btop, prgend, entry, origine)."""
    texte = open(src, encoding="latin-1").read()
    nom = os.path.splitext(os.path.basename(src))[0]
    if org is not None:
        texte, n = re.subn(r"^(\s+org\s+)\$[0-9a-fA-F]+", r"\g<1>$%x" % org, texte, count=1, flags=re.M)
        if n != 1:
            sys.exit(f"{src} : ligne 'org' introuvable")
        # le seul assert qui porte sur une adresse absolue
        texte = re.sub(r"^\s*assert\s+entry\s*=.*$", "", texte, flags=re.M)
        nom += "_%x" % org
    open(os.path.join(tmp, nom + ".asm"), "w", encoding="latin-1", newline="\n").write(texte)
    inc = os.path.join(os.path.dirname(src), "pce500.inc")
    if os.path.exists(inc):
        open(os.path.join(tmp, "pce500.inc"), "wb").write(open(inc, "rb").read())
    r = subprocess.run([XASM, nom + ".asm", "-O", nom + ".obj", "-L", nom + ".lst", "-S"],
                       cwd=tmp, capture_output=True, text=True)
    if "No fatal error" not in r.stdout:
        sys.exit(f"echec d'assemblage de {src} :\n{r.stdout}{r.stderr}")
    lst = open(os.path.join(tmp, nom + ".lst"), encoding="latin-1").read()
    sym = lambda n: int(re.search(r"([0-9A-F]+)h  %s\r?$" % n, lst, re.M).group(1), 16)
    entry = sym("entry")
    return open(os.path.join(tmp, nom + ".obj"), "rb").read(), sym("btop"), sym("prgend"), entry, entry

def reloger(obj, btop, prgend, entry, org, dest):
    code = obj[16:]                       # en-tete de l'objet XASM : 16 octets
    corps = bytearray(code[btop - org:prgend - org])
    table = code[prgend - org:]
    y, i, sites = dest - (btop - entry), 0, 0
    while table[i] != 0xFF:
        a = table[i]; i += 1
        n = 3 if a & 0x80 else 2
        if a & 0x7F == 0x7E:
            y += table[i] | table[i + 1] << 8; i += 2
        else:
            y += a & 0x7F
        p = y - dest
        if not (0 <= p and p + n <= len(corps)):
            sys.exit(f"site de relocation hors du corps : {y:05X}h")
        v = (int.from_bytes(corps[p:p + n], "little") - (btop - dest)) % (1 << 8 * n)
        corps[p:p + n] = v.to_bytes(n, "little"); sites += 1
    if i + 1 != len(table):
        sys.exit(f"{len(table) - i - 1} octet(s) apres le terminateur 0FFh")
    return bytes(corps), sites

with tempfile.TemporaryDirectory() as tmp:
    ref = assembler(os.path.join(ICI, "reference", "plinkc.a62.asm"), tmp)
    new = assembler(os.path.join(ICI, "plinkc.asm"), tmp)
    alt = assembler(os.path.join(ICI, "plinkc.asm"), tmp, org=new[4] - DECALAGE)

ok = ref[0] == open(os.path.join(ICI, "reference", "PLINKC.OBJ"), "rb").read()
print(f"reference -> PLINKC.OBJ d'origine : {'identique' if ok else 'DIFFERENT'}")

# L'objet entier (installateur, corps, table de relocation) doit tenir sous le
# plafond 0BFC00h de la zone langage machine : au-dela, LOADM ecrase la zone
# systeme (s1_top 0BFC15h, d_link 0BFCA2h...). La table est ajoutee apres END :
# aucun assert de la source ne peut le verifier, d'ou ce controle ici.
PLAFOND = 0xBFC00
taille = int.from_bytes(new[0][5:8], "little")     # en-tete XASM : longueur en 05h-07h,
debut = int.from_bytes(new[0][8:11], "little")     # adresse de chargement en 08h-0Ah
fin = debut + taille
sous = fin <= PLAFOND
ok &= sous
print(f"objet {debut:05X}h-{fin - 1:05X}h ({taille} o) : "
      f"{'sous le plafond 0BFC00h' if sous else 'DEPASSE LE PLAFOND 0BFC00h de %d o' % (fin - PLAFOND)}")
for dest in DESTINATIONS:
    a, sa = reloger(*new, dest)
    b, sb = reloger(*alt, dest)
    same = a == b and sa == sb
    ok &= same
    print(f"corps reloge en {dest:05X}h depuis {new[4]:05X}h et {alt[4]:05X}h : "
          f"{len(a)} octets, {sa} sites -> {'identique' if same else 'DIFFERENT'}")
a, sa = reloger(*new, DESTINATIONS[0])
r, sr = reloger(*ref, DESTINATIONS[0])
print(f"(info) par rapport a la 1.62 ({len(r)} octets, {sr} sites) : corps "
      f"{'inchange' if a == r else 'modifie'}")
print("OK" if ok else "ECHEC")
sys.exit(0 if ok else 1)
