;----------------------------------------------------------------------
;
;	Pocket Link System Device Driver Ver. 1.04
;	Installation program
;	for PC-E500 series pocket computer
;	Copyright (c) 1990,93,94 N.Kon
;
;	Usage: CALL &BF000
;
;	Last change: Mar. 26th
;
;----------------------------------------------------------------------
;
		pre_on
;
		org	$bf000
;----------------------------------------------------------------------
;		各種数値定義
;----------------------------------------------------------------------
fcntl_entry:	equ	$fffe4
iocs_entry:	equ	$fffe8
iocs_fook:	equ	$bfca2
sio_rcv_vct:	equ	$bfcd5
sio_param:	equ	$bfd33
i_work1:	equ	0
i_work2:	equ	1
sect_num:	equ	2
flag:		equ	4
rxdata:		equ	5
i_work3:	equ	6
vct_rsv:	equ	7
base:		equ	$ec
bx:		equ	$d4
cx:		equ	$d6
cl:		equ	$d6
ch:		equ	$d7
dx:		equ	$d8
key_strobe_2:	equ	$f1
sio_ctrl_reg:	equ	$f7
sio_stat_reg:	equ	$f8
sio_rx_reg:	equ	$f9
sio_tx_reg:	equ	$fa
intr_mask_reg:	equ	$fb
system_stat_reg:equ	$ff
basic_work:	equ	$bfd0e
top_of_slot0:	equ	$bfc15
top_of_slot1:	equ	$bfc0f
top_of_slot2:	equ	$bfc09
size_of_slot1:	equ	$bfc12
size_of_slot2:	equ	$bfc0c
end_of_slot0:	equ	$bfcde
;----------------------------------------------------------------------
;		インストール
;----------------------------------------------------------------------
		mv	x,msg0			;オープニングメッセージ出力
		mv	y,btm0-msg0
		mv	(cl),0
		mv	il,4
		callf	fcntl_entry
;
		mv	(cl),'1'		;どのメモリ・スロットにインストールするのかを決める
		popu	x
inst_loop1:	mv	a,[x]
		cmp	a,$0d
		jrz	inst_memory
		mv	(cl),a
		inc	x
		jr	inst_loop1
inst_memory:	pushu	x
		mv	a,(cl)
		cmp	a,'1'
		jrc	default
		cmp	a,'3'+1
		jrnc	default
		sub	a,'1'
		jr	compress
default:	mv	a,0
compress:	mv	[memory_slot],a
		mv	(cl),6			;メモリ圧縮
		mv	(ch),a
		mv	il,$47
		callf	iocs_entry
;
		call	get_slot_top
		mv	y,[x+$12]
		add	x,y
		mv	(10),x
;
init_1:		mv	a,[x]			;デバイスドライバ最後尾を検索
		cmp	a,0fbh
		jrnz	block_end
		mv	y,block_top
		mv	il,12
		pushu	x
		callf	stricmp
		popu	x
		jpz	exit2			;すでにPLINKが存在している
		mv	a,[x+12]
		test	a,0ch			;常駐システムファイル属性のチェック
		jrz	set_start
		mv	y,[x+11h]
		add	x,y
		jr	init_1
set_start:	mv	(10),x
init_2:		mv	a,[x]			;メモリブロック最後尾を検索
		cmp	a,$ff
		jrz	block_end
		mv	y,[x+$11]
		add	x,y
		jr	init_2
block_end:	mv	(13),x
		pushu	x
		mv	a,[!memory_slot]		;インストール先のメモリ・スロットの終了アドレスを求める
		cmp	a,1
		mv	x,[!top_of_slot1]
		mv	ba,[!size_of_slot1]
		jrz	inst_not_slot0
		mv	x,[!top_of_slot2]
		mv	ba,[!size_of_slot2]
		jrnc	inst_not_slot0
		mv	x,[!end_of_slot0]
		jr	inst_block_end
inst_not_slot0:	mv	il,11
		mv	y,ba
