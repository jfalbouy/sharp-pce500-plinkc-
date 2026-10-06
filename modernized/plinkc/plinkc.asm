		org	$bf000
;----------------------------------------------------------------------
;
;	Pocket Link Cache Device Driver ver 1.62
;	Installation program
;	for PC-E500 series pocket computer
;	Copyright (c) 1996,1997,1999 by Daisuke Mizobata
;
;	based on PLINK.SYS ver 1.04
;	Copyright (c) 1990,93,94 N.Kon
;
;----------------------------------------------------------------------
;----------------------------------------------------------------------
;
;	Mise a jour 2026 (J.-F. Albouy) - derive de PLINKC 1.62, voir NOTICE
;	  - constantes systeme tirees de pce500.inc ;
;	  - desinstallation par CALL &BF000 "-U" (deliage + SET/KILL), qui
;	    reconnait aussi un bloc de la 1.62 d'origine ;
;	  - INIT "L:?" : etat du pilote (mode, numero de device, bloc) ;
;	  - INIT "L:H" : version, taille, etat et commandes ; une option
;	    inconnue est signalee (la 1.62 videait le tampon sans rien dire) ;
;	  - INIT "L:2" : mode 256K ;
;	  - apres chaque INIT "L:1"/"L:2"/"L:5", commande 'Q' : le serveur
;	    (APLINKS 1.07) rend son mode reel, que le pilote adopte ;
;	  - � deja installe � detaille : etat du pilote en place, autre
;	    version, bloc non chaine, ou "L:" pris par un autre pilote.
;	Protocole : seul ajout, la commande 'Q' (APLINKS 1.07 y repond, les
;	serveurs anciens l'ignorent) ; 'S' est inchange. Le corps ne differe de la 1.62 que par INIT "L:?",
;	INIT "L:2" et mpb256. verifier.py controle la table de relocation.
;	Assembleur : xasm2026-4 (dialecte A62 : rel, #defmacro, suborg, { }).
;	Reference d'origine : reference/plinkc.a62.asm -> PLINKC.OBJ.
;
;----------------------------------------------------------------------
;

;----------------------------------------------------------------------
;		Definitions numeriques
;----------------------------------------------------------------------
;	Constantes systeme : pce500.inc (genere depuis les tables du
;	desassembleur SC62015Disassembler, noms identiques a ses sorties).
;	Correspondance avec les noms d'origine de PLINKC 1.62 :
;	  fcs -> fcs_call         iocs -> iocs_call      iroot -> d_link
;	  sio_rcv_vct -> intv_sio_rx   sio_param -> sio_baud
;	  base -> bp_ram   bx/cx/dx -> bl/cl/dl   cx+1 -> ch
;	  key_strobe_2 -> koh      sio_ctrl_reg -> ucr    sio_stat_reg -> usr
;	  sio_rx_reg -> rxd        sio_tx_reg -> txd      intr_mask_reg -> imr
;	  system_stat_reg -> ssr   btext -> txtbas        bdata -> datbas
;	  iwork -> iocsw           s1top -> s1_top        s1end -> s1_btm
;	  bworkp -> baswrk         $bfcbe -> softint
;	Retirees car inutilisees : iocs_fook, bpmax, keyvec, cdrv, rev.
		include	pce500.inc

sectsiz:	equ	128
cache_sect:	equ	sectsiz+1
cache_next:	equ	cache_sect+2
cache_size:	equ	cache_next+3
n_fcache:	equ	7		;	Nombre de secteurs dans le cache FAT
n_dcache:	equ	1		;	Nombre de secteurs dans le cache de donnees
dtop:		equ	44
timeout:	equ	40000		; Delai d'attente (environ 1 seconde)

#DEFMACRO bsr
	rel call	%0
#ENDMACRO

;	Revision de la mise a jour 2026, definie UNE seule fois : banniere de
;	l'installateur et INIT "L:H". La 1.62 reste le numero de Mizobata.
	macro	drvrev
	db	'2026.1'
	endm

;
;	Installateur
;

pntr	dest,bottom,mdf,offset
byte	argu				;	Drapeau d'argument : 0 installer, 1 desinstaller

;	ENTRY DOIT RESTER A L'ORG : la boucle de relocation part de btop-entry,
;	et la table generee par les 'rel' compte ses ecarts depuis l'org.
entry:
	pre	$32
	sub	(bp_ram),%

;	Argument de CALL : CALL &BF000 installe, CALL &BF000 "-U" desinstalle.
;	Protocole d'UUENCODE (argskp) : le pointeur de ligne BASIC, pris sur la
;	pile U, y est RENDU avance jusqu'au terminateur ; quatre terminateurs
;	(0, CR, 1Ah, 0FFh) - sinon 'Syntax error' au retour dans BASIC.
	popu	x
	mv	(argu),0
arg_lp:	mv	a,[x++]
	cmp	a,0
	jrz	arg_end
	cmp	a,$0d
	jrz	arg_end
	cmp	a,$1a
	jrz	arg_end
	cmp	a,$ff
	jrz	arg_end
	cmp	a,'-'
	jrnz	arg_lp
	mv	a,[x]
	cmp	a,'u'
	jrz	arg_u
	cmp	a,'U'
	jrnz	arg_lp
arg_u:	mv	(argu),1
	jr	arg_lp
arg_end:	dec	x
	pushu	x

	mv	x,title
	mv	y,title_e-title
	call	puts
	test	(argu),1
	jpnz	uninst

;	Deja installe ? Le bloc PLINK.SYS d'abord, puis "L:" (2026 : la 1.62
;	refusait sur l'un ou l'autre sans dire lequel ni ou).
	pre	$32
	mv	(ch),0			;	Slot 0 = S1: (fonction 41h)
	mv	x,btop+1
	mv	il,d6_search_phys
	call	memd			;	Y = bloc, carry si absent
	jrc	ex_sans_bloc
	mv	(dest),y
	mv	x,dvname
	mv	il,iocs_find_drive
	call	icall			;	Recherche de nom de lecteur
	jrc	ex_non_lie		;	Bloc present, mais "L:" n'est plus chaine
	mv	x,(dest)
	mv	y,[x+$11]
	mv	(bottom),y
	mv	y,blen
	cmpp	(bottom),y
	jrnz	ex_autre		;	Un autre PLINK.SYS (1.62 d'origine...)
	mv	x,etat			;	Notre version : INIT "L:?" lui fait
	mv	il,iocs_fmt_drive	;	afficher son etat (mode, device, bloc)
	call	icall
	mv	il,exi_m-mb
	jp	msend
ex_autre:
	mv	x,exo_m
	mv	y,exo_e-exo_m
	jr	ex_fin
ex_non_lie:
	mv	x,exu_m
	mv	y,exu_e-exu_m
	call	puts
	mv	x,sk_m
	mv	y,sk_e-sk_m
	jr	ex_fin
ex_sans_bloc:
	mv	x,dvname
	mv	il,iocs_find_drive
	call	icall
	jrc	ex_libre		;	Ni bloc ni "L:" : on installe
	mv	x,exl_m
	mv	y,exl_e-exl_m
ex_fin:	call	puts
	jp	fin
ex_libre:

	mv	y,[d_link]			;	Debut de la liste d'en-tete IOCS d'origine
	mv	[ihead],y

;	Definir le numero de peripherique
	pre	$32
	mv	(cl),10-1			;	Numero de peripherique planifie 10
	{
		pre	$32
		inc	(cl)
		mv	il,iocs_header_addr
		call	icall
		jrnc	continue
	}
	pre	$32
	mv	[devno],(cl)		;	Definir le numero de peripherique

	mv	il,d6_condense
	call	memd

;	Verifiez l'emplacement d'installation
	mv	x,[s1_top]
	mv	y,[x+$12]
loop1:	add	x,y
	mv	(dest),x
	mv	a,[x]
	cmp	a,$fb
	jrnz	chksize
	mv	a,[x+$0c]
	test	a,$0c

loop2:	mv	y,[x+$11]
	jrnz	loop1
	add	x,y
	mv	a,[x]
	cmp	a,$fb
	jrz	loop2

chksize:
;	 Verifiez si le programme depasse la limite de 64 Ko
	mv	i,prgend-btop		;	Taille du conducteur seulement
	mv	ba,(dest)
	add	ba,i
	mv	il,pg_m-mb
	jrc	msend2

;	Verifier la capacite de la memoire
	mv	(bottom),x
	mv	y,[s1_btm]
	sub	y,x
	dec	y
	mv	ba,blen
	sub	y,ba
	mv	il,mem_m-mb
	jrc	msend2

;	Bloc memoire Stagger
	mv	x,(bottom)
	mv	y,(dest)
	sub	x,y
	inc	x				;	x = nombre d'octets a deplacer
	pushu	imr			;	Desactiver l'interruption
	mv	[--s],u			;	pushs	u
	mv	y,(bottom)
	mv	u,(bottom)
	add	u,ba
	inc	u
	inc	y
	{
		mv	a,[--y]
		pushu	a		;	mv	[--u],a
		dec	x
	jrnz	continue
	}

;	Chauffeur de transfert
	mv	u,btop
	mv	x,(dest)
	mv	[--s],u			;	pushs	u
	sub	u,x
	mv	(offset),u
	mv	u,[s++]			;	pops	u
	mv	i,prgend-btop	;	Taille du conducteur seulement
	{
		popu	a		;	mv	a,[u++]
		mv	[x++],a
		dec	i
		jrnz	continue
	}

;	Relocaliser le traitement
	mv	y,(dest)
	mv	ba,btop-entry
	sub	y,ba
	{
		popu	a		;	mv	a,[u++]
		cmp	a,$ff
		jrz	break
		mv	il,2
		test	a,$80
		jrz	word
		inc	il
word:		and	a,$7f
		cmp	a,$7e
		jrnz	short
		popu	ba		;	mv	ba,[u++]
		add	y,ba
		db	$0a			;	Passer les 2 octets suivants
short:		add	y,a		
		mvp	(mdf),[y]
		sbcl	(mdf),(offset)
		mvp	[y],(mdf)
		jr	continue
	}

	mv	u,[s++]			;	pops	u

;	S'inscrire a la liste IOCS
	mv	x,(dest)
	mv	a,ihead-btop
	add	x,a
	mv	[d_link],x

	popu	imr
	mv	x,dvname
	mv	il,iocs_fmt_drive
	call	icall		;	Initialisation des parametres

	mv	il,ins_m-mb
msend2:

	pushu	i
	call	linkbas		;	Corrigez les pointeurs de BTEXT $ et BDATA $ en BASIC
	mv	a,0
	pre	$32
	mv	[(iocsw)+$3a],a	;	Detachez RAMFILE
	popu	i
msend:	call	putm2
fin:	pre	$32
	add	(bp_ram),%
	rc				;	Carry CLAIR : arme, BASIC repondrait 'Syntax error'
	retf

;	putm2 : message de la table mb (IL = son ecart, 1er octet = longueur)
;	puts  : X = texte, Y = longueur, a l'ecran (handle 0)
putm2:	mv	x,mb
	add	x,i
	mv	il,[x++]
	mv	y,i
puts:	pre	$32
	mv	(cl),0
	mv	il,fcs_write_block
	callf	fcs_call
	ret

linkbas:
;	Pointeur de BTEXT $ et BDATA $
	pre	$32
	mv	x,[baswrk]
	mv	a,$72
	add	x,a
	call	bsearch
	jrc	bomb
	pre	$32
	mv	(txtbas),y
	call	bsearch
	jrc	bomb
	pre	$32
	mv	(datbas),y
	ret
bomb:	reset

bsearch:mv	il,d6_search_phys
memd2:	pre	$32
	mv	(ch),[x++]
memd:	pre	$32
	mv	(cl),dev_memcard
icall:	callf	iocs_call
	ret

;----------------------------------------------------------------------
;		Desinstallation : CALL &BF000 "-U"
;----------------------------------------------------------------------
;	Le pilote ne tient AUCUN vecteur au repos : il ne detourne la SIO que
;	le temps d'un appel (devmain la rend en jump00). Desinstaller, c'est
;	donc delier son en-tete de la chaine des devices, puis faire taper
;	SET et KILL a l'utilisateur : ce sont des commandes de MODE DIRECT,
;	qu'un programme ne peut pas executer.
;	Le bloc se retrouve par la CHAINE DES BLOCS de S1:, pas par d_link :
;	si un amorcage a perdu le maillon, le bloc est toujours la.
uninst:
	mv	x,[s1_top]
	mv	y,[x+$12]
un_blk:	add	x,y
	mv	a,[x]
	cmp	a,$fb
	jrnz	un_absent		;	Fin de la chaine des blocs
	mv	(dest),x
	mv	y,btop			;	Signature + nom, lus dans l'image (jamais relogee)
	mv	il,12
	call	compare
	mv	x,(dest)
	mv	y,[x+$11]		;	Taille du bloc (MV ne touche pas aux drapeaux)
	jrnz	un_blk

;	Le deliage ne touche qu'a l'en-tete IOCS : on reconnait donc le bloc a
;	cet en-tete, pas a sa taille (qui change a chaque version) - le nom de
;	device 'L:',0 a sa place (bloc+2Ah), donc le lien suivant en bloc+22h.
;	C'est la disposition de la 1.62 d'origine et de toutes les versions
;	2026 ; aucune ne tient de vecteur au repos.
	mv	a,dvname-btop
	add	x,a
	mv	y,dvname		;	'L:',0 de l'image
	mv	il,3
	call	compare
	jrnz	un_autre

;	Aucun pilote AU-DESSUS du notre. Le KILL de PLINK.SYS ferait descendre
;	tous les blocs suivants SANS relocation : sans dommage pour TEXT.BAS et
;	DATA.BAS (la ROM les recale), fatal pour un autre pilote (mesure du
;	2026-09-25 avec BASEXT.SYS au-dessus : la machine tombe). Meme regle de
;	reconnaissance que l'installateur : signature $fb et bits $0c de
;	l'attribut.
	mv	x,(dest)
un_sup:	mv	y,[x+$11]
	add	x,y
	mv	a,[x]
	cmp	a,$fb
	jrnz	un_delier		;	Fin de chaine : rien au-dessus
	mv	a,[x+$0c]
	test	a,$0c
	jrz	un_sup
	mv	(bottom),x
	mv	x,sup_m
	mv	y,sup_e-sup_m
	call	puts
	mv	x,(bottom)
	inc	x			;	Nom 8.3 du pilote fautif (11 octets)
	mv	y,11
	call	puts
	mv	x,sup2_m
	mv	y,sup2_e-sup2_m
	jr	un_fin

;	Delier notre en-tete IOCS (bloc + ihead-btop), s'il est encore chaine
un_delier:
	mv	x,(dest)
	mv	a,ihead-btop
	add	x,a
	mv	(bottom),x		;	Notre en-tete
	mv	y,d_link
un_lnk:	mv	x,[y]
	inc	x
	jrz	un_ok			;	$fffff : fin de chaine, plus chaine
	dec	x
	jrz	un_ok			;	0 : chaine vide
	mv	(offset),y		;	Emplacement du lien qui designe x
	mv	(mdf),x
	mv	y,(bottom)
	cmpp	(mdf),y
	jrz	un_trouve
	mv	y,x			;	Le lien suivant est le 1er champ de l'en-tete
	jr	un_lnk
un_trouve:
	mv	x,[x]			;	Notre successeur...
	mv	y,(offset)
	mv	[y],x			;	...prend notre place
un_ok:	mv	x,uok_m
	mv	y,uok_e-uok_m
un_fin:	call	puts
	jp	fin

un_absent:
	mv	x,abs_m
	mv	y,abs_e-abs_m
	jr	un_fin
un_autre:
	mv	x,oth_m
	mv	y,oth_e-oth_m
	jr	un_fin

;	compare : IL octets de [x] et de [y] ; Z si identiques
compare:	mv	(mdf),[x++]
	mv	a,[y++]
	cmp	(mdf),a
	jrnz	compare_e
	dec	il
	jrnz	compare
compare_e:	ret

title:	db	'PLINKC ver 1.62 by Daisuke Mizobata',$0d,$0a
	db	'based on PLINK ver 1.04 by N.Kon',$0d,$0a
	db	'Update '
	drvrev
	db	' by J-F.Albouy',$0d,$0a
title_e:

;	Messages de la desinstallation (affiches par puts : X, Y = longueur)
uok_m:	db	'Uninstalled. To free memory :',$0d,$0a
sk_m:	db	'SET  "S1:PLINK.SYS"," "',$0d,$0a
	db	'KILL "S1:PLINK.SYS"',$0d,$0a
sk_e:
uok_e:

;	Messages de « deja installe » (2026)
etat:	db	'L:?',0			;	Argument d'INIT : etat du pilote installe
exo_m:	db	'Already exists (other version).',$0d,$0a
exo_e:
exu_m:	db	'PLINK.SYS in S1: but not linked.',$0d,$0a
	db	'Free it, then install again :',$0d,$0a
exu_e:
exl_m:	db	'Error: L: used by another driver.',$0d,$0a
exl_e:
abs_m:	db	'PLINK.SYS not in S1:.',$0d,$0a
abs_e:
oth_m:	db	'Error: PLINK.SYS without L: header.',$0d,$0a
oth_e:
sup_m:	db	'Error: driver above PLINK.SYS :',$0d,$0a
sup_e:
sup2_m:	db	$0d,$0a,'Uninstall it first.',$0d,$0a
sup2_e:

;	Messages de l'installation (affiches par putm2 : IL = ecart depuis mb,
;	1er octet = longueur ; la table doit tenir sous 256 octets)
mb:
exi_m:	db	17,'Already exists.',$0d,$0a
mem_m:	db	20,'Not enough memory.',$0d,$0a
ins_m:	db	12,'Installed.',$0d,$0a
pg_m:	db	17,'Over two pages.',$0d,$0a

;----------------------------------------------------------------------
;		En-tete du fichier d'en-tete de l'appareil
;----------------------------------------------------------------------
btop:	db	$fb,'PLINK   SYS'		;Nom du bloc de peripherique
		db	$25						;Attributs de bloc de memoire
		dw	0,0						;Date et heure
		dp	blen					;Nombre d'octets dans le bloc memoire
		dw	0
		dp	blen					;Nombre d'octets de l'entite de fichier
		dp	blen					;Nombre d'octets dans le bloc memoire
		dp	0,0
;----------------------------------------------------------------------
;		En-tete du pilote de peripherique
;----------------------------------------------------------------------
ihead:		dp	0			;Adresse du prochain en-tete de pilote de peripherique
devno:		db	0			;Numero d'appareil (variable)
		db	$83				;Attribut de peripherique (identique a E :)
		rel dp	devmain		;Adresse du corps du pilote de peripherique
dvname:		db	'L:',0		;Nom de l'appareil
;----------------------------------------------------------------------
;		Media parameter block
;----------------------------------------------------------------------
;Version de 128 Ko
mpb128:		db	$f0			;Descripteur de media (peut etre approprie)
		dw	sectsiz			;Nombre d'octets par secteur
		db	4-1				;(Nombre d'octets par secteur / 32) -1
		db	2				;log 2 (nombre d'octets par secteur / 32)
		db	0				;???
		db	1				;???
		dw	0				;Premier numero de secteur de zone FAT
		db	8				;???
		dw	128				;Nombre maximum de fichiers stockables
		dw	dtop			;Numero du secteur de depart de la zone de donnees
		dw	980+1			;Nombre total de secteurs dans la zone de donnees + 1
		db	12				;Nombre total de secteurs dans la zone FAT
		dw	12				;Premier numero de secteur de la zone DIR
;Donnees referencees dans DS
		dw	12				;Premier numero de secteur de la zone DIR
;Version de 512 Ko
mpb512:		db	$f0
		dw	sectsiz
		db	4-1
		db	2
		db	0
		db	1
		dw	0
		db	8
		dw	128
		dw	80			;Numero du secteur de depart de la zone de donnees
		dw	4016+1		;Nombre total de secteurs dans la zone de donnees + 1
		db	48			;Nombre total de secteurs dans la zone FAT
		dw	48			;Premier numero de secteur de la zone DIR
;
		dw	48
;Version de 256 Ko (ajout 2026). Meme regle que les deux autres : FAT,
;puis 32 secteurs de repertoire (128 fichiers), puis les donnees, pour
;256K/128 = 2048 secteurs : 24 + 32 + 1992. FAT de 12 bits : 24 secteurs
;= 2048 entrees >= 1992+2. Doit egaler set_geometry('2') d'APLINKS 1.07.
mpb256:		db	$f0
		dw	sectsiz
		db	4-1
		db	2
		db	0
		db	1
		dw	0
		db	8
		dw	128
		dw	56			;Numero du secteur de depart de la zone de donnees
		dw	1992+1		;Nombre total de secteurs dans la zone de donnees + 1
		db	24			;Nombre total de secteurs dans la zone FAT
		dw	24			;Premier numero de secteur de la zone DIR
;
		dw	24
;----------------------------------------------------------------------
;		Corps
;----------------------------------------------------------------------
suborg		0
byte		i_work1,i_work2
word		sect_num,sect_num2
byte		flag,rxdata,i_work3,subko
pntr		cachep,vct_rsv,before
devmain:	pushu	imr				;Arretez l'interruption et reecrivez le vecteur de reception SIO
		pushu	x
		pre	$30
		sub	(bp_ram),%
		mv	x,[intv_sio_rx]
		mv	(vct_rsv),x	
		rel mv	x,rcv
		mv	[intv_sio_rx],x
		popu	x
		popu	imr
		mv	(i_work3),[sio_baud]   ;Charger les parametres
		and	(i_work3),$fd	   		;Ce force a 8 bits
		pre	$22
		ex	(i_work3),(ucr);Parametrage de la SIO & conservation du contenu precedent
		pre	$22
		mv	(subko),(koh)	;Enregistrer KOH
		pre	$30
		or	(koh),$60		;Activer DTR, RR
;
		bsr	main
;
		{
			pre	$30
			test	(usr),$10
			jrz	continue				;Attendre la fin de la transmission
		}
		pre	$30
		mv	(ucr),(i_work3)	;Restaurer le parametre SIO
		pre	$30
		mv	(koh),(subko)		;Restaurer KOH
		test	(flag),2
		jrz	jump00						;[BRK] a ete presse?
		mv	a,$02
		jrc	jump00
brkloop:	test	[softint],$80		;Attendez que la pause soit liberee
		jrnz	brkloop
		mv	a,$ff						;Traitement en cas de pression
		sc
jump00:		pushu	imr					;Restaurer le vecteur de reception SIO
		pushu	x
		mv	x,(vct_rsv)
		mv	[intv_sio_rx],x
		pre	$30
		pmdf	(bp_ram),%
		popu	x
		popu	imr
		retf
;----------------------------------------------------------------------
;		Diverses commandes
;----------------------------------------------------------------------
;----------------------------------------------------------------------
;		INIT "L:?" : etat du pilote (ajout 2026)
;----------------------------------------------------------------------
;	Affiche 'L: 128K, device 10, block &80018'. Rien n'est envoye au
;	serveur et les tampons ne sont pas touches (pas de buffer_clr).
st_l:		db	'L: '
st_l_e:
st_128:		db	'128K'
st_512:		db	'512K'
st_256:		db	'256K'
st_no256:	db	'No 256K reply from server: 128K.',$0d,$0a
st_no256_e:
st_srv:		db	'Server mode: '
st_srv_e:
st_unk:		db	'Unknown INIT option. Help: INIT "L:H"',$0d,$0a
st_unk_e:
;	INIT "L:H" : la taille du bloc est ecrite en decimal A L'ASSEMBLAGE
;	(blen est une constante ; % entre deux valeurs = modulo). PARENTHESES
;	OBLIGATOIRES : le modulo lie MOINS fort que '+' dans ce langage (comme
;	oprlevel_set du moteur C), donc '0'+blen%10 vaudrait ('0'+blen)%10.
st_ver:		db	'PLINKC 1.62-'
		drvrev
		db	', '
		db	'0'+(blen/1000),'0'+((blen/100)%10),'0'+((blen/10)%10),'0'+(blen%10)
		db	' bytes',$0d,$0a
st_ver_e:
st_cmd:		db	'INIT "L:x"  1/2/5 = 128K/256K/512K',$0d,$0a
		db	'D disc, I clear, ? state, H help [key]'	;SANS CR LF : voir help
st_cmd_e:
st_dev:		db	', device '
st_dev_e:
st_blk:		db	', block &'
st_blk_e:
st_crlf:	db	$0d,$0a
st_mode:	db	'1'				;Mode choisi par INIT "L:1"/"L:2"/"L:5"

;	cmd3f_set : adopter la geometrie X (mpb) pour le mode A ('1','2','5')
cmd3f_set:	rel mv	[st_mode],a
		rel mv	[getmpb+1],x
		mv	ba,[x+$c]
		rel mv	[secpatch+1],ba
		ret

;	st_puts : X = texte, Y = longueur, a l'ecran (handle 0)
st_puts:	pre	$30
		mv	(cl),0
		mv	il,fcs_write_block
		callf	fcs_call
		ret

;	st_dec : A en decimal, sans zero de tete
st_dec:		mv	(i_work1),a			;Reste a ecrire
		mv	(i_work2),0			;Aucun chiffre ecrit encore
		mv	a,100
		bsr	st_digit
		mv	a,10
		bsr	st_digit
		mv	(i_work2),1			;Les unites s'ecrivent toujours
		mv	a,1
st_digit:	mv	il,'0'
st_digit_1:	cmp	(i_work1),a
		jrc	st_digit_2			;Reste < poids
		sub	(i_work1),a
		inc	il
		jr	st_digit_1
st_digit_2:	mv	a,il
		cmp	a,'0'
		jrnz	st_digit_3
		test	(i_work2),1
		jrz	st_ret				;Zero de tete : pas ecrit
st_digit_3:	mv	(i_work2),1
;	st_putc : A a l'ecran (handle 0)
st_putc:	pre	$30
		mv	(cl),0
		mv	il,fcs_write_byte
		callf	fcs_call
st_ret:		ret

;	st_hex5 : X en hexadecimal sur 5 chiffres
st_hex5:	mv	(before),x
		mv	a,(before+2)
		bsr	st_nib
		mv	a,(before+1)
		bsr	st_hex2
		mv	a,(before)
st_hex2:	pushu	a
		swap	a
		bsr	st_nib
		popu	a
st_nib:		and	a,$0f
		add	a,'0'
		cmp	a,'9'+1
		jrc	st_putc
		add	a,'A'-'9'-1
		jr	st_putc

;	st_pmode : le mode retenu, '128K', '256K' ou '512K'
st_pmode:	rel mv	x,st_128
		rel mv	a,[st_mode]
		cmp	a,'5'
		jrnz	st_pmode_0
		rel mv	x,st_512
st_pmode_0:	cmp	a,'2'
		jrnz	st_pmode_1
		rel mv	x,st_256
st_pmode_1:	mv	y,4
		bsr	st_puts
		ret

;----------------------------------------------------------------------
;		INIT "L:H" : version, taille, etat, commandes (ajout 2026)
;----------------------------------------------------------------------
help:		rel mv	x,st_ver
		mv	y,st_ver_e-st_ver
		bsr	st_puts
		bsr	status				;Mode, device, bloc
		rel mv	x,st_cmd
		mv	y,st_cmd_e-st_cmd
		bsr	st_puts
;	Attente d'une touche (2026-10-06). L'ecran a 4 lignes : la 4e est ecrite
;	SANS retour a la ligne, sinon l'ecran defilerait avant la pause et la
;	1re serait deja perdue. Tampon clavier vide d'abord (touche d'avance),
;	puis IOCS clavier 43h, a bit 7 = 1 : attente en basse consommation.
		pre	$30
		mv	(cl),dev_key
		pre	$30
		mv	(ch),0
		mv	il,d1_buffer_clear
		callf	iocs_call
		pre	$30
		mv	(cl),dev_key
		pre	$30
		mv	(ch),0
		mv	a,$80
		mv	il,d1_key_read
		callf	iocs_call
		rel mv	x,st_crlf
		mv	y,2
		bsr	st_puts
		rc
		ret

status:		rel mv	x,st_l
		mv	y,st_l_e-st_l
		bsr	st_puts
		bsr	st_pmode
		rel mv	x,st_dev
		mv	y,st_dev_e-st_dev
		bsr	st_puts
		rel mv	a,[devno]
		bsr	st_dec
		rel mv	x,st_blk
		mv	y,st_blk_e-st_blk
		bsr	st_puts
		rel mv	x,btop				;Adresse du bloc installe (relogee)
		bsr	st_hex5
		rel mv	x,st_crlf
		mv	y,2
		bsr	st_puts
		rc
		ret

init:		mv	a,[x]
		cmp	a,'a'				;Minuscule -> majuscule (ajout 2026)
		jrc	init_0
		cmp	a,'z'+1
		jrnc	init_0
		and	a,$df
init_0:		cmp	a,'?'
		jrz	status
		cmp	a,'H'
		jrz	help
		rel mv	x,mpb128
		cmp	a,'1'
		jrz	cmd3f_15
		rel mv	x,mpb256			;256K : ajout 2026
		cmp	a,'2'
		jrz	cmd3f_15
		rel mv	x,mpb512
		cmp	a,'5'
		jrnz	cmd3f_d
;	INIT "L:1", "L:2", "L:5" : comme la 1.62, 'S' puis le mode, sans reponse.
;	Puis (2026) 'Q' : le serveur rend le mode qu'il utilise REELLEMENT et on
;	l'adopte. Un serveur qui garde un disque precharge dans un autre mode
;	ferait sinon lire la FAT comme un repertoire, et demander des secteurs
;	absurdes (APLINKS 1.06 en est tombe, le 2026-10-06). Sans reponse dans
;	le delai (APLINKS 1.06, DOS 1.03 : 'Q' ignore), on garde le mode
;	demande, comme la 1.62 - sauf 256K, que ces serveurs ne connaissent
;	pas : 128K (ce qu'ils font eux-memes d'un disque vide), et on le dit.
cmd3f_15:	mv	(i_work2),a			;Mode demande
		bsr	cmd3f_set			;Geometrie + mode retenu pour INIT "L:?"
		bsr	check_sect
		mv	a,'S'
		bsr	send_one
		mv	a,(i_work2)
		bsr	send_one
		mv	a,'Q'				;Quel mode utilises-tu ?
		bsr	send_one
		bsr	receive_one_s		;Attente bornee (timeout, ~1 s)
		test	(flag),2
		jrnz	cmd3f_q0			;Pas de reponse : serveur ancien
		rel mv	x,mpb512
		cmp	a,'5'
		jrz	cmd3f_q1
		rel mv	x,mpb256
		cmp	a,'2'
		jrz	cmd3f_q1
		rel mv	x,mpb128
		cmp	a,'1'
		jrnz	cmd3f_2				;Reponse inconnue : on garde
cmd3f_q1:	cmp	(i_work2),a
		jrz	cmd3f_2				;Le serveur est dans le mode demande
		bsr	cmd3f_set			;Sinon on adopte le sien...
		rel mv	x,st_srv			;...et on le dit
		mv	y,st_srv_e-st_srv
		bsr	st_puts
		bsr	st_pmode
		rel mv	x,st_crlf
		mv	y,2
		bsr	st_puts
		jr	cmd3f_2
cmd3f_q0:	and	(flag),$fd			;Pas une erreur de liaison : on continue
		mv	a,(i_work2)
		cmp	a,'2'
		jrnz	cmd3f_2				;128K ou 512K : on garde
		rel mv	x,st_no256
		mv	y,st_no256_e-st_no256
		bsr	st_puts
		mv	a,'1'
		rel mv	x,mpb128
		bsr	cmd3f_set
		jr	cmd3f_2
cmd3f_d:	cmp	a,'D'
		jrnz	cmd3f_i
		bsr	check_sect				;"D" commande
		mv	a,'D'
		bsr	send_one				;Envoyer la commande "D"
		mv	i,$12+(receive_one_s-receive_one-2)*$100
		rel mv	[receive_one],i		;jr receive_one_s
		jr	cmd3f_2
cmd3f_i:	cmp	a,'I'
		jrnz	cmd3f_x
		mv	il,130					;"Je" commande
		mv	a,0						;Envoyer 130 pieces de 00h
cmd3f_i1:	bsr	send_one
		dec	il
		jrnz	cmd3f_i1
		jr	cmd3f_2
;	Ni 1/2/5, ni D/I/?/H (ajout 2026). Option vide (INIT "L:", et l'appel de
;	l'installateur avec "L:",0) : comme la 1.62, vider le tampon. Lettre
;	inconnue : la 1.62 videait aussi le tampon, sans rien dire ; on le dit,
;	et on ne touche a rien.
cmd3f_x:	cmp	a,' '+1				;0, CR, 1Ah, espace... : option vide
		jrc	cmd3f_2
		cmp	a,$ff
		jrz	cmd3f_2
		rel mv	x,st_unk
		mv	y,st_unk_e-st_unk
		bsr	st_puts
		rc
		ret
cmd3f_2:	bsr	buffer_clr			;Nettoyer le tampon
		;bsr	root
		;ret

root:		bsr	getroot	
		mv	[x+$a],i
		mv	[x+$11],ba
		rc
		ret

getroot:	bsr	getmpb
		mv	ba,[x+$13]
		mv	il,128
		ret

getmpb:		rel mv	x,mpb128
		rc
		ret
;----------------------------------------------------------------------
;		Corps de chaque processus
;----------------------------------------------------------------------
main:		mv	(flag),0		;Effacer le drapeau
		mv	a,il				;Analyse de commande
		cmp	a,$10
		jrnz	cmd11
		rc						;Traitement de commande 10h
		ret
cmd11:		cmp	a,$11
		jrz	getmpb				;Traitement de la commande 11h
		cmp	a,$12
		jrz	read_sect			;Traitement de commande 12h
		cmp	a,$13
		jrz	write_sect			;Traitement de la commande 13h
		cmp	a,$14
		jrz	write_sect			;Traitement de la commande 14h
		cmp	a,$15
		jrz	read_sect			;Traitement de commande 15h
		cmp	a,$16
		jrnz	cmd17
		mv	ba,0				;Traitement de commande 16h
		rc
		ret
cmd17:		cmp	a,$17
		jrnz	cmd18
		rel mv	ba,[sect_number]	;Traitement de commande 17h
		pre	$30
		cmpw	(bl),ba
		jrz	same_sect				;c'etait le meme secteur que le tampon
		bsr	check_sect
		test	(flag),2
		jrnz	cmd17_err
		pre	$30
		mv	ba,(bl)
		rel mv	[sect_number],ba
		mv	(sect_num),ba
		rel mv	x,sect_1
		rel mv	y,sect_2		;Faire une copie
		mv	il,sectsiz/2+1
		bsr	rcv_sect			;Lire secteur specifie
		test	(flag),2
		jrz	same_sect
		mv	ba,-1
		rel mv	[sect_number],ba
		jr	cmd17_err
same_sect:	pre	$30
		mvw	(cl),sectsiz
		rel mv	x,sect_1
		rc
cmd17_err:	ret
cmd18:		cmp	a,$18
		jrz	getroot				;Traitement de la commande $ 18 (pour DS)	
cmd3f:		cmp	a,$3f
		jrnz	cmd40
		rel jp	init				;Traitement de la commande 3Fh (trop loin pour jrz depuis 2026)
cmd40:		cmp	a,$40
		jrz	root				;Traitement de commande 40h
cmd_err:	mv	a,3				;Commande invalide
		sc
		ret
;----------------------------------------------------------------------
;		Lecture continue de secteurs
;----------------------------------------------------------------------
read_sect:	pre	$22
		mvw	(sect_num),(bl)
		mv	y,x
		mv	il,sectsiz/2
		rel mv	ba,[sect_number]
		cmpw	(sect_num),ba    ;Secteurs tampons et
		jrnz	read_sect1	     ;Avez-vous frappe?
		rel mv	y,sect_1
read_sect2:	mv	ba,[y++]
		mv	[x++],ba
		dec	il
		jrnz	read_sect2
		jr	read_sect3
read_sect1:	bsr	rcv_sect
		test	(flag),2
		jrnz	read_err
read_sect3:	pre	$30
		mv	ba,(bl)
		inc	ba
		pre	$30
		mv	(bl),ba
		pre	$30
		mv	ba,(dl)
		dec	ba
		pre	$30
		mv	(dl),ba
		jrnz	read_sect
		rc
read_err:	ret
;----------------------------------------------------------------------
;		Ecriture continue de secteurs
;----------------------------------------------------------------------
write_sect:	pre	$22
		mvw	(sect_num),(bl)
		mv	il,sectsiz
		rel mv	ba,[sect_number]
		cmpw	(sect_num),ba    ;Secteurs tampons et
		jrnz	write_sect1	     ;Avez-vous frappe?
		rel mv	y,sect_1
write_sect2:	mv	a,[x++]
		mv	[y++],a
		dec	il
		jrnz	write_sect2
		jr	write_sect3
write_sect1:	bsr	send_sect
		test	(flag),2
		jrnz	write_err
write_sect3:	pre	$30
		mv	ba,(bl)
		inc	ba
		pre	$30
		mv	(bl),ba
		pre	$30
		mv	ba,(dl)
		dec	ba
		pre	$30
		mv	(dl),ba
		jrnz	write_sect
		rc
write_err:	ret
;----------------------------------------------------------------------
;		Transmission a un secteur
;----------------------------------------------------------------------
send_sect:	pushu	il
		bsr	send_cache	;Traitement CACHE
		popu	il
		pushu	imr
		pre	$30
		mv	(imr),$a0
		mv	y,(cachep)
		pushu	y
send_sect_2:	mv	a,[x++]
		mv	[y++],a		;Ecrivez a CACHE
		dec	il
		jrnz	send_sect_2
		mv	a,'W'
		bsr	send_one			;Envoyer la commande a ecrire
		mv	a,(sect_num)
		bsr	send_one			;Transmission inferieure a 1 octet du numero de secteur
		mv	a,(sect_num+1)
		bsr	send_one			;Envoi du 1 octet superieur du numero de secteur
		popu	y
		mv	il,sectsiz+1
send_sect_3:	mv	a,[y++]
		bsr	send_one			;Envoi de 129 octets de donnees CACHE
		dec	il
		jrnz	send_sect_3
		mv	a,$ff
		bsr	send_one			;Envoyer une marque de terminaison normale
		bsr	receive_one
		test	(flag),2
		jrz	send_ok
		mv	ba,-1
		mv	[y],ba				;Invalider le cache mis en cache
send_ok:	popu	imr
		ret
;----------------------------------------------------------------------
;		Reception 1 secteur
;----------------------------------------------------------------------
rcv_sect:	pushu	imr
		pushu	il
		pre	$30
		mv	(imr),$a0
		bsr	send_cache			;Traitement CACHE
		popu	il
		jrnc	read_cache		;Sautez quand vous pouvez lire de CACHE
		pushu	il
		pushu	x
		mv	x,(cachep)			;Charger dans CACHE
		mv	a,'R'
		bsr	send_one			;Envoyer une commande de lecture
		mv	a,(sect_num)
		bsr	send_one			;Transmission inferieure a 1 octet du numero de secteur
		mv	a,(sect_num+1)
		bsr	send_one			;Envoi du 1 octet superieur du numero de secteur
		rc
		bsr	receive_one			;(Taille du secteur + 1) reception octet
		jrc	rcv_sect_2
		mv	[x++],a
		mv	il,sectsiz
rcv_sect_1:	bsr	receive_one
		mv	[x++],a
		dec	il
		jrnz	rcv_sect_1
rcv_sect_2:	popu	x
		popu	il
read_cache:	mv	[--s],u			;Lire de CACHE
		mv	u,(cachep)
		test	(flag),2
		jrz	read_cache_1
		mv	ba,-1
		mv	[u+cache_sect],ba;Invalider le cache entrant
		jr	rcv_err
read_cache_1:	popu	ba		;mv	ba,[u++]
		mv	[x++],ba
		mv	[y++],ba
		dec	il
		jrnz	read_cache_1
rcv_err:	mv	u,[s++]
		popu	imr
		ret
;----------------------------------------------------------------------
;		Transmission sur 1 octet
;----------------------------------------------------------------------
send_one:	pre	$30
		test	(usr),$8
		jrz	send_one			;Attendez qu'il soit pret pour Tx
		test	(flag),2
		jrz	send_one_2			;En mode d'arret de la transmission, 00h est transmis
		mv	a,0
send_one_2:	pre	$30
		mv	(txd),a		;Envoyer
		ret
;----------------------------------------------------------------------
;		Recevez 1 octet
;----------------------------------------------------------------------
receive_one:	jr	receive_one_s
		db	ssr,8
;		test	(ssr),8
		jrnz	receive_one_err	;[BRK] a ete presse
		test	(flag),1
		jrz	receive_one			;Attendez qu'un octet soit recu
		mv	a,(rxdata)
		and	(flag),$fe			;Reinitialiser le drapeau
		ret
receive_one_s:	mv	ba,timeout
receive_one_lp:	pre	$30			;1
		test	(ssr),8	;4
		jrnz	receive_one_err		;2
		test	(flag),1		;4
		jrnz	receive_one_ok		;2
		dec	ba			;3
		jrnz	receive_one_lp		;3
		sc
receive_one_err:or	(flag),2	;Definir le mode d'arret de la transmission
		ret
receive_one_ok:	mv	ba,$6530	;pre $30 test (m),n
		rel mv	[receive_one],ba
		mv	a,(rxdata)
		and	(flag),$fe			;Reinitialiser le drapeau
		ret
;----------------------------------------------------------------------
;		Recevez une routine de traitement des interruptions
;----------------------------------------------------------------------
rcv:		pre	$30
		mv	a,(rxd)
		mv	(rxdata),a
		or	(flag),1			;Definir le drapeau de reception complete
		retf
;----------------------------------------------------------------------
;		Tampon clair
;----------------------------------------------------------------------
buffer_clr:	mv	il,sectsiz+2
		mv	ba,0
		rel mv	x,sect_1
buffer_clr_1:	mv	[x++],ba	;Remplir le tampon avec 00h
		dec	i
		jrnz	buffer_clr_1
		mv	ba,-1
		rel mv	[sect_number],ba	;Initialisation du numero de secteur
		mv	il,n_fcache
		rel mv	y,fcache
		rel mv	[fcachep],y
		bsr	buffer_clr_3		;Initialisation du cache FAT
		mv	il,n_dcache
		rel mv	y,dcache
		rel mv	[dcachep],y
		bsr	buffer_clr_3		;Initialisation du cache de donnees
		ret

buffer_clr_3:	mv	x,y
		mv	[x+cache_sect],ba
		dec	il
		jrz	buffer_clr_2
		mv	ba,cache_size
		add	y,ba
		mv	[x+cache_next],y
		jr	buffer_clr_3
buffer_clr_2:	mv	y,$fffff
		mv	[x+cache_next],y
		ret
;----------------------------------------------------------------------
;		Verification de la correspondance du tampon pour la commande $ 17
;----------------------------------------------------------------------
check_sect:	rel mv	x,sect_1
		mv	il,sectsiz+1
check_sect_3:	mv	(i_work1),[x++]
		mv	a,[x+sectsiz+1]
		cmp	(i_work1),a			;Comparaison du contenu de la memoire tampon
		jrnz	check_sect_4
		dec	il
		jrnz	check_sect_3
		ret
check_sect_4:
		rel mvw	(sect_num),[sect_number]
		rel mv	x,sect_1
		mv	il,sectsiz+1
		pushu	x
		bsr	send_sect			;Pour expulser le tampon
		popu	x
		mv	ba,(sect_num)
		inc	ba
		mv	(sect_num),ba
		dec	ba
		dec	ba
		mv	(sect_num2),ba
		mv	y,(cachep)
check_sect_6:	mv	ba,[y+cache_sect]
		cmpw	(sect_num),ba
		jrnz	check_sect_5
		pushu	a
		mv	a,[x+sectsiz]
		mv	[y],a				;Le premier octet du secteur a cote du secteur accede
		popu	a
check_sect_5:	cmpw	(sect_num2),ba
		jrnz	check_sect_7
		mv	a,[x]
		mv	[y+sectsiz],a		;Le 129eme octet du secteur avant le secteur accede
check_sect_7:	mv	y,[y+cache_next]
		pushu	y
		inc	y
		popu	y
		jrnz	check_sect_6
		ret
;----------------------------------------------------------------------
;		Verification de la correspondance avec le cache
;----------------------------------------------------------------------
send_cache:
		pushu	x
		pushu	y
		rel mv	x,dcachep
secpatch:	mv	ba,dtop			;Le numero du secteur principal de la zone DATA est ecrit
		cmpw	(sect_num),ba
		jrnc	send_cache_0
		rel mv	x,fcachep
send_cache_0:	mv	(cachep),x
		mv	(before),x
		mv	x,[x]
send_cache_1:	mv	ba,[x+cache_sect]
		mv	y,[x+cache_next]
		cmpw	(sect_num),ba
		jrz	send_cache_2		;Le secteur auquel on a tente d'acceder est le meme que CACHE
		pushu	y
		inc	y
		popu	y
		sc						;Marquez qu'il ne peut pas etre lu de CACHE
		jrz	send_cache_2
		mv	a,cache_next
		add	x,a
		mv	(before),x
		mv	x,y
		jr	send_cache_1
send_cache_2:	mv	[(before)],y
		mv	y,[(cachep)]
		mv	[x+cache_next],y
		mvw	[x+cache_sect],(sect_num)
		mv	[(cachep)],x
		mv	(cachep),x
		popu	y
		popu	x
		ret

prgend:
;----------------------------------------------------------------------
;		Zone de travail
;----------------------------------------------------------------------
suborg		*
byte		sect_1[sectsiz+1+1],sect_2[sectsiz+1+1]
pntr		fcachep,dcachep
byte		fcache[cache_size*n_fcache]
byte		dcache[cache_size*n_dcache]
word		sect_number

blen:		equ	%-btop
blen_162:	equ	2336		;Taille du bloc de PLINKC 1.62 d'origine ("Already exists" la distingue)

;----------------------------------------------------------------------
;		Verifications a l'assemblage
;----------------------------------------------------------------------
		assert	entry = $bf000,'entry hors de l''org : relocation faussee'
		assert	ihead-btop = $22,'en-tete IOCS hors de bloc+22h'
		assert	dvname-btop = $2a,'nom de device hors de bloc+2Ah (-U le cherche la)'
		assert	pg_m-mb < 256,'table mb au-dela de 256 octets (IL)'
		assert	blen < 10000,'blen sur plus de 4 chiffres : st_ver ne l''ecrit pas'
		assert	blen <> blen_162,'blen = blen_162 : ambigu pour -U et pour Already exists'
		end
