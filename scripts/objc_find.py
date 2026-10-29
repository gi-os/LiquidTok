# objc_find.py <macho> <selector-regex>  (python3 -I): the classes, metaclasses and categories implementing
# matching methods, with IMP addresses for objc_dis.py.
import re, struct, sys
path, pat = sys.argv[1], re.compile(sys.argv[2])
d = open(path, "rb").read()
ncmds = struct.unpack_from("<I", d, 16)[0]
off, segs, sects = 32, [], {}
for _ in range(ncmds):
    cmd, size = struct.unpack_from("<II", d, off)
    if cmd == 0x19:
        vmaddr, vmsize, fileoff, _ = struct.unpack_from("<QQQQ", d, off + 24)
        segs.append((vmaddr, vmsize, fileoff))
        for i in range(struct.unpack_from("<I", d, off + 64)[0]):
            s = off + 72 + i * 80
            addr, sz, foff = struct.unpack_from("<QQI", d, s + 32)
            sects[d[s:s + 16].rstrip(b"\0").decode()] = (addr, sz)
    off += size
base = min(v for v, sz, f in segs if sz)
def fo(vm):
    for v, sz, f in segs:
        if v <= vm < v + sz: return f + (vm - v)
def ptr(vm):
    o = fo(vm)
    if o is None: return 0
    raw = struct.unpack_from("<Q", d, o)[0]
    if raw >> 63: return 0
    t = raw & 0xFFFFFFFFF
    return t if t >= base else base + t
def cstr(vm):
    o = fo(vm); return "?" if o is None else d[o:d.index(b"\0", o)].decode(errors="replace")
def i32(vm): return struct.unpack_from("<i", d, fo(vm))[0]
def methods(ml):
    if not ml or fo(ml) is None: return []
    flags, count = struct.unpack_from("<II", d, fo(ml)); es = flags & 0xFFFC; out = []
    for k in range(count):
        e = ml + 8 + k * es
        if flags & 0x80000000: out.append((cstr(ptr(e + i32(e))), e + 8 + i32(e + 8)))
        else: out.append((cstr(ptr(e)), ptr(e + 16)))
    return out
def ro(c): return ptr(c + 32) & ~7
a, sz = sects["__objc_classlist"]
for k in range(sz // 8):
    c = ptr(a + k * 8); r = ro(c) if c else 0
    if not r or fo(r) is None: continue
    for m, imp in methods(ptr(r + 32)):
        if pat.search(m): print("class", cstr(ptr(r + 24)), m, hex(imp))
    meta = ptr(c)
    if meta and fo(meta) is not None:
        for m, imp in methods(ptr(ro(meta) + 32)):
            if pat.search(m): print("class", cstr(ptr(r + 24)), "+" + m, hex(imp))
if "__objc_catlist" in sects:
    a, sz = sects["__objc_catlist"]
    for k in range(sz // 8):
        cat = ptr(a + k * 8)
        if not cat: continue
        for m, imp in methods(ptr(cat + 16)):
            if pat.search(m): print("category", cstr(ptr(cat)), m, hex(imp))