inst_mult_2048:	add	y,y
		dec	il
		jrnz	inst_mult_2048
		add	x,y
inst_block_end:	mv	y,x
		popu	x
		dec	y
		sub	y,x
		mv	(16),y
		mv	y,block_bottom - block_top
		mv	x,(10)			;デバイスドライバ最終アドレスを求める
		add	x,y
		mv	(cl),x
		cmp	(cl+2),(10+2)		;先頭と最終のページを比較
		jrnz	exit5			;異なるページにまたがっている
		cmpp	(16),y
		jrc	exit3			;必要なメモリが確保できなかったらメニューへ飛ぶ
;
		mv	x,[iocs_fook]		;デバイスリンクに組み込む
		mv	[header],x
		mv	x,(10)
		mv	il,$22
		add	x,il
		mv	[iocs_fook],x
;
		mv	x,modify_table		;３バイト系のアドレス補正を行なう
init_3:		mv	y,[x++]
		inc	y
		jrz	modify2
		pushu	x
		mv	x,[y]
		pushu	y
		mv	y,block_top
		sub	x,y
		mv	y,(10)
		add	x,y
		popu	y
		mv	[y],x
		popu	x
		jr	init_3
;
modify2:	mv	x,modify_table2		;２バイト系のアドレス補正を行なう
mod_loop2:	mv	y,[x++]
		inc	y
		jrz	modify_end
		mv	ba,[y]
		mv	i,block_top
		sub	ba,i
		mv	i,(10)
		add	ba,i
		mv	[y],ba
		jr	mod_loop2
modify_end:	mv	x,(13)
		mv	y,(10)
		sub	x,y
		mv	(16),x
		mv	x,(13)
		mv	y,x
		mv	ba,block_bottom - block_top
		add	y,ba
		inc	x
		inc	y
		mv	a,1
;
init_6:		mv	il,[--x]		;メモリブロックを後方へずらす
		mv	[--y],il
		sub	(16),a
		jrnc	init_6
		sub	(17),a
		jrnc	init_6
		sub	(18),a
		jrnc	init_6
;
		mv	i,block_bottom - block_top
		mv	y,(10)
		mv	x,block_top
init_5:		mv	a,[x++]			;デバイスドライバを転送する
		mv	[y++],a
		dec	i
		jrnz	init_5
;
;;;;;;;;;;; KNJSCRN より拝借！
;
exit1:		mv	x,msg1		;DISPLAY "SUCCESS" MESSAGE
		mv	y,btm1-msg1
		jr	exit4
;
exit2:		mv	x,msg2		;DISPLAY "EXIST ERROR" MESSAGE
		mv	y,btm2-msg2
		jr	exit4
;
exit3:		mv	x,msg3		;DISPLAY "MEMORY ERROR" MESSAGE
		mv	y,btm3-msg3
		jr	exit4
;
exit5:		mv	x,msg5		;DISPLAY "BRIDGED OVER" MESSAGE
		mv	y,btm5-msg5
;
exit4:		mv	(cl),0
		mv	il,4
		callf	fcntl_entry
remake_slot:	mv	x,[basic_work]	;BASIC WORK Address
		mv	a,[x+72h]
		mv	[memory_slot],a
;
remake_text:	mv	y,73h
		add	y,x		;BTEXT$ Address
		pushu	y
		call	get_slot_top	;[memory_slot]で示されるメモリ・スロットの先頭アドレスを求める
		mv	y,[x+12h]
		add	x,y
		popu	y
text1:		mv	a,[x]		;SEARCH  block 'TEXT.BAS'
		cmp	a,0fbh
		jrnz	text_err
		mv	il,11
		pushu	y
		pushu	x
		inc	x
		callf	stricmp
		popu	x
		jrz	text2
		mv	y,[x+11h]
		add	x,y		;next block
		popu	y
		jr	text1
text2:		popu	y
		mv	(0cbh),x	;set "TEXT.BAS"  Address
;
remake_data:	mv	x,[basic_work]	;BASIC WORK Address
		mv	a,[x+7eh]
		mv	[memory_slot],a
