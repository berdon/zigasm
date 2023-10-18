foo:
// al = 0
// cl = 1
// dl = 2
// bl = 3
// ah = 4
// ch = 5
// dh = 6
// bh = 7
// ax = 0
// cx = 1
// dx = 2
// bx = 3
@SetBitMode(32)
@SetOrigin(0x7c00)
jmp 0x7c00
@SetBitMode(32)
eax = 3
@SetBitMode(16)
eax = 6