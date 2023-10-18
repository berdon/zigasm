; MOV al, 0
; MOV cl, 1
; MOV dl, 2
; MOV bl, 3
; MOV ah, 4
; MOV ch, 5
; MOV dh, 6
; MOV bh, 7
; MOV ax, 0
; MOV cx, 1
; MOV dx, 2
; MOV bx, 3
Bits 32
org 0x7c00
jmp 0x7c00
Bits 32
MOV eax, 3
Bits 16
MOV eax, 6