;
		mv	y,7fh		;BDATA$ Address
		add	y,x
		pushu	y
		call	get_slot_top
		mv	y,[x+12h]
		add	x,y
		popu	y
data1:		mv	a,[x]		;SEARCH  block 'DATA.BAS'
		cmp	a,0fbh
		jrnz	data_err
		mv	il,11
		pushu	y
		pushu	x
		inc	x
		callf	stricmp
		popu	x
		jrz	data2
		mv	y,[x+11h]
		add	x,y		;next block
		popu	y
		jr	data1
data2:		popu	y
		mv	(0ceh),x	;set "DATA.BAS"  Address
remake_end:	rc
		retf
;
text_err:				;remake failed. fatal error
data_err:	mv	x,msg4		;"Fatal error:"
		mv	y,btm4-msg4
		mv	(cl),0
		mv	il,4
		callf	fcntl_entry
;
		pushu	imr
kw1:		mv	(0f0h),$ff	;KEY WAIT   until any key
		and	(0f1h),$f8
		nop
		nop
		mv	a,($f2)
		cmp	a,$00		;no key ??
		jrz	kw1
		mv	(0f0h),$00
		and	(0f1h),$f8
		popu	imr
;
		mv	x,[0ffffdh]	;jmp to MENU
		jp	x
;
msg0:	db	'PLINK Ver. 1.04 (C)1990,93,94 N.Kon',13,10,'Installing...'
btm0:
msg1:	db	'done.',13,10
btm1:
msg2:	db	'error!',13,10,'PLINK already exist.',13,10
btm2:
msg3:	db	'error!',13,10,'Not enough memory.',13,10
btm3:
msg5:	db	'error!',13,10,'Bridged over between different pages.',13,10
btm5:
msg4:	db	'fatal error. HELP!!',13,10,'Push any key to reboot.',13,10
btm4:
stricmp:	mv	(0),[x++]	;compare string (length = IL bytes )
		mv	a,[y++]
		cmp	(0),0
		jrz	stricmp1
		cmp	(0),a
		jrnz	stricmp2
		dec	il
		jrnz	stricmp
		retf
stricmp1:	cmp	(0),a
stricmp2:	retf
;;;;;;;;;;;　ここまで
get_slot_top:	mv	a,[memory_slot]		;インストール先のメモリ・スロットの先頭アドレスを求める
		mv	x,[top_of_slot0]
		cmp	a,0
		jrz	inst_1
		mv	x,[top_of_slot1]
		cmp	a,1
		jrz	inst_1
		mv	x,[top_of_slot2]
inst_1:		ret
memory_slot:	ds	1
;----------------------------------------------------------------------
;		デバイスドライバのファイルヘッダ
;----------------------------------------------------------------------
block_top:	db	$fb,'PLINK   SYS'	;デバイスブロック名
		db	$25			;メモリブロックの属性
		dw	0,0			;日付と時間
		dp	block_bottom - block_top;メモリブロックのバイト数
		dw	0
		dp	block_bottom - block_top;ファイル実体のバイト数
		dp	block_bottom - block_top;メモリブロックのバイト数
		dp	0,0
;----------------------------------------------------------------------
;		デバイスドライバのヘッダ
;----------------------------------------------------------------------
header:		ds	3		;次のデバイスドライバヘッダのアドレス
		db	10		;デバイスナンバ
		db	$83		;デバイスの属性（Ｅ：と同じ）
modify_top:	dp	entry		;デバイスドライバ本体のアドレス
		db	'L:',0		;デバイス名
;----------------------------------------------------------------------
;		Media parameter block
;----------------------------------------------------------------------
mpb:		db	$f0		;メディアディスクリプタ（適当でよい）
		dw	128		;１セクタのバイト数
		db	4-1		;(１セクタのバイト数/32) -1
		db	2		;log2 (１セクタのバイト数/32)
		db	0		;???
		db	1		;???
		dw	0		;ＦＡＴエリアの先頭セクタ番号
		db	8		;???
		dw	128		;最大収容可能ファイル数
		dw	44		;ＤＡＴＡエリアの先頭セクタ番号
		dw	980+1		;ＤＡＴＡエリアの総セクタ数+1
		db	12		;ＦＡＴエリアの総セクタ数
		dw	12		;ＤＩＲエリアの先頭セクタ番号
