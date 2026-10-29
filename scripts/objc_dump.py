# objc_dump.py <macho> <class-regex>   (run with python3 -I)
# A poor man's class-dump for X's frameworks (thin arm64 Mach-O, chained-fixup pointers): the instance
# and class methods of the ObjC classes whose names match, and of categories on them, with type
# encodings. Pass --names to list every class name instead. How LiquidBird finds what to hook (see
# CLAUDE.md): extract Payload/Twitter.app/Twitter and Frameworks/* from the NeoFreeBird IPA first.
import re
import struct
import sys

path, arg = sys.argv[1], sys.argv[2]
d = open(path, "rb").read()
ncmds = struct.unpack_from("<I", d, 16)[0]
off, segs, sects = 32, [], {}
for _ in range(ncmds):
    cmd, size = struct.unpack_from("<II", d, off)
    if cmd == 0x19:  # LC_SEGMENT_64
        name = d[off + 8:off + 24].rstrip(b"\0").decode()
        vmaddr, vmsize, fileoff, _ = struct.unpack_from("<QQQQ", d, off + 24)
        segs.append((vmaddr, vmsize, fileoff, name))
        for i in range(struct.unpack_from("<I", d, off + 64)[0]):
            s = off + 72 + i * 80
            addr, sz, foff = struct.unpack_from("<QQI", d, s + 32)
            sects[d[s:s + 16].rstrip(b"\0").decode()] = (addr, sz, foff)
    off += size
base = next(v for v, _, _, n in segs if n == "__TEXT")


def fo(vm):
    for v, sz, f, _ in segs:
        if v <= vm < v + sz:
            return f + (vm - v)
    return None


def ptr(vm):
    o = fo(vm)
    if o is None:
        return 0
    raw = struct.unpack_from("<Q", d, o)[0]
    if raw >> 63:  # bind to another image
        return 0
    t = raw & 0xFFFFFFFFF  # chained rebase target
    return t if t >= base else base + t


def cstr(vm):
    o = fo(vm)
    return "?" if o is None else d[o:d.index(b"\0", o)].decode(errors="replace")


def i32(vm):
    return struct.unpack_from("<i", d, fo(vm))[0]


def methods(ml):
    if not ml or fo(ml) is None:
        return []
    flags, count = struct.unpack_from("<II", d, fo(ml))
    es, out = flags & 0xFFFC, []
    for k in range(count):
        e = ml + 8 + k * es
        if flags & 0x80000000:  # relative method list
            selref = e + i32(e)
            out.append((cstr(ptr(selref)) if fo(selref) is not None else "?", cstr(e + 4 + i32(e + 4))))
        else:
            out.append((cstr(ptr(e)), cstr(ptr(e + 8))))
    return out


def ro(cls):
    return ptr(cls + 32) & ~7


def show(kind, name, inst, cls):
    print(f"== {kind} {name}")
    for n, t in cls:
        print(f"  + {n}  {t}")
    for n, t in inst:
        print(f"  - {n}  {t}")


a, sz, _ = sects["__objc_classlist"]
for k in range(sz // 8):
    c = ptr(a + k * 8)
    r = ro(c) if c else 0
    if not r or fo(r) is None:
        continue
    name = cstr(ptr(r + 24))
    if arg == "--names":
        print(name)
        continue
    if not re.search(arg, name):
        continue
    meta = ptr(c)
    show("class", name, methods(ptr(r + 32)), methods(ptr(ro(meta) + 32)) if meta else [])
if arg != "--names" and "__objc_catlist" in sects:
    a, sz, _ = sects["__objc_catlist"]
    for k in range(sz // 8):
        cat = ptr(a + k * 8)
        if not cat:
            continue
        cls = ptr(cat + 8)
        clsname = cstr(ptr(ro(cls) + 24)) if cls and fo(cls) is not None else "(external)"
        if re.search(arg, clsname) or re.search(arg, cstr(ptr(cat))):
            show(f"category {cstr(ptr(cat))} on", clsname, methods(ptr(cat + 16)), methods(ptr(cat + 24)))
