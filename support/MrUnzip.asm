; UNZIP.Z80
;
;	Dissolves MS-DOS ZIP files.
;
; Can be assembled with Z80asm from z88dk :
; 	z80asm -mz80 -b -m -l -r=0x7000 Mr_Unzip.asm
;	head -c 4736 Mr_Unzip.bin > Mr_Unzip.bin0
;	bin2cmd Mr_Unzip.bin0 7000 7000  
;
;
#define FASTQUIT 0	; Quit as soon as end of data section
#define CCPQUIT  0	; Returns to CCP instead of WARM

Vers:	equ	15
Revisn:	equ	7		;;v1.5-7
VersDD:	equ	22
VersMM:	equ	10
VersYY:	equ	2023

; Version MiSTer 1.0 : 10 december 2024 - theflynn49
;   	Port of this version for the TRS80 model I core found in MiSTer
;	- removed  all the options/parms mechanism
;	- removed imploding because it's too memory consuming
;	- replaced file-input by the core Cassette channel
;	- replaced all CPM disk I/O by calls to TRSDOS routines 
;
; Version 1.5-7 -- 22 October 2023 -- Stefano and Tony Nicholson
;	Some code size optimisations.
;
; Version 1.56 -- 27 August 2023 -- Jonathan Harston
;	Junks file paths when extracting.
;	Returns to caller instead of jumping to WARM.
;	Tidied up display. Added [Q]uiet and [O]verwrite.
;	Syntax:	UNZIP {dir:}zipfile {dir:}{afn} [OQ]
;	Updated code fairly untidy, next update to tidy up.
;
; Version 1.5-5 -- September 19, 2021 -- Tony Nicholson
;	CP/M filenames must be UPPERCASE.
;
; Version 1.5-4 -- October 18, 2020 -- Russell Marks
;	Further slight optimisations to bit-readers,
;	fix long-filename buffer overrun,
;	backport some unzip 1.8 changes (buffer-overrun fixes, bit 7 strip on
;	output filenames, less frequent ^C checking, and low-memory message),
;	and add various comments.
;
;	Use self-modifying code with an unrolled end loop in rdbybits,
;	and add a "rd1bit" macro, for about a 12% speed improvement
;	on overall extraction time compared to version 1.5-3.
;	Fix long-filename buffer overrun, for filenames longer than
;	255 characters.
;	Backport Howard Goldstein's buffer-overrun fixes from
;	unzip 1.8 - previously, a 255-byte buffer was repeatedly used
;	to read up-to-65535-byte inputs.
;	Strip bit 7 on output filenames as in unzip 1.8.
;	Check ^C less frequently as in unzip 1.8 (but every 16 bytes
;	rather than every 128 there which was excessive and made
;	little difference to speed), for a further 30% speed
;	improvement on overall extraction time (or 38% total).
;	Adopt low-memory message from unzip 1.8.
;	Add some basic comments to code/data based mostly on the
;	https://en.wikipedia.org/wiki/Zip_(file_format)
;	format description.
;
; Version 1.5-3 -- October 15, 2020 -- Russell Marks
;	More optimisations to improve the speed of the UnDeflate
;	method.
;
;	Calls to readbits when an eight or fewer bit value is
;	passed optimised to a new rdbybits routine (about a 20%
;	speed improvement).
;	Cosmetic change the "V" label to "urV" for assembly with
;	zmac under Unix.
;	Output a message when there is insufficient TPA available.
;	Use a table-based CRC algorithm.  This increases
;	code size by about 1Kbyte and boosts the speed by more
;	than 30% compared to version 1.5-2.
;
; Version 1.5-2 -- September 3, 2020 -- Martin
;	In further postings to the USENET newsgroup comp.os.cpm, some
;	more enhancements.
;
;	Fix extraction of zero-length files.
;	Skip to the next file header if the compression method is unknown
;	Fix readbits when a full word (16 bits) is read (in preparation
;	for implementing the unDeflate algorithm.
;	Fix mis-ordering of variables.  Code makes the assumption
;	that "bitbuf" is the byte before "bleft".
;	Allow the relocation of the input buffer.
;	Make the output buffer size dynamic.
;	Implement the UnDeflate algorithm (based on the work by
;	Keir Fraser's HiTech-C code at
;	https://github.com/keirf/Amiga-Stuff/blob/master/inflate/degzip_portable.c
;
; Version 1.5-1 -- June 17, 2020 -- Martin
;	In postings to the USENET newgroup comp.os.cpm, a flaw in both
;	the un-implode and un-shrink routines was found to be causing
;	CRC errors.
;
;	For un-implode, the algorithm is essentially a translation
;	of the PKZ101 MS-DOS algorithm in C that has been hand optimized
;	into Z80 assembly language.  However, the readtree() function
;	was incorrectly returning a byte value in the A register, when
;	the shift routine at label ui5 was expecting a 16-bit value in HL.
;
;	For unshrink, there is a race condition with handling the "KwKwK"
;	case that was omitted from the routine.
;
;	Both updates are flagged with ;;v1.5-1 comments, and the
;	version sign-on message now includes the revision.

; Version 1.5 -- june 1, 1991 -- Howard Goldstein
;	Fixed bug at WILDLP which was causing an output spec of "dir:"
;	not to work correctly.  Corrected problems that were causing
;	writes to disk when a non-matching member file was being skipped.
;	Changed "disk full" logic to close and erase partial output file
;	and abort the program immediately.  Made several minor changes to
;	allow assembly with ZMAC or M80.

; Version 1.4 -- May 16, 1991 -- Bruce Morgen
;	Fixed bug at "setusr" and added output filename wildcard
;	support.  If the selected output filespec is NOT wild,
;	(and d: or dir: alone IS wild) UNZIP will exit after the
;	first extraction.  Boy, do I have a headache....

; Version 1.3 -- May 12, 1991 -- Gene Pizzetta
;	Some quick and dirty mods to make this utility more useful.
;	The original has to be the most God-awful source code I've
;	ever come across.  It is totally uncommented, and I have
;	no idea what kind of strange assembler it was written for.
;	This code now assembles with SLR's Z80ASM and it's a little
;	more orderly.
;
;	New syntax:
;		UNZIP {dir:}zipfile {dir:}{afn}
;	Under ZCPR3 "dir" can be a DU or DIR spec; otherwise, just
;	a drive.  If no destination is given, member files are checked
;	and listed.  If a destination is given, member files are
;	extracted if they match "afn" if given, otherwise the entire
;	ZIPfile is extracted.
;
;	You can now abort this thing with ^C (and the partial output
;	file, if any, will be closed and erased).  Usage screen now
;	responds to "//".  This program still needs a lot of work.
;	It's probably not bullet-proof and testing has been very
;	limited, but it seems to work.
;
; Version 1.2 -- July 3, 1990 -- David P. Goodenough
;
; System addresses
;
wboot:	equ	0
;bdos:	equ	exit
;
; BDOS service functions
;
conout:	equ	2
dircon:	equ	6
fopen:	equ	15
fclose:	equ	16
ferase:	equ	19
fread:	equ	20
fwrite:	equ	21
fmake:	equ	22
getdrv:	equ	25
setdma:	equ	26
setusr:	equ	32
;
; Other
;
STRSIZ:	equ	256		; must be 256 exactly, see plfh for why
DLE:	equ	144
max_bits: equ	13
init_bits: equ	9
hsize:	equ	8192
first_ent: equ	257
clear:	equ	256
maxcmax:	equ	2000h  ; 1 shl max_bits
maxSF:	equ	256
_code:	equ	0
_value:	equ	2
_bitlength: equ	3
_entries: equ	0
_maxlength: equ	2
_entry:	equ	4
_sf_tree_: equ	264  ; 4 + 4 * maxSF
maxcl:	equ	16
nrcl:	equ	19
nrlit:	equ	288
nrdist:	equ	32
;
; ASCII
;
CtrlC:	equ	03h
CR:	equ	0Dh
;LF:	equ	0Ah
CtrlZ:	equ	1Ah
;
;	aseg
	org	7000h
;
;
start:	ld	(oldstk),sp	; save old stack here for future use
	ld	sp,(04049h)		; set the stack pointer
;
; Check TPA size (this will need adjusting if warm-boot-only exit
; is changed).
;
	ld	hl,-128		; allow for a decent stack size
	add	hl,sp
	ld	de,endaddr
	or	a
	sbc	hl,de		; check endaddr is less (i.e. hl is >=)
	jp	c,nomem

        xor     a
	ld	(opfcb),a	; disk number
	call	ilprt
	db	"MiSTer Unzip 1.0, based on Unzip for CPM v1.5.7",CR
	db	"Enter destination disk : (0-3)<enter>",0
	ld	b, 1
	ld	hl,trsBUF
	call	0040h
	jr	c,exit
	xor	a
	or 	b
	jr 	z,disk0
	ld	a,(trsBUF)
	and	a,3
	ld	(opfcb),a
disk0:
;
; bit 1 = [O]verwrite
; bit 4 = [Q]uiet
;
	ld 	a,2		; overwrite
	ld	(opts),a
;
	ld	a,1
	ld	(mode),a	; 0=list only  1=extract files
;
	ld	a,1
	out     (6),a
	xor	a
	out	(5),a
	out	(4),a    	; sets the vmem address to 0x10000 
	jr	openok
;
nomem:	call	ilprt0		; complain and fall through to exit
	db	"Not enough memory.",CR,0
;
; All exits point here for possible future enhancements, such
; as elimination of warm boot.
;
exit:	call	ilprt0		; complain and fall through to exit
	db	"Press return to exit.",0
	call	049h 	; KBWAIT
	cp	a,CR
	jr  	nz,exit
if CCPQUIT
	ld	sp,(oldstk)
	ret
else
	jp	wboot
endif
;
sigerr0:call	ilprt0
	db	"No ZIP file in CAS mem.\r\n\0"
	jr	exit
sigerr:	call	ilprt0
	db	"Zipfile corrupt.\r\n\0"
	jr	exit
;
; Judging from https://en.wikipedia.org/wiki/Zip_(file_format)
; this appears to read the file in a technically incorrect way,
; by relying on the local file header only (as a zip-fixing
; program might), and simply skipping past the central directory
; entirely. This leaves us potentially extracting deleted files,
; for example. It's probably not a real problem in most
; cases, but it seemed worth noting. Many unzippers do actually
; just work through the data segment and ignore the central
; directory.
;
openok:	call	getword
	ld	de,-19280	; -(('K' shl 8) + 'P')		; magic number
	add	hl,de
	ld	a,h
	or	l
	jr	nz,sigerr0
	call	getword
	dec	l		; check for 01,02 (central directory)
	jr	nz,nocfhs
	dec	h
	dec	h
	jr	nz,sigerr
if FASTQUIT
	jr	exit		; data block done, exit
else
	call	pcfh
	jr	openok
endif
;
nocfhs:	dec	l		; check for 03,04 (local file header)
	dec	l
	jr	nz,nolfhs
	ld	a,h
	sub	4
	jr	nz,sigerr
	call	plfh
	jr	openok
;
nolfhs:	dec	l		; check for 05,06 (end of central dir.)
	dec	l
	jr	nz,sigerr
	ld	a,h
	sub	6
	jr	nz,sigerr
if FASTQUIT
	jp	exit		; data block done, exit
else
	call	pecd
	jp	exit
endif
;
; (The belated-CRC type (07,08) is apparently not supported.)
;
; pcfh/pecd are not truly required, they only serve to skip past
; the central directory and end-of-central-directory blocks. But
; they do arguably serve as a small additional check of file
; integrity. It would be faster to simply exit when we spot the
; central directory signature (since the CD/EOCD are by definition
; the last two things) - for large files this might be noticeable.
;
; pcfh - skip past central directory
;
if FASTQUIT
else
pcfh:	ld	b,12		; skip ahead to filename length entry
pcfhl1:	push	bc
	call	getword
	pop	bc
	djnz	pcfhl1
	call	getword
	push	hl
	call	getword
	push	hl
	call	getword
	pop	de
	pop	bc
	push	hl		; file comment length
	push	de		; extra field length
	push	bc		; filename length
	ld	b,6		; skip ahead to filename
pcfhl2:	push	bc
	call	getword
	pop	bc
	djnz	pcfhl2
	pop	hl
	call	skpstring	; skip past filename
	pop	hl
	call	skpstring	; skip past extra field
	pop	hl
	jp	skpstring	; skip past file comment
endif
;
; pecd - skip past end-of-central-directory
;
if FASTQUIT
else
pecd:	ld	b,8		; skip ahead to comment length
pecdl:	push	bc
	call	getword
	pop	bc
	djnz	pecdl
	call	getword		; comment length
	jp	skpstring	; skip past comment
endif
;
; plfh - read local file header, then extract/check file
;
; NB: As mentioned above, this is technically not the correct
; approach to take (but it's almost certainly faster this way
; and will do the right thing for most zips).
;
plfh:	ld	de,lfh
	ld	hl,endlfh-lfh
	call	getstring
	ld	hl,opfcb+1
	ld	de,opfcb+2
	ld	bc,33
	ld	(hl),b
	ldir			; zero opfcb
;
; Read filename from LFH into "junk". Filenames of >255 (sic)
; characters will be skipped after the 255th char.
; Required as the format allows 65535-char filenames. (!)
;
	ld	de,junk
	ld	hl,(fnl)
	ld	a,h
	or	a
	jr	z,plfh2
	ld	hl,STRSIZ-1	; 255, allow for trailing zero byte
plfh2:	call	getstring	; rets DE pointing past last char read
	ex	de,hl
	ld	de,junk
	or	a
	sbc	hl,de
	ex	de,hl		; DE=number of chars read already
	ld	hl,(fnl)
	or	a		; probably unnecessary, but for clarity
	sbc	hl,de
	call	skpstring	; skip the rest of any long filename
	ld	hl,(efl)
	call	skpstring	; skip extra field
;
; Copy leafname from junk to opfn.
;
; Now that filenames of <=255 chars are retained to this point,
; there is the possibility of adding some kind of support for
; zips with embedded paths in filenames (which are very common).
; We default to '-j' junk-paths and skip past any directories
; to get to the final leafname. Does not make sense to have '-j'
; turned off as CP/M does not have directories.
;
; NOTE: The ZipFile specification specifies that directory seperators
; inside a ZIP file are '/' characters, regardless of what the host's
; directory separators are.
;
; NOTE: ZipFiles may have directory entries, these are filenames that
; end in '/'. For CP/M these should be skipped. This is implemented
; by them being reduced to a null filename.
;
	ld	hl,junk		; point to filename from ZipFile
junk1:	ld	d,h		; current start of leafname
	ld	e,l
junk2:	ld	a,(hl)
	inc	hl
	and	a
	jr	z,junked	; end of filename, hl=>leafname
	cp	'/'		; Zipfile directory seperator
	jr	z,junk1		; set this as start of leafname
	jr	junk2		; otherwise check next char

; de now points to the final leafname, or the end of the filename
; if the entry is a directory.

junked:	ld	a,(de)
	and	a
	ret	z		; Entry is a directory, ignore it
; *NOTE* If a directory entry erroneously has a data field, will run
; into it and get 'Bad Zip file' error.

	ld	hl,opfn
	ld	b,8
	call	scanfn
	ld	a,(de)
	cp	'.'
	jr	nz,nodot
	inc	de
nodot:	ld	b,3
	call	scanfn
	ld	hl,init
	ld	de,vars
	ld	bc,endinit-init
	ldir
	ld	a,(mode)
resmod:	ld	(curmode),a
	or	a
	jp	z,listit	; zero = list without extracting
mtched:	call	setout		; log output user
	ld	de,opfcb
	ld	a,(opts)
	bit	1,a
	jr	z,ifthere	; [O]verwrite off
;	ld	c,ferase	; delete any existing file
;	call	bdos
	call	cp_fn_DCB
	ld	de,trsDCB
	ld	hl,trsBUF
	ld	b,128
	call	4424h	;Open
	jr	z,saveit
	ld	de,trsDCB
	call	442Ch	;Kill
	jr	saveit
ifthere:
	call	cp_fn_DCB
	ld	de,trsDCB
	ld	hl,trsBUF
	ld	b,128
	call	4424h		;OPEN
;	ld	c,fopen		; see if output file already exists
;	call	bdos
;	inc	a
	jr	z,exists
saveit:	
;	ld	b,11
;	ld	hl,opfn
;	ld	de,mtchfcb
;mtchlp:	ld	a,(de)
;	ld	c,(hl)
;	inc	hl
;	inc	de
;	cp	'?'
;	jr	z,mtch1
;	res	7,c
;	cp	c
;	jr	nz,nomtch
;mtch1:	djnz	mtchlp
	jr	creok		; (nope, so continue)
;nomtch:	ld	hl,junk
;	call	pstr
;	call	ilprt
;	db	" doesnt match",0
;	jr	noex
exists:	ld	hl,junk		; it exists, so skip it
	call	pstr
	call	ilprt
	db	" -- exists",0
	xor	a
	ld	(curmode),a
	ld	(zipeof),a
	jr	doext2
;	jp	badskp

noex:	call	ilprt
	db	" -- not extracting  ",0
	xor	a
	jp	resmod
;
extrct:
listit:	xor	a
	ld	(zipeof),a
	ld	a,(curmode)
	or	a
	jr	nz,doext
;	call	ilprt
;	db	'Checking ',0
	jr	pjunk
;
creok:	call	setout
;	ld	de,opfcb	; create output file
;	ld	c,fmake
;	call	bdos
	call	cp_fn_DCB
	ld	de,trsDCB
	ld	hl,trsBUF
	ld	b,128
	call	4420h	; INIT
;	or	a
	jr	z,opnok1
;	inc	a
;	jr	nz,opnok1
	call	ilprt
	db	"Error creating ",0
	ld	hl,junk
	call	pstr
	jr	noex
;
opnok1:
;	call	ilprt
;	db	"Extracting \0"
pjunk:	ld	hl,junk		; print filename
	call	pstr
doext:	call	ilprt
	db	" -- ",0
doext2:	ld	hl,(cs)
	ld	de,(cs + 2)
	ld	a,d
	or	e
	or	h
	or	l
	ld	hl,zipeof
	jr	nz,neof
	inc	(hl)
neof:	inc	hl
	inc	(hl)
	ld	a,(cm)
	cp	9
	jr	nc,badzip
	ld	a,(curmode)
	or	a
	jr	z,caseck
	call	ilprt
	db	"extracting ",0
caseck:	ld	a,(cm)
	or	a
	jr	nz,case1
case0w:	ld	a,(zipeof)
	and	1
	jr	nz,closeo
savcs0:	call	getbyte
	call	outbyte
	jr	case0w
;
case1:	dec	a
	jr	nz,case2p
	call	unshrink
	jr	closeo
;
case2p:	dec	a
	cp	4
	jr	nc,tryimp
	call	unreduce
	jr	closeo
;
tryimp:	
;	jr	nz,trydfl
;	call	unimplode
;	jr	closeo
;
trydfl:	cp	6
	jr	nz,badzip
	call	undeflate
	jr	closeo
;
badzip:	call	ilprt
	db	"unknown compression method",CR,0
badskp:	ld	a,(zipeof)
	and	1
	jr	nz,closeo
	call	getbyte
	jr	badskp

;
open_wr:
;	ld	de,opbuf
;	ld	c,setdma
;	call	bdos
	call	setout
;	ld	de,opfcb
;	ld	c,fwrite
;	jp	bdos
	ld	de,trsDCB
	ld	hl,opbuf
	call	4439h		; WRITE
	ret
;
closeo:	ld	hl,zipeof
	dec	(hl)
	inc	hl
	dec	(hl)
	ld	a,(curmode)
	or	a
	jr	z,nocls
;	jr	nz,nocls
	ld	hl,wrtpt
	ld	a,(hl)
	or	a
	jr	z,noflsh
	call	open_wr
noflsh:	call	setout
;	ld	de,opfcb
;	ld	c,fclose
;	call	bdos
	ld	de,trsDCB
	call	4428h		; CLOSE
nocls:	ld	hl,crc32
	ld	de,crc
	scf
	ld	bc,400h   ; 4 shl 8
crcclp:	ld	a,(de)
	adc	a,(hl)
	push	af
	or	c
	ld	c,a
	pop	af
	inc	hl
	inc	de
	djnz	crcclp
	ld	a,c
	or	a
	jr	z,crcok
	call	ilprt
	db	"CRC error",CR,0
	jr	wildck
;
crcok:	ld	a,(mode)
	or	a
	jr	z,crcok2
	call	ilprt
	DB	CR,0
	jr	wildck
crcok2:	call	ilprt
	db	"CRC OK",CR,0
wildck:	ret

;	ld	a,(curmode)
;	or	a
;	ret	z
;wild2:	ld	hl,mtchfcb
;	ld	bc,11
;	ld	a,'?'
;	cpir
;	jp	nz,exit
;	ret
;
getchla:
	ld	a,(codesize)
	call	readbits
	ld	(code),hl
	ld	a,(zipeof)
	and	1
	ret
;
savstk:	ld	hl,(stackp)
	dec	hl
	ld	(stackp),hl
	ld	(hl),a
	ret
;
rd16bits:
	ld	a,16

readbits:
	ld	b,a
	ld	c,80h		; bits rotate into C and A
	xor	a		; (rra is 4 cycles vs 8 for others)
	ld	hl,(bitbuf)	; keep bitbuf in L, bleft in H
getbit:	dec	h
	jp	p,getbt2	; skip if new byte not needed yet
	push	af
	push	bc
	call	getbyte
	ld	l,a		; new bitbuf
	ld	h,7		; 8 bits left, pre-dec'd
	pop	bc
	pop	af
getbt2:	rr	l
	rr	c
	rra
	jr	c,bitret
	djnz	getbit
finbit: srl	c
	rra
	jp	nc,finbit	; jp likely faster in this case
bitret:	ld	(bitbuf),hl	; update bitbuf/bleft
	ld	h,c		; return bits in HL and A
	ld	l,a
	ret
;
; rdbybits - faster version of readbits for <=8 bits.
; Due to the implementation this must not ever be called with A>8.
; (No caller seems to require saving BC, so I removed that for both
; this and readbits.)
;
rdbyte:
	ld	a,8

rdbybits:
	ld	(rdbyop+1),a	; modify jr instruction at rdbyop
	ld	b,a
	xor	a		; bits rotate into A (rra faster)
	ld	hl,(bitbuf)	; keep bitbuf in L, bleft in H
rdbylp:	dec	h
	jp	p,rdby1		; skip if new byte not needed yet
	ld	c,a
	push	bc
	call	getbyte
	ld	l,a		; new bitbuf
	ld	h,7		; 8 bits left, pre-dec'd
	pop	bc
	ld	a,c
rdby1:	rr	l
	rra
	djnz	rdbylp
	ld	(bitbuf),hl	; update bitbuf/bleft
	or	a
rdbyop:	jr	rdbyr8
rdbyr8:	rra			; 8x rra, not all are used in practice but
	rra			; this arrangement simplifies code above
	rra
	rra
	rra
	rra
	rra
	rra
	ld	h,b		; B still zero after the final djnz
	ld	l,a		; return bits in HL and A
	ret
;
; rd1bit - faster version which reads a single bit only.
; The jp instruction here is awkward, due to differing
; local-symbol syntax between assemblers.
;
rd1bit:	macro
	ld	hl,(bitbuf)	; keep bitbuf in L, bleft in H
	dec	h
	jp	p,$+9		; jump to "xor a", past jp op plus 6 bytes:
	call	getbyte		; (3 bytes)
	ld	l,a		; (1 byte)  new bitbuf
	ld	h,7		; (2 bytes) 8 bits left, pre-dec'd
	xor	a		; jp op above jumps here
	rr	l
	ld	(bitbuf),hl	; update bitbuf/bleft
	ld	h,a		; A still zero
	rla			; return bit in HL and A
	ld	l,a
	endm
;
; scans up to B characters, padding if less, skipping any extras
scanfn:	ld	a,(de)
	cp	'.'
	jr	z,nocopy
	or	a
	jr	z,nocopy
	inc	de
	dec	b
	jp	m,scanfn
	and	7fh		; remove high bit
	cp	'a'		; convert to UPPERCASE
	jr	c,scfu		; use same scheme as CCP
	cp	'z'+1		; only convert letters
	jr	nc,scfu
	sub	20h
scfu:	ld	(hl),a
	inc	hl
	jr	scanfn
;
nocopy:	dec	b
	ret	m
	ld	(hl),' '
	inc	hl
	jr	nocopy
;
ilprt0:	xor	a
	ld	(opts),a	; force [Q]uiet off
ilprt:	pop	hl
	call	pstr
	jp	(hl)
;
pstr:	ld	bc,(opts-1)	; b=options
pstrlp:	ld	a,(hl)
	or	a
	ret	z
	bit	4,b
	jr	nz,pskip	; [Q]uiet
	push	hl
	call	0033h   ; TRS80
	pop	hl
pskip:	inc	hl
	jr	pstrlp
;
; getstring must return DE pointing just past the last byte read.
;
getstring:
	ld	a,h
	or	l
	ld	(de),a
	ret	z
	push	de
	push	hl
	call	getbyte
	pop	hl
	pop	de
	ld	(de),a
	inc	de
	dec	hl
	jr	getstring
;
skpstring:
	ld	a,h
	or	l
	ret	z
	push	hl
	call	getbyte
	pop	hl
	dec	hl
	jr	skpstring
;
getword:
	call	getbyte
	push	af
	call	getbyte
	pop	hl
	ld	l,h
	ld	h,a
	ret
;
getbyte:
	in	a,(4)
	ret
;
ateof:	ld	a,CtrlZ
	ret
;
outb:	ld	hl,(outpos)
	push	hl
	push	af
	ld	a,(omask)
	and	h
	ld	h,a
	pop	af
	ld	de,outbuf
	add	hl,de
	ld	(hl),a
	pop	hl
	inc	hl
	ld	(outpos),hl
	push	af
	ld	a,h
	or	l
	jr	nz,nopos
	ld	hl,(outpos + 2)
	inc	hl
	ld	(outpos + 2),hl
nopos:	pop	af
outbyte:
	push	af
	call	updcrc
	ld	hl,(ucs)
	ld	de,(ucs + 2)
	ld	a,h
	or	l
	dec	hl
	ld	(ucs),hl
	jr	nz,tsthl0
	dec	de
	ld	(ucs + 2),de
tsthl0:	ld	a,h
	or	l
	or	d
	or	e
	jr	nz,noeof
	ld	hl,zipeof
	inc	(hl)
noeof:	ld	a,(curmode)
	or	a
	jr	nz,noeof1
	pop	af
	ret
;
noeof1:	ld	hl,wrtpt
	ld	a,(hl)
	add	a,a
	jr	nc,wptok
	call	open_wr
	or	a
	jr	z,wptok
	call	ilprt
	db	"Write Error (Disk full)",CR,0
	jp	ckcon0
;
wptok:	jr	nz,nofilb
	ld	hl,opbuf
	ld	de,opbuf + 1
	ld	bc,127
	ld	(hl),CtrlZ
	ldir
	xor	a
	ld	(wrtpt),a
nofilb:	pop	af
	ld	hl,wrtpt
	inc	(hl)
	ld	l,(hl)
	ld	h,0
	ld	de,opbuf - 1
	add	hl,de
	ld	(hl),a
	ret
;
; based on this from crc32() in degzip_portable.c:
;    for (i = 0; i < len; i++)
;        crc = crc32_tab[(uint8_t)(crc ^ *b++)] ^ (crc >> 8);
;
updcrc:	ld	bc,(crc32)
	xor	c		; A=low byte of crc xor output byte
	ld	h,0
	ld	l,a
	add	hl,hl		; *2
	add	hl,hl		; *4
	ld	de,crc32tab
	add	hl,de
	ld	de,(crc32 + 2)
	; now DEBC is "crc", and HL points to low byte of
	; relevant crc32tab entry. Do the xor with "crc"/256,
	; starting from the low bytes.
	ld	a,(hl)
	xor	b
	ld	c,a
	inc	hl
	ld	a,(hl)
	xor	e
	ld	b,a
	inc	hl
	ld	a,(hl)
	xor	d
	ld	e,a
	inc	hl
	ld	d,(hl)		; high byte is a simple copy
	ld	(crc32 + 2),de
	ld	(crc32),bc
	ret
;
unshrink:
	ld	a,1fh
	ld	(omask),a
	ld	a,init_bits
	ld	(codesize),a
	ld	hl,1ffh       ; +(1 shl init_bits) - 1;
	ld	(maxcode),hl
	ld	hl,first_ent
	ld	(free_ent),hl
	ld	hl,prefix_of
	ld	de,prefix_of + 1
	ld	bc,512
	ld	(hl),c
	ldir
	ld	bc,16386 - 512
	ld	(hl),-1
	ldir
	ld	hl,suffix_of
sol:	ld	(hl),c
	inc	hl
	inc	c
	jr	nz,sol
	call	getchla
	ld	(oldcode),hl
	ret	nz
	ld	a,l
	ld	(finchar),a
	call	outbyte
unshlp:	ld	hl,stack + 8192
	ld	(stackp),hl
	ld	a,(zipeof)
	and	1
	ret	nz
clrlp:	call	z,getchla
	ret	nz
	ld	a,h
	dec	a
	or	l
	jr	nz,noclr
	call	getchla
	ld	a,h
	or	a
	jr	nz,clrlp
	dec	l
	jr	z,bumpcs
	dec	l
	call	z,partial_clear
	jr	clrlp
;
bumpcs:	ld	hl,codesize
	inc	(hl)
	ld	a,(hl)
	cp	max_bits
	ld	hl,maxcmax
	jr	z,atmax
	ld	hl,1
maxclp:	add	hl,hl
	dec	a
	jr	nz,maxclp
	dec	hl
atmax:	ld	(maxcode),hl
	jr	clrlp
;
noclr:	ld	(incode),hl	;;v1.5-1 start unshrink fix
	add	hl,hl
	ld	de,prefix_of
	add	hl,de
	ld	a,(hl)
	inc	hl
	and	(hl)
	inc	a
	ld	hl,(code)
	jr	nz,noKwKw
	ld	a,(finchar)
	call	savstk
	ld	hl,(oldcode)
noKwKw:	ex	de,hl
;
staklp:	ld	hl,100h
	or	a
	sbc	hl,de
	jr	nc,unstak
	ld	hl,prefix_of
	add	hl,de
	add	hl,de
	ld	a,(hl)
	inc	hl
	and	(hl)
	inc	a
	jr	nz,noKw2
	ld	a,(finchar)
	call	savstk
	ld	de,(oldcode)
	jr	staklp
;
noKw2:	ld	hl,suffix_of
	add	hl,de
	ld	a,(hl)
	call	savstk
	ld	hl,prefix_of
	add	hl,de
	add	hl,de
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	jr	staklp
;
unstak:	ld	hl,suffix_of
	add	hl,de
	ld	a,(hl)
	call	savstk
	ld	(finchar),a	;;v1.5-1 end of unshrink fix
	ld	de,(stackp)
unslp:	ld	hl,stack + 8192
	or	a
	sbc	hl,de
	jr	z,newent
	ld	a,(de)
	inc	de
	push	de
	call	outbyte
	pop	de
	jr	unslp
;
newent:	ld	hl,(free_ent)
	ld	(code),hl
	ex	de,hl
	ld	hl,1fffh
	or	a
	sbc	hl,de
	jr	c,full
	ld	hl,prefix_of
	add	hl,de
	add	hl,de
	ld	bc,(oldcode)
	ld	(hl),c
	inc	hl
	ld	(hl),b
	ld	hl,suffix_of
	add	hl,de
	ld	a,(finchar)
	ld	(hl),a
getfre:	inc	de
	ld	hl,1fffh
	or	a
	sbc	hl,de
	jr	c,full1
	ld	hl,prefix_of
	add	hl,de
	add	hl,de
	ld	a,(hl)
	inc	hl
	and	(hl)
	inc	a
	jr	nz,getfre
full1:	ld	(free_ent),de
full:	ld	hl,(incode)
	ld	(oldcode),hl
	jp	unshlp
;
partial_clear:
	ld	de,first_ent
l8:	ld	hl,(free_ent)
	or	a
	sbc	hl,de
	jr	z,br8
	ld	hl,prefix_of + 1
	add	hl,de
	add	hl,de
	set	7,(hl)
	inc	de
	jr	l8
;
br8:	ld	de,first_ent
l9:	ld	hl,(free_ent)
	or	a
	sbc	hl,de
	jr	z,br9
	ld	hl,prefix_of
	add	hl,de
	add	hl,de
	push	de
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	res	7,d
	ld	hl,first_ent - 1
	or	a
	sbc	hl,de
	jr	nc,ei10
	ld	hl,prefix_of + 1
	add	hl,de
	add	hl,de
	res	7,(hl)
ei10:	pop	de
	inc	de
	jr	l9
;
br9:	ld	de,first_ent
l10:	ld	hl,(free_ent)
	or	a
	sbc	hl,de
	jr	z,br10
	ld	hl,prefix_of + 1
	add	hl,de
	add	hl,de
	bit	7,(hl)
	jr	z,ei11
	ld	(hl),-1
	dec	hl
	ld	(hl),-1
ei11:	inc	de
	jr	l10
;
br10:	ld	de,first_ent
l11:	ld	hl,maxcmax
	or	a
	sbc	hl,de
	jr	z,br11
	ld	hl,prefix_of
	add	hl,de
	add	hl,de
	ld	a,(hl)
	inc	hl
	and	(hl)
	inc	a
	jr	z,br11
	inc	de
	jr	l11
br11:	ld	(free_ent),de
	ret

; End of SHRINK related section

; -------------------------
; REDUCE Method
; -------------------------
;
loadfollowers:
	ld	hl,Slen + 255
	ld	b,0
lflp:	push	bc
	push	hl
	ld	a,6
	call	rdbybits
	pop	hl
	pop	de
	ld	(hl),a
	push	de
	push	hl
	dec	d
	ld	hl,followers
	call	shftadd
	ld	b,a
	or	a
	jr	z,nofoll
ldfllp:	push	hl
	push	bc
	call	rdbyte
	pop	bc
	pop	hl
	ld	(hl),a
	inc	hl
	djnz	ldfllp
nofoll:	pop	hl
	pop	bc
	dec	hl
	djnz	lflp
	ret
;
unreduce:
	ld	e,a
	ld	d,0
	ld	hl,_L_table
	add	hl,de
	ld	a,(hl)
	ld	(L_table),a
	ld	hl,_D_shift
	add	hl,de
	ld	a,(hl)
	ld	(D_shift),a
	ld	a,1fh
	ld	(omask),a
	xor	a
	ld	(ExState),a
	ld	(lchar),a
	call	loadfollowers
ur1:	ld	a,(zipeof)
	and	1
	ret	nz
	call	slenlch
	or	a
	jr	nz,ur2
ur4:	call	rdbyte
	jr	ur3
;
ur2:	rd1bit
	dec	l
	jr	z,ur4
	call	slenlch
	dec	a
	or	1
	ld	l,a
	xor	a
btlp:	inc	a
	srl	l
	jr	nz,btlp
	call	readbits
	ld	de,followers
	add	hl,de
	ld	de,(lchar - 1)
	call	shftadd
	ld	a,(hl)
ur3:	ld	(nchar),a
	ld	l,a
	ld	a,(ExState)
	or	a
	jr	nz,ur5
	ld	a,l
	cp	DLE
	jr	nz,ur9
	ld	a,1
	ld	(ExState),a
	jr	ur6
;
ur5:	dec	a
	jr	nz,ur7
	ld	a,l
	or	a
	jr	z,ur10
	ld	(urV),a
	ld	a,(L_table)
	ld	h,a
	and	l
	cp	h
	ld	l,a
	ld	h,0
	ld	(Len),hl
	jr	nz,ur12
	ld	a,2
	jr	ur11
;
ur10:	ld	(ExState),a
	ld	a,DLE
ur9:	call	outb
	jr	ur6
;
ur7:	dec	a
	jr	nz,ur8
	ld	a,l
	ld	hl,Len
	add	a,(hl)
	ld	(hl),a
	jr	nc,ur12
	inc	hl
	inc	(hl)
ur12:	ld	a,3
	jr	ur11
;
ur8:	dec	a
	jr	nz,ur13
	ld	a,(D_shift)
	ld	b,a
	ld	a,(urV)
ur14:	srl	a
	djnz	ur14
	ld	h,a
	inc	hl
	ld	bc,(Len)
	inc	bc
	inc	bc
	inc	bc
	call	callback
ur13:	xor	a
ur11:	ld	(ExState),a
ur6:	ld	a,(nchar)
	ld	(lchar),a
	jp	ur1
;
slenlch:
	ld	hl,(lchar)
	ld	h,0
	ld	de,Slen
	add	hl,de
	ld	a,(hl)
	ret
;
shftadd:
	ld	e,0
	srl	d
	rr	e
	srl	d
	rr	e
	add	hl,de
	ret

; --- End of REDUCE decompression section ---


;
callback:
	push	bc
	push	hl
	ld	hl,(outpos)
	ld	de,(outpos + 2)
	pop	bc
	or	a
	sbc	hl,bc
	jr	nc,cb2
	dec	de
cb2:	pop	bc
cb3:	bit	7,d
	jr	z,cb4
	ld	a,b
	or	c
	jr	z,cb4
	xor	a
	call	outbp
	inc	hl
	ld	a,h
	or	l
	jr	nz,cb5
	inc	de
cb5:	dec	bc
	jr	cb3
;
cb4:	ex	de,hl
cb6:	ld	a,b
	or	c
	ret	z
	ld	a,(omask)
	and	d
	ld	d,a
	ld	hl,outbuf
	add	hl,de
	ld	a,(hl)
	call	outbp
	inc	de
	dec	bc
	jr	cb6
;
outbp:	push	hl
	push	de
	push	bc
	call	outb
	pop	bc
	pop	de
	pop	hl
	ret
;
readlengths:
	call	rdbyte
	ld	d,h
	ld	e,d
	inc	hl
	ld	b,h
	ld	c,l
	ld	(ix + _maxlength),e
	ld	(ix + _maxlength + 1),d
	push	ix
	pop	hl
	inc	hl
	inc	hl
	inc	hl
rl1:	ld	a,b
	or	c
	ret	z
	push	bc
	push	de
	push	hl
	ld	a,4
	call	rdbybits
	inc	a
	push	af
	ld	a,4
	call	rdbybits
	inc	a
	ld	b,a
	pop	af
	ld	c,a
	pop	hl
	pop	de
	ld	a,(ix + _maxlength)
	cp	c
	jr	nc,rl2
	ld	(ix + _maxlength),c
rl2:	inc	hl
	inc	hl
	inc	hl
	ld	(hl),e
	inc	hl
	ld	(hl),c
	inc	e
	djnz	rl2
	pop	bc
	dec	bc
	jr	rl1
;
sortlengths:
	ld	h,(ix + _entries + 1)
	ld	l,(ix + _entries)
	ld	b,h
	ld	c,l
	ld	(entrs),hl
sl7:	srl	b
	rr	c
sl1:	ld	a,b
	or	c
	ret	z
	ld	(noswps),a
	push	ix
	ld	de,4
	add	ix,de
	push	ix
	pop	iy
	add	iy,bc
	add	iy,bc
	add	iy,bc
	add	iy,bc
	ld	hl,(entrs)
	or	a
	sbc	hl,bc
sl2:	ld	a,(ix + _bitlength)
	cp	(iy + _bitlength)
	jr	c,sl4
	jr	nz,sl3
	ld	a,(iy + _value)
	cp	(ix + _value)
	jr	nc,sl4
sl3:	ld	d,e
sl5:	ld	a,(ix)
	push	af
	ld	a,(iy)
	ld	(ix),a
	pop	af
	ld	(iy),a
	inc	ix
	inc	iy
	dec	d
	jr	nz,sl5
	ld	a,d
	ld	(noswps),a
	jr	sl6
;
sl4:	add	ix,de
	add	iy,de
sl6:	dec	hl
	ld	a,h
	or	l
	jr	nz,sl2
	pop	ix
	ld	a,(noswps)
	or	a
	jr	nz,sl7
	jr	sl1
;
;
;
nextsymbol:
	ld	(treep),hl
nsloop:	push	hl
	rd1bit
	pop	hl
	or	a
	jr	z,nsleft
	inc	hl
	inc	hl
nsleft:	ld	e,(hl)
	inc	hl
	ld	d,(hl)

	ld	a,d
	cp	10h
	jr	nc,nsleaf
	or	e
	ret	z

	ld	hl,(treep)
	add	hl,de
	add	hl,de
	add	hl,de
	add	hl,de
	jr	nsloop

nsleaf:	and	0fh
	ld	d,a
	ret
;
buildcode:
	ld	(lenp),hl
	ld	(nodes),de
	ld	(nrsym),bc

	ld	hl,blcnt
	ld	de,blcnt + 1
	ld	bc,2 * maxcl + 1
	ld	(hl),b
	ldir

	ld	bc,(nrsym)
	ld	de,(lenp)
bclp1:	ld	a,(de)
	add	a,a
	jr	z,bcnol
	ld	hl,blcnt
	add	a,l
	ld	l,a
	jr	nc,bcnc1
	inc	h
bcnc1:	ld	a,(hl)
	inc	a
	ld	(hl),a
	jr	nz,bcnol
	inc	hl
	inc	(hl)
bcnol:	inc	de
	dec	bc
	ld	a,b
	or	c
	jr	nz,bclp1

	ld	hl,0
	push	hl

	ld	bc,1
bclp2:	ld	a,c
	sub	maxcl + 1
	jr	nc,bccn2

	ld	hl,blcnt
	add	hl,bc
	add	hl,bc
	dec	hl
	ld	d,(hl)
	dec	hl
	ld	e,(hl)

	pop	hl
	add	hl,de
	add	hl,hl
	push	hl

	ex	de,hl
	ld	hl,ncode
	add	hl,bc
	add	hl,bc
	ld	(hl),e
	inc	hl
	ld	(hl),d

	inc	c
	jr	bclp2
bccn2:	pop	hl

	ld	hl,(nrsym)
	add	hl,hl
	add	hl,hl
	ld	b,h
	ld	c,l
	ld	hl,(nodes)
	ld	d,h
	ld	e,l
	inc	de
	dec	bc
	ld	(hl),0
	ldir

	ld	hl,1
	ld	(nnode),hl

	ld	bc,0
bclp3:	ld	hl,(lenp)
	add	hl,bc
	ld	a,(hl)
	or	a
	jr	z,bccn3

	push	bc

	push	af
	ld	hl,ncode
	add	a,a
	add	a,l
	ld	l,a
	jr	nc,bc4
	inc	h
bc4:	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ld	(bcode),de
	inc	de
	ld	(hl),d
	dec	hl
	ld	(hl),e
	pop	af

	ld	hl,1
bclp4:	dec	a
	or	a
	jr	z,bccn4
	add	hl,hl
	jr	bclp4
bccn4:	ld	(bmask),hl

	ld	hl,(nodes)
bclp5:	ld	de,(bcode)
	ld	bc,(bmask)
	ld	a,d
	and	b
	ld	d,a
	ld	a,e
	and	c
	ld	e,a
	or	d
	jr	z,bcleft
	inc	hl
	inc	hl
bcleft:	srl	b
	rr	c
	ld	(bmask),bc
	ld	a,b
	or	c
	jr	z,bccn5

	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ld	a,d
	or	e
	jr	nz,bc6
	ld	de,(nnode)
	ld	(hl),d
	dec	hl
	ld	(hl),e
	inc	de
	ld	(nnode),de
	dec	de

bc6:	ld	hl,(nodes)
	add	hl,de
	add	hl,de
	add	hl,de
	add	hl,de
	jr	bclp5

bccn5:	pop	bc

	ld	(hl),c
	inc	hl
	ld	a,b
	or	10h
	ld	(hl),a

bccn3:	inc	bc
	ld	hl,(nrsym)
	or	a
	sbc	hl,bc
	jr	nz,bclp3
	ret
;
huffman:
	ld	a,5
	call	rdbybits
	inc	a
	ld	l,a
	ld	h,1
	ld	(hlit),hl

	ld	a,5
	call	rdbybits
	inc	a
	ld	(hdist),a

	ld	a,4
	call	rdbybits
	add	a,4
	ld	c,a

	ld	b,0
	ld	de,clord
hmlp1:	ld	a,b
	cp	c
	jr	nc,hmcn1
	push	bc
	push	de
	ld	a,3
	call	rdbybits
	pop	hl
	ld	c,(hl)
	ld	b,0
	ex	de,hl
	ld	hl,lenld
	add	hl,bc
	ld	(hl),a
	pop	bc
	inc	de
	inc	b
	jr	hmlp1

hmcn1:	xor	a
	ld	c,a
hmlp2:	ld	a,b
	cp	nrcl
	jr	nc,hmcn2
	ld	a,(de)
	ld	hl,lenld
	add	a,l
	ld	l,a
	jr	nc,hmnc2
	inc	h
hmnc2:	ld	(hl),c
	inc	de
	inc	b
	jr	hmlp2

hmcn2:	ld	hl,lenld
	ld	de,cltr
	ld	bc,nrcl
	call	buildcode

	ld	hl,(hlit)
	ld	a,(hdist)
	add	a,l
	ld	c,a
	ld	a,h
	adc	a,0
	ld	b,a
	ld	hl,lenld
hmlp3:	push	bc
	push	hl
	ld	hl,cltr
	call	nextsymbol
	ld	a,e

	cp	010h
	jr	nz,hmn16
	ld	a,2
	call	rdbybits
	pop	hl
	pop	bc
	add	a,3
	ld	d,a
	dec	hl
	ld	e,(hl)
	inc	hl
hmlp4:	ld	(hl),e
	inc	hl
	dec	bc
	dec	d
	jr	nz,hmlp4
	jr	hmcn3

hmn16:	cp	011h
	jr	nz,hmn17
	ld	a,3
	call	rdbybits
	pop	hl
	pop	bc
	add	a,3
	ld	d,a
	xor	a
hmlp5:	ld	(hl),a
	inc	hl
	dec	bc
	dec	d
	jr	nz,hmlp5
	jr	hmcn3

hmn17:	cp	012h
	jr	nz,hmn18
	ld	a,7
	call	rdbybits
	pop	hl
	pop	bc
	add	a,11
	ld	d,a
	xor	a
hmlp6:	ld	(hl),a
	inc	hl
	dec	bc
	dec	d
	jr	nz,hmlp6
	jr	hmcn3

hmn18:	pop	hl
	pop	bc
	ld	(hl),a
	inc	hl
	dec	bc

hmcn3:	ld	a,b
	or	c
	jr	nz,hmlp3

	ld	hl,lenld
	ld	de,littr
	ld	bc,(hlit)
	call	buildcode

	ld	hl,(hlit)
	ld	de,lenld
	add	hl,de
	ld	de,disttr
	ld	a,(hdist)
	ld	c,a
	ld	b,0
	call	buildcode

	ld	hl,(inbps)
	ld	a,l
	or	h
	jr	z,hmnext
	ld	(inbufp),hl
	ld	a,(rdpts)
	ld	(readpt),a
	ld	hl,(bitbs)	; H=bleft=blfts, L=bitbuf=bitbs
	ld	(bitbuf),hl
	ld	hl,counting
	inc	(hl)

hmnext:	ld	hl,littr
	call	nextsymbol
	ld	a,d
	dec	a
	or	e
	ret	z
	ld	a,(zipeof)
	and	1
	ret	nz

	ld	a,d
	or	a
	jr	nz,hmsym
	ld	a,e
	call	outb
	jr	hmnext

hmsym:	dec	e
	ld	d,0
	ld	hl,lenex
	add	hl,de
	ld	a,(hl)
	ld	hl,0
	or	a
	jr	z,hmnlen
	push	de
	call	readbits
	pop	de
hmnlen:	push	hl
	ld	hl,lenbas
	add	hl,de
	add	hl,de
	ld	a,(hl)
	inc	hl
	ld	h,(hl)
	ld	l,a
	pop	de
	add	hl,de
	push	hl

	ld	hl,disttr
	call	nextsymbol
	ld	hl,dstex
	add	hl,de
	ld	a,(hl)
	ld	hl,0
	or	a
	jr	z,hmndst
	push	de
	call	readbits
	pop	de
hmndst:	push	hl
	ld	hl,dstbas
	add	hl,de
	add	hl,de
	ld	a,(hl)
	inc	hl
	ld	h,(hl)
	ld	l,a
	pop	de
	add	hl,de

	pop	bc
	call	callback
	jr	hmnext
;
undeflate:
	ld	a,7fh
	ld	(omask),a

udloop:	ld	a,(zipeof)
	and	1
	ret	nz

	rd1bit
	push	af

	ld	a,2
	call	rdbybits
	or	a
	jr	nz,udnt0

	xor	a
	ld	(bleft),a
	call	rd16bits
	push	hl
	call	rd16bits
	pop	bc
	scf
	adc	hl,bc
	jr	nz,udblm

udt0lp:	ld	a,b
	or	c
	jr	z,udnext
	ld	a,(zipeof)
	and	1
	jr	nz,udpret
	push	bc
	call	getbyte
	call	outb
	pop	bc
	dec	bc
	jr	udt0lp

udnt0:	dec	a
	jr	nz,udnt1
	ld	hl,(inbufp)
	ld	(inbps),hl
	ld	a,(readpt)
	ld	(rdpts),a
	ld	hl,(bitbuf)	; H=bleft=blfts, L=bitbuf=bitbs
	ld	(bitbs),hl
	ld	hl,counting
	dec	(hl)
	ld	hl,static_pre
	ld	(inbufp),hl
	xor	a
	ld	(readpt),a
	ld	(bleft),a
	call	huffman
	jr	udnext

udnt1:	dec	a
	jr	nz,udubt
	ld	hl,0
	ld	(inbps),hl
	call	huffman

udnext:	pop	af
	or	a
	jp	z,udloop
	ret

udpret:	pop	af
	ret
udbskp:	ld	a,(zipeof)
	and	1
	jr	nz,udpret
	call	getbyte
	jr	udbskp
udblm:	call	ilprt
	db	"Block length mismatch",CR,0
	jr	udbskp
udubt:	call	ilprt
	db	"Unknown block type",CR,0
	jr	udbskp
;
; ckcon -- checks console for character; aborts if ^C
; Only really checks every 16 calls, since this is called
; from getbyte for every input byte.
;
ckcon:	ld	a,1		; modified below
	dec	a
	and	15
	ld	(ckcon+1),a	; update LD A instruction above
	ret	nz		; check every 16 calls only
	push	de
	call	2bh
	pop	de
	or	a
	ret	z
	cp	CtrlC		; ^C ?
	ret	nz		; (no, continue)
	ld	a,(curmode)	; are we writing a file?
	or	a
	jr	z,ckcon1	; (no)
	call	setout
ckcon0:	
;	ld	de,opfcb	; ckcon0 jumped to for write error
;	ld	c,fclose	; yes, close it
;	call	bdos
;	ld	de,opfcb
;	ld	c,ferase	; and delete it
;	call	bdos

	ld	de,trsDCB
	call	442Ch	; Kill does close the file
;
	call	ilprt
	db	"Partial file erased -- ",0
ckcon1:	call	ilprt0
	db	"Aborted",0
	jp	exit
;
; getusr -- gets and stores source and destination users
;
getusr: 
;
; setin, setout -- logs to source or destination user
;
setin:	
;
setout:	
setbth:	ret
;
; copy the filename from cpm FCB to trs DCB
;
cp_fn_DCB: 
	push	hl
	push	de
	push	bc
	ld	hl,trsDCB
	ld	de,trsDCB+1
	ld	bc,31  
	ld	a,20h
	ld	(hl),a
	ldir
	ld	hl,opfn
	ld	de,trsDCB
	ld	b,8
cp_fn_l01: 
	ld	a,(hl)
	inc	hl
	cp	a,20h
	jr	z,cp_fn_ex1
	ld	(de),a
	inc	de
	djnz	cp_fn_l01
cp_fn_ex1:
	ld	hl,opext
	ld	a,(hl)
	cp	a,20h
	jr	z,cp_fn_d1
	ld	b,3
	ld	a,'/'
	ld	(de),a
	inc	de
cp_fn_l02:
	ld	a,(hl)
	inc	hl
	cp	a,20h
	jr	z,cp_fn_d1
	ld	(de),a
	inc	de
	djnz	cp_fn_l02
cp_fn_d1:
	ld	a,':'
	ld	(de),a
	ld	a,(opfcb)
	or	a
	jr	z,cp_fn_end
	inc	de
	add	a,30h
	ld	(de),a
	inc	de
cp_fn_end:
	ld	a,CR
	ld	(de),a
	inc	de
	xor	a
	ld	(de),a
;	push 	de
;	ld	hl,trsDCB
;	call	pstr
;	pop	de
	ld	a,20h
	ld	(de),a

	ld 	hl,trsDCB
	ld	a,(hl)
	cp	a,41h
	jr	nc,cp_ok
	add	a,11h
	ld	(hl),a
cp_ok:
	pop	bc
	pop	de
	pop	hl
	ret		
;
; data storage . . .
;	
zipeof:	db	2
counting:
	db	0
init:
	db	0	; for bleft
	db	0	; for wrtpt
	dw	0,0	; for outpos
	dw	-1,-1	; for crc32
endinit:
inbufp:	dw	0080h
readpt:	db	80h
omask:	db	1fh
_L_table:
	db	7fh, 3fh, 1fh, 0fh
_D_shift:
	db	07h, 06h, 05h, 04h
clord:	db	16, 17, 18
	db	0, 8
	db	7, 9
	db	6, 10
	db	5, 11
	db	4, 12
	db	3, 13
	db	2, 14
	db	1, 15
lenbas:	dw	3, 4
	dw	5, 6
	dw	7, 8
	dw	9, 10
	dw	11, 13
	dw	15, 17
	dw	19, 23
	dw	27, 31
	dw	35, 43
	dw	51, 59
	dw	67, 83
	dw	99, 115
	dw	131, 163
	dw	195, 227
	dw	258
lenex:	db	0, 0
	db	0, 0
	db	0, 0
	db	0, 0
	db	1, 1
	db	1, 1
	db	2, 2
	db	2, 2
	db	3, 3
	db	3, 3
	db	4, 4
	db	4, 4
	db	5, 5
	db	5, 5
	db	0
dstbas:	dw	1, 2
	dw	3, 4
	dw	5, 7
	dw	9, 13
	dw	17, 25
	dw	33, 49
	dw	65, 97
	dw	129, 193
	dw	257, 385
	dw	513, 769
	dw	1025, 1537
	dw	2049, 3073
	dw	4097, 6145
	dw	8193, 12289
	dw	16385, 24577
dstex:	db	0, 0
	db	0, 0
	db	1, 1
	db	2, 2
	db	3, 3
	db	4, 4
	db	5, 5
	db	6, 6
	db	7, 7
	db	8, 8
	db	9, 9
	db	10, 10
	db	11, 11
	db	12, 12
	db	13, 13
static_pre:
	db	0ffh, 05bh, 000h, 06ch, 003h, 036h, 0dbh, 0b6h
	db	06dh, 0dbh, 0b6h, 06dh, 0dbh, 0b6h, 0cdh, 0dbh
	db	0b6h, 06dh, 0dbh, 0b6h, 06dh, 0dbh, 0a8h, 06dh
	db	0ceh, 08bh, 06dh, 03bh
crc32tab:	; crc32_tab[] from degzip_portable.c, takes 1k
	db	000h,000h,000h,000h,096h,030h,007h,077h
	db	02Ch,061h,00Eh,0EEh,0BAh,051h,009h,099h
	db	019h,0C4h,06Dh,007h,08Fh,0F4h,06Ah,070h
	db	035h,0A5h,063h,0E9h,0A3h,095h,064h,09Eh
	db	032h,088h,0DBh,00Eh,0A4h,0B8h,0DCh,079h
	db	01Eh,0E9h,0D5h,0E0h,088h,0D9h,0D2h,097h
	db	02Bh,04Ch,0B6h,009h,0BDh,07Ch,0B1h,07Eh
	db	007h,02Dh,0B8h,0E7h,091h,01Dh,0BFh,090h
	db	064h,010h,0B7h,01Dh,0F2h,020h,0B0h,06Ah
	db	048h,071h,0B9h,0F3h,0DEh,041h,0BEh,084h
	db	07Dh,0D4h,0DAh,01Ah,0EBh,0E4h,0DDh,06Dh
	db	051h,0B5h,0D4h,0F4h,0C7h,085h,0D3h,083h
	db	056h,098h,06Ch,013h,0C0h,0A8h,06Bh,064h
	db	07Ah,0F9h,062h,0FDh,0ECh,0C9h,065h,08Ah
	db	04Fh,05Ch,001h,014h,0D9h,06Ch,006h,063h
	db	063h,03Dh,00Fh,0FAh,0F5h,00Dh,008h,08Dh
	db	0C8h,020h,06Eh,03Bh,05Eh,010h,069h,04Ch
	db	0E4h,041h,060h,0D5h,072h,071h,067h,0A2h
	db	0D1h,0E4h,003h,03Ch,047h,0D4h,004h,04Bh
	db	0FDh,085h,00Dh,0D2h,06Bh,0B5h,00Ah,0A5h
	db	0FAh,0A8h,0B5h,035h,06Ch,098h,0B2h,042h
	db	0D6h,0C9h,0BBh,0DBh,040h,0F9h,0BCh,0ACh
	db	0E3h,06Ch,0D8h,032h,075h,05Ch,0DFh,045h
	db	0CFh,00Dh,0D6h,0DCh,059h,03Dh,0D1h,0ABh
	db	0ACh,030h,0D9h,026h,03Ah,000h,0DEh,051h
	db	080h,051h,0D7h,0C8h,016h,061h,0D0h,0BFh
	db	0B5h,0F4h,0B4h,021h,023h,0C4h,0B3h,056h
	db	099h,095h,0BAh,0CFh,00Fh,0A5h,0BDh,0B8h
	db	09Eh,0B8h,002h,028h,008h,088h,005h,05Fh
	db	0B2h,0D9h,00Ch,0C6h,024h,0E9h,00Bh,0B1h
	db	087h,07Ch,06Fh,02Fh,011h,04Ch,068h,058h
	db	0ABh,01Dh,061h,0C1h,03Dh,02Dh,066h,0B6h
	db	090h,041h,0DCh,076h,006h,071h,0DBh,001h
	db	0BCh,020h,0D2h,098h,02Ah,010h,0D5h,0EFh
	db	089h,085h,0B1h,071h,01Fh,0B5h,0B6h,006h
	db	0A5h,0E4h,0BFh,09Fh,033h,0D4h,0B8h,0E8h
	db	0A2h,0C9h,007h,078h,034h,0F9h,000h,00Fh
	db	08Eh,0A8h,009h,096h,018h,098h,00Eh,0E1h
	db	0BBh,00Dh,06Ah,07Fh,02Dh,03Dh,06Dh,008h
	db	097h,06Ch,064h,091h,001h,05Ch,063h,0E6h
	db	0F4h,051h,06Bh,06Bh,062h,061h,06Ch,01Ch
	db	0D8h,030h,065h,085h,04Eh,000h,062h,0F2h
	db	0EDh,095h,006h,06Ch,07Bh,0A5h,001h,01Bh
	db	0C1h,0F4h,008h,082h,057h,0C4h,00Fh,0F5h
	db	0C6h,0D9h,0B0h,065h,050h,0E9h,0B7h,012h
	db	0EAh,0B8h,0BEh,08Bh,07Ch,088h,0B9h,0FCh
	db	0DFh,01Dh,0DDh,062h,049h,02Dh,0DAh,015h
	db	0F3h,07Ch,0D3h,08Ch,065h,04Ch,0D4h,0FBh
	db	058h,061h,0B2h,04Dh,0CEh,051h,0B5h,03Ah
	db	074h,000h,0BCh,0A3h,0E2h,030h,0BBh,0D4h
	db	041h,0A5h,0DFh,04Ah,0D7h,095h,0D8h,03Dh
	db	06Dh,0C4h,0D1h,0A4h,0FBh,0F4h,0D6h,0D3h
	db	06Ah,0E9h,069h,043h,0FCh,0D9h,06Eh,034h
	db	046h,088h,067h,0ADh,0D0h,0B8h,060h,0DAh
	db	073h,02Dh,004h,044h,0E5h,01Dh,003h,033h
	db	05Fh,04Ch,00Ah,0AAh,0C9h,07Ch,00Dh,0DDh
	db	03Ch,071h,005h,050h,0AAh,041h,002h,027h
	db	010h,010h,00Bh,0BEh,086h,020h,00Ch,0C9h
	db	025h,0B5h,068h,057h,0B3h,085h,06Fh,020h
	db	009h,0D4h,066h,0B9h,09Fh,0E4h,061h,0CEh
	db	00Eh,0F9h,0DEh,05Eh,098h,0C9h,0D9h,029h
	db	022h,098h,0D0h,0B0h,0B4h,0A8h,0D7h,0C7h
	db	017h,03Dh,0B3h,059h,081h,00Dh,0B4h,02Eh
	db	03Bh,05Ch,0BDh,0B7h,0ADh,06Ch,0BAh,0C0h
	db	020h,083h,0B8h,0EDh,0B6h,0B3h,0BFh,09Ah
	db	00Ch,0E2h,0B6h,003h,09Ah,0D2h,0B1h,074h
	db	039h,047h,0D5h,0EAh,0AFh,077h,0D2h,09Dh
	db	015h,026h,0DBh,004h,083h,016h,0DCh,073h
	db	012h,00Bh,063h,0E3h,084h,03Bh,064h,094h
	db	03Eh,06Ah,06Dh,00Dh,0A8h,05Ah,06Ah,07Ah
	db	00Bh,0CFh,00Eh,0E4h,09Dh,0FFh,009h,093h
	db	027h,0AEh,000h,00Ah,0B1h,09Eh,007h,07Dh
	db	044h,093h,00Fh,0F0h,0D2h,0A3h,008h,087h
	db	068h,0F2h,001h,01Eh,0FEh,0C2h,006h,069h
	db	05Dh,057h,062h,0F7h,0CBh,067h,065h,080h
	db	071h,036h,06Ch,019h,0E7h,006h,06Bh,06Eh
	db	076h,01Bh,0D4h,0FEh,0E0h,02Bh,0D3h,089h
	db	05Ah,07Ah,0DAh,010h,0CCh,04Ah,0DDh,067h
	db	06Fh,0DFh,0B9h,0F9h,0F9h,0EFh,0BEh,08Eh
	db	043h,0BEh,0B7h,017h,0D5h,08Eh,0B0h,060h
	db	0E8h,0A3h,0D6h,0D6h,07Eh,093h,0D1h,0A1h
	db	0C4h,0C2h,0D8h,038h,052h,0F2h,0DFh,04Fh
	db	0F1h,067h,0BBh,0D1h,067h,057h,0BCh,0A6h
	db	0DDh,006h,0B5h,03Fh,04Bh,036h,0B2h,048h
	db	0DAh,02Bh,00Dh,0D8h,04Ch,01Bh,00Ah,0AFh
	db	0F6h,04Ah,003h,036h,060h,07Ah,004h,041h
	db	0C3h,0EFh,060h,0DFh,055h,0DFh,067h,0A8h
	db	0EFh,08Eh,06Eh,031h,079h,0BEh,069h,046h
	db	08Ch,0B3h,061h,0CBh,01Ah,083h,066h,0BCh
	db	0A0h,0D2h,06Fh,025h,036h,0E2h,068h,052h
	db	095h,077h,00Ch,0CCh,003h,047h,00Bh,0BBh
	db	0B9h,016h,002h,022h,02Fh,026h,005h,055h
	db	0BEh,03Bh,0BAh,0C5h,028h,00Bh,0BDh,0B2h
	db	092h,05Ah,0B4h,02Bh,004h,06Ah,0B3h,05Ch
	db	0A7h,0FFh,0D7h,0C2h,031h,0CFh,0D0h,0B5h
	db	08Bh,09Eh,0D9h,02Ch,01Dh,0AEh,0DEh,05Bh
	db	0B0h,0C2h,064h,09Bh,026h,0F2h,063h,0ECh
	db	09Ch,0A3h,06Ah,075h,00Ah,093h,06Dh,002h
	db	0A9h,006h,009h,09Ch,03Fh,036h,00Eh,0EBh
	db	085h,067h,007h,072h,013h,057h,000h,005h
	db	082h,04Ah,0BFh,095h,014h,07Ah,0B8h,0E2h
	db	0AEh,02Bh,0B1h,07Bh,038h,01Bh,0B6h,00Ch
	db	09Bh,08Eh,0D2h,092h,00Dh,0BEh,0D5h,0E5h
	db	0B7h,0EFh,0DCh,07Ch,021h,0DFh,0DBh,00Bh
	db	0D4h,0D2h,0D3h,086h,042h,0E2h,0D4h,0F1h
	db	0F8h,0B3h,0DDh,068h,06Eh,083h,0DAh,01Fh
	db	0CDh,016h,0BEh,081h,05Bh,026h,0B9h,0F6h
	db	0E1h,077h,0B0h,06Fh,077h,047h,0B7h,018h
	db	0E6h,05Ah,008h,088h,070h,06Ah,00Fh,0FFh
	db	0CAh,03Bh,006h,066h,05Ch,00Bh,001h,011h
	db	0FFh,09Eh,065h,08Fh,069h,0AEh,062h,0F8h
	db	0D3h,0FFh,06Bh,061h,045h,0CFh,06Ch,016h
	db	078h,0E2h,00Ah,0A0h,0EEh,0D2h,00Dh,0D7h
	db	054h,083h,004h,04Eh,0C2h,0B3h,003h,039h
	db	061h,026h,067h,0A7h,0F7h,016h,060h,0D0h
	db	04Dh,047h,069h,049h,0DBh,077h,06Eh,03Eh
	db	04Ah,06Ah,0D1h,0AEh,0DCh,05Ah,0D6h,0D9h
	db	066h,00Bh,0DFh,040h,0F0h,03Bh,0D8h,037h
	db	053h,0AEh,0BCh,0A9h,0C5h,09Eh,0BBh,0DEh
	db	07Fh,0CFh,0B2h,047h,0E9h,0FFh,0B5h,030h
	db	01Ch,0F2h,0BDh,0BDh,08Ah,0C2h,0BAh,0CAh
	db	030h,093h,0B3h,053h,0A6h,0A3h,0B4h,024h
	db	005h,036h,0D0h,0BAh,093h,006h,0D7h,0CDh
	db	029h,057h,0DEh,054h,0BFh,067h,0D9h,023h
	db	02Eh,07Ah,066h,0B3h,0B8h,04Ah,061h,0C4h
	db	002h,01Bh,068h,05Dh,094h,02Bh,06Fh,02Ah
	db	037h,0BEh,00Bh,0B4h,0A1h,08Eh,00Ch,0C3h
	db	01Bh,0DFh,005h,05Ah,08Dh,0EFh,002h,02Dh
;
; uninitialized storage
;
oldstk:	ds	2		; also end of initialised data
inusr:	ds	1
outusr:	ds	1
mode:	ds	1
opts:	ds	1
junk:	ds	STRSIZ
lfh:				; data read from local file header
vnte:	ds	2		; version
gpbf:	ds	2		; general purpose bit flag
cm:	ds	2		; compression method
lmft:	ds	2		; file last modification time
lmfd:	ds	2		; file last modification date
crc:	ds	4		; CRC-32 of uncompressed data
cs:	ds	4		; compressed size
ucs:	ds	4		; uncompressed size
fnl:	ds	2		; file name length
efl:	ds	2		; extra field length
endlfh:	ds	1		; marker for end of lfh data; also,
				; zero byte is written here by getstring
opfcb:	ds	1		; output file control block
opfn:	ds	8
opext:	ds	3
	ds	24
trsDCB: ds	32		; DCB for TRS80
trsBUF:	ds	256
;mtchfcb:
;	ds	11
; note that as indicated above, bitbuf must be the byte before bleft
bitbuf:	ds	1
vars:
bleft:	ds	1
wrtpt:	ds	1
outpos:	ds	4
crc32:	ds	4
curmode:
	ds	1
opbuf:	ds	128
L_table:
	ds	1
D_shift:
	ds	1
urV:	ds	1
nchar:	ds	1
lchar:	ds	1
ExState:
	ds	1
Len:	ds	2
ltp:	ds	1
mml:	ds	1
dictb:	ds	1
noswps:	ds	1
entrs:	ds	2
lbl:	ds	1
treep:	ds	2
lenp:	ds	2
nodes:	ds	2
nrsym:	ds	2
nnode:	ds	2
bcode:	ds	2
bmask:	ds	2
blcnt:	ds	2 * maxcl + 2
ncode:	ds	2 * maxcl + 2
hlit:	ds	2
hdist:	ds	1
inbps:	ds	2

; Keep bitbs and blfts wrapped together
; so we can pick them up with a single 16bit register
rdpts:	ds	1
bitbs:	ds	1

blfts:	ds	1

; ---  used by the SHRINK method only ---
oldcode:
	ds	2
offset:	ds	2	; This variable is probably not necessary
codesize:
	ds	1
maxcode:
	ds	2
free_ent:
	ds	2
finchar:
	ds	1
; --- --- --- --- --- --- --- --- --- ---

stackp:	ds	2
incode:	ds	2
code:	ds	2
outbuf:
suffix_of:
	ds	8192
prefix_of:
Slen:
followers:
stack:	ds	8192 - 2
lenld:	ds	nrlit + nrdist
cltr:	ds	4 * nrcl
littr:	ds	4 * nrlit
disttr:	ds	4 * nrdist
endtr:
	ds	8192 + 2 - (endtr - lenld)
endaddr: ds     1	; must be no vars/data beyond this point