;----------------------------------------------------------------------
;		本体
;----------------------------------------------------------------------
entry:		pushu	imr		;割り込みを止めてＳＩＯ受信ベクタを書き替える
		pushu	x
		pmdf	(base),$f0
		mv	x,[sio_rcv_vct]
		mv	(bp+vct_rsv),x	
mod_p000:	;********** Added by automatic address modifier
		mv	x,rcv
		mv	[sio_rcv_vct],x
		popu	x
		popu	imr
		mv	(bp+i_work3),[sio_param]   ;設定内容読み込み
		and	(bp+i_work3),$fd	   ;これで強制８ビット化
		ex	(bp+i_work3),(sio_ctrl_reg);ＳＩＯの設定＆以前の内容保存
		or	(key_strobe_2),$60		;ＤＴＲ、ＲＲをＯＮにする
;
mod_q000:	;********** Added by automatic address modifier
		call	main
;
		mv	(sio_ctrl_reg),(bp+i_work3)	;ＳＩＯパラメータを元に戻す
		test	(bp+flag),2
		jrz	jump00		;［ＢＲＫ］は押されていたか？
mod_q001:	;********** Added by automatic address modifier
		call	buffer_clr	;押されていたときの処理
		mv	a,$ff
		sc
jump00:		pushu	imr		;ＳＩＯ受信ベクタを元に戻す
		pushu	x
		mv	x,(bp+vct_rsv)
		mv	[sio_rcv_vct],x
		pmdf	(base),$10
		popu	x
		popu	imr
		retf
;----------------------------------------------------------------------
;		各処理の本体
;----------------------------------------------------------------------
main:		mv	(bp+flag),0	;フラグをクリアする
		mv	a,il		;コマンド解析
		cmp	a,$10
		jrnz	cmd11
		rc			;コマンド１０ｈの処理
		ret
cmd11:		cmp	a,$11
		jrnz	cmd12
		rc			;コマンド１１ｈの処理
mod_p001:	;********** Added by automatic address modifier
		mv	x,mpb
		ret
cmd12:		cmp	a,$12
		jrz	read_sect	;コマンド１２ｈの処理
		cmp	a,$13
		jrz	write_sect	;コマンド１３ｈの処理
		cmp	a,$14
		jrz	write_sect	;コマンド１４ｈの処理
		cmp	a,$15
		jrz	read_sect	;コマンド１５ｈの処理
		cmp	a,$16
		jrnz	cmd17
		mv	ba,0		;コマンド１６ｈの処理
		rc
		ret
cmd17:		cmp	a,$17
		jrnz	cmd3f
mod_p002:	;********** Added by automatic address modifier
		mv	ba,[sect_number]	;コマンド１７ｈの処理
		cmpw	(bx),ba
		jrz	same_sect	;バッファと同じセクタだった
mod_q002:	;********** Added by automatic address modifier
		call	check_sect
		mv	ba,(bx)
mod_p003:	;********** Added by automatic address modifier
		mv	[sect_number],ba
		mv	(bp+sect_num),ba
mod_p004:	;********** Added by automatic address modifier
		mv	x,sect_1
mod_p005:	;********** Added by automatic address modifier
		mv	y,sect_2	;コピーも作る
		mv	il,129
mod_q003:	;********** Added by automatic address modifier
		call	rcv_sect	;指定セクタを読み込む
same_sect:	mvw	(cx),128
mod_p006:	;********** Added by automatic address modifier
		mv	x,sect_1
		rc
		ret
cmd3f:		cmp	a,$3f
		jrnz	cmd40
		mv	a,[x]		;コマンド３Ｆｈの処理
		cmp	a,'D'
		jrnz	cmd3f_i
