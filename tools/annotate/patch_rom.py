import sys

rom_path, out_path = sys.argv[1:3]
d = bytearray(open(rom_path, 'rb').read())
targets = [0xE100, 0xE1C1, 0xE203, 0xE278, 0xE29A, 0xE2F7, 0xE319, 0xE348, 0xE3AC, 0xE3BD,
           0x2D27, 0x364F, 0x3A55, 0x3E3E]
stub = 0x3F40
d[0:3] = bytes([0x21, stub >> 8, stub & 0xFF])
p = stub
for t in targets:
    d[p:p + 3] = bytes([0x20, t >> 8, t & 0xFF])
    p += 3
d[p:p + 3] = bytes([0x21, 0x02, 0x00])
open(out_path, 'wb').write(d)