mod_q004:	;********** Added by automatic address modifier
		call	check_sect	;”Ｄ”コマンド
		mvw	(bp+sect_num),-1
mod_q005:	;********** Added by automatic address modifier
		call	send_cache	;ＣＡＣＨＥの中身を追い出す
		mv	a,'D'
mod_q006:	;********** Added by automatic address modifier
		call	send_one	;”Ｄ”コマンドを送る
mod_q007:	;********** Added by automatic address modifier
cmd3f_2:	call	buffer_clr	;バッファをきれいにする
		rc
		ret
cmd3f_i:	cmp	a,'I'
		jrnz	cmd3f_2
		mv	il,130		;”Ｉ”コマンド
		mv	a,0		;００ｈを１３０個送信する
mod_q008:	;********** Added by automatic address modifier
cmd3f_i1:	call	send_one
		dec	il
		jrnz	cmd3f_i1
		jr	cmd3f_2
cmd40:		cmp	a,$40
		jrnz	cmd_err
jump01:		rc			;コマンド４０ｈの処理
		ret
cmd_err:	mv	a,3		;無効なコマンド
		sc
		ret
;----------------------------------------------------------------------
;		セクタの連続読み込み
;----------------------------------------------------------------------
read_sect:	mvw	(bp+sect_num),(bx)
		mv	y,x
		mv	il,128
mod_p007:	;********** Added by automatic address modifier
		mv	ba,[sect_number]
		cmpw	(bp+sect_num),ba    ;バッファリングしているセクタと
		jrnz	read_sect1	    ;ヒットしたか？
mod_p008:	;********** Added by automatic address modifier
		mv	y,sect_1
read_sect2:	mv	a,[y++]
		mv	[x++],a
		dec	il
		jrnz	read_sect2
		jr	read_sect3
mod_q009:	;********** Added by automatic address modifier
read_sect1:	call	rcv_sect
read_sect3:	mv	ba,(bx)
		inc	ba
		mv	(bx),ba
		mv	ba,(dx)
		dec	ba
		mv	(dx),ba
		jrnz	read_sect
		rc
		ret
;----------------------------------------------------------------------
;		セクタの連続書き込み
;----------------------------------------------------------------------
write_sect:	mvw	(bp+sect_num),(bx)
		mv	il,128
mod_p009:	;********** Added by automatic address modifier
		mv	ba,[sect_number]
		cmpw	(bp+sect_num),ba    ;バッファリングしているセクタと
		jrnz	write_sect1	    ;ヒットしたか？
mod_p010:	;********** Added by automatic address modifier
		mv	y,sect_1
write_sect2:	mv	a,[x++]
		mv	[y++],a
		dec	il
		jrnz	write_sect2
		jr	write_sect3
mod_q010:	;********** Added by automatic address modifier
write_sect1:	call	send_sect
write_sect3:	mv	ba,(bx)
		inc	ba
		mv	(bx),ba
		mv	ba,(dx)
		dec	ba
		mv	(dx),ba
		jrnz	write_sect
		rc
		ret
;----------------------------------------------------------------------
;		１セクタ送信
;----------------------------------------------------------------------
send_sect:	pushu	il
mod_q011:	;********** Added by automatic address modifier
		call	send_cache	;ＣＡＣＨＥの処理
		popu	il
mod_p011:	;********** Added by automatic address modifier
		mv	y,cache
send_sect_2:	mv	a,[x++]		;ＣＡＣＨＥへ書き込む
		mv	[y++],a
		dec	il
		jrnz	send_sect_2
mod_p012:	;********** Added by automatic address modifier
		or	[cache_stat],$ff;かならず追い出しをすること
		ret
;----------------------------------------------------------------------
;		１セクタ受信
;----------------------------------------------------------------------
rcv_sect:	pushu	imr
		pushu	il
		mv	(intr_mask_reg),$a0
mod_q012:	;********** Added by automatic address modifier
		call	send_cache	;ＣＡＣＨＥの処理
		popu	il
		jrnc	read_cache	;ＣＡＣＨＥから読めばよいときジャンプ
		pushu	il
		pushu	x
mod_p013:	;********** Added by automatic address modifier
		mv	x,cache		;ＣＡＣＨＥに読み込む
		mv	a,'R'
mod_q013:	;********** Added by automatic address modifier
		call	send_one	;読みだしコマンド送信
		mv	a,(bp+sect_num)
mod_q014:	;********** Added by automatic address modifier
		call	send_one	;セクタ番号の下位１バイト送信
		mv	a,(bp+sect_num+1)
mod_q015:	;********** Added by automatic address modifier
		call	send_one	;セクタ番号の上位１バイト送信
		mv	il,129		;１２９バイト受信
mod_q016:	;********** Added by automatic address modifier
rcv_sect_1:	call	receive_one
		mv	[x++],a
		dec	il
		jrnz	rcv_sect_1
		popu	x
mod_p014:	;********** Added by automatic address modifier
		and	[cache_stat],0	;ＣＡＣＨＥは追い出さなくてよい
		popu	il
read_cache:	mv	[--s],u		;ＣＡＣＨＥから読み込む
mod_p015:	;********** Added by automatic address modifier
		mv	u,cache
read_cache_1:	mv	a,[u++]
		mv	[x++],a
		mv	[y++],a
		dec	il
		jrnz	read_cache_1
		mv	u,[s++]
		popu	imr
		ret
;----------------------------------------------------------------------
;		１バイト送信
;----------------------------------------------------------------------
send_one:	test	(sio_stat_reg),$8
		jrz	send_one	;Tx ready になるまで待つ
		test	(bp+flag),2
		jrz	send_one_2	;送信中止モードなら００ｈを送信することになる
		mv	a,0
send_one_2:	mv	(sio_tx_reg),a	;送信
		ret
;----------------------------------------------------------------------
;		１バイト受信
;----------------------------------------------------------------------
receive_one:	test	(system_stat_reg),8
		jrnz	receive_one_err	;［ＢＲＫ］が押された
		test	(bp+flag),1
		jrz	receive_one	;１バイト受信するまで待つ
		mv	a,(bp+rxdata)
		and	(bp+flag),$fe	;フラグをリセットする
		ret
receive_one_err:or	(bp+flag),2	;送信中止モードにする
		ret
;----------------------------------------------------------------------
;		受信割込み処理ルーチン
;----------------------------------------------------------------------
rcv:		mv	a,(sio_rx_reg)
		mv	(bp+rxdata),a
		or	(bp+flag),1	;受信完了フラグを立てる
		retf
;----------------------------------------------------------------------
;		バッファ・クリア
;----------------------------------------------------------------------
buffer_clr:	mv	il,129
		mv	ba,0
mod_p016:	;********** Added by automatic address modifier
		mv	x,sect_1
buffer_clr_1:	mv	[x++],ba	    ;バッファを００ｈで埋める
		dec	i
		jrnz	buffer_clr_1
		mv	i,-1
mod_p017:	;********** Added by automatic address modifier
		mv	[sect_number],i	    ;セクタ番号の初期化
mod_p018:	;********** Added by automatic address modifier
		mv	[cache_number],i    
		ret
;----------------------------------------------------------------------
;		コマンド17h用のバッファの一致検査
;----------------------------------------------------------------------
mod_p019:	;********** Added by automatic address modifier
check_sect:	mv	x,sect_1
		mv	il,129
check_sect_3:	mv	(bp+i_work1),[x++]
		mv	a,[x+128]
		cmp	(bp+i_work1),a	;バッファ内容の比較
		jrz	check_sect_4
mod_p020:	;********** Added by automatic address modifier
		mvw	(bp+sect_num),[sect_number]
mod_p021:	;********** Added by automatic address modifier
		mv	x,sect_1
		mv	il,129
mod_q017:	;********** Added by automatic address modifier
		call	send_sect	;バッファを追い出す
		mv	il,1
check_sect_4:	dec	il
		jrnz	check_sect_3
		ret
;----------------------------------------------------------------------
;		Cacheとの一致検査
;----------------------------------------------------------------------
send_cache:	pushu	imr
		mv	(intr_mask_reg),$a0
		pushu	x
mod_p022:	;********** Added by automatic address modifier
		mv	x,cache
mod_p023:	;********** Added by automatic address modifier
		mv	ba,[cache_number]
		mv	(bp+i_work1),ba
		cmpw	(bp+sect_num),ba
mod_p024:	;********** Added by automatic address modifier
		mvw	[cache_number],(bp+sect_num)
		jrz	no_read		;アクセスしようとしたセクタはＣＡＣＨＥと同じである
		inc	ba
		jrz	_read		;ＣＡＣＨＥは初期状態である
mod_p025:	;********** Added by automatic address modifier
		cmp	[cache_stat],0
		jrz	_read		;ＣＡＣＨＥを追い出す必要はない
		mv	a,'W'
mod_q018:	;********** Added by automatic address modifier
		call	send_one	;書き込むコマンド送信
		mv	a,(bp+i_work1)
mod_q019:	;********** Added by automatic address modifier
		call	send_one	;セクタ番号の下位１バイト送信
		mv	a,(bp+i_work2)
mod_q020:	;********** Added by automatic address modifier
		call	send_one	;セクタ番号の上位１バイト送信
		mv	il,129
send_cache_2:	mv	a,[x++]
mod_q021:	;********** Added by automatic address modifier
		call	send_one	;１２９バイトのＣＡＣＨＥデータを送信
		dec	il
		jrnz	send_cache_2
		mv	a,$ff
mod_q022:	;********** Added by automatic address modifier
		call	send_one	;正常終了の印を送信
mod_q023:	;********** Added by automatic address modifier
		call	receive_one
_read:		sc			;ＣＡＣＨＥからは読み込めないという印
send_cache_3:	popu	x
		popu	imr
		ret
no_read:	rc			;ＣＡＣＨＥから読み込んで宜しいという印
		jr	send_cache_3
;----------------------------------------------------------------------
;		ワークエリア
;----------------------------------------------------------------------
sect_1:		ds	129,0
sect_2:		ds	129,0
cache:		ds	129,0
sect_number:	dw	-1
cache_number:	dw	-1
cache_stat:	db	0
;
block_bottom:
;----------------------------------------------------------------------
;		アドレス補正テーブル
;----------------------------------------------------------------------
modify_table:	dp	modify_top - 1
;*** Automatic address modifier map list (3bytes)
		dp	!mod_p000
		dp	!mod_p001
		dp	!mod_p002
		dp	!mod_p003
		dp	!mod_p004
		dp	!mod_p005
		dp	!mod_p006
		dp	!mod_p007
		dp	!mod_p008
		dp	!mod_p009
		dp	!mod_p010
		dp	!mod_p011
		dp	!mod_p012
		dp	!mod_p013
		dp	!mod_p014
		dp	!mod_p015
		dp	!mod_p016
		dp	!mod_p017
		dp	!mod_p018
		dp	!mod_p019
		dp	!mod_p020 + 1
		dp	!mod_p021
		dp	!mod_p022
		dp	!mod_p023
		dp	!mod_p024
		dp	!mod_p025
		dp	-1
;*** Automatic address modifier map list (2bytes)
modify_table2:
		dp	!mod_q000
		dp	!mod_q001
		dp	!mod_q002
		dp	!mod_q003
		dp	!mod_q004
		dp	!mod_q005
		dp	!mod_q006
		dp	!mod_q007
		dp	!mod_q008
		dp	!mod_q009
		dp	!mod_q010
		dp	!mod_q011
		dp	!mod_q012
		dp	!mod_q013
		dp	!mod_q014
		dp	!mod_q015
		dp	!mod_q016
		dp	!mod_q017
		dp	!mod_q018
		dp	!mod_q019
		dp	!mod_q020
		dp	!mod_q021
		dp	!mod_q022
		dp	!mod_q023
		dp	-1
;
		end
