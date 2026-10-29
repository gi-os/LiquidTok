# objc_dis.py <macho> <start-hex> <end-hex>  (python3 -I): disassembles a method (llvm-objdump) and names its
# objc_msgSend stubs, selrefs, classrefs and strings; find IMP addresses with objc_find.py.
import re, struct, subprocess, sys
path, start, end = sys.argv[1], sys.argv[2], sys.argv[3]
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
base = segs[1][0] if segs[0][1] == 0 else segs[0][0]
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
    o = fo(vm)
    return None if o is None else d[o:d.index(b"\0", o)].decode(errors="replace")
def insec(vm, name):
    if name not in sects: return False
    a, sz = sects[name]; return a <= vm < a + sz
def classname(c):
    if not c or fo(c) is None: return "external class"
    r = ptr(c + 32) & ~7
    return cstr(ptr(r + 24)) if r else "?"
def decode_adrp(w, pc):
    immlo = (w >> 29) & 3; immhi = (w >> 5) & 0x7FFFF
    imm = ((immhi << 2) | immlo) << 12
    if imm & (1 << 32): imm -= 1 << 33
    return (pc & ~0xFFF) + imm
def stub_sel(t):
    o = fo(t); w0, w1 = struct.unpack_from("<II", d, o)
    if (w0 & 0x9F000000) != 0x90000000: return None
    page = decode_adrp(w0, t); imm12 = ((w1 >> 10) & 0xFFF) * 8
    return cstr(ptr(page + imm12))
def name(vm):
    if insec(vm, "__objc_selrefs"): return "sel " + str(cstr(ptr(vm)))
    if insec(vm, "__objc_classrefs"): return "class " + classname(ptr(vm))
    if insec(vm, "__objc_superrefs"): return "super " + classname(ptr(vm))
    if insec(vm, "__cfstring"): return "@\"%s\"" % cstr(ptr(vm + 16))
    if insec(vm, "__cstring"): return "\"%s\"" % cstr(vm)
    return None
out = subprocess.run(["xcrun", "llvm-objdump", "-d", "--no-show-raw-insn", "--start-address=" + start, "--stop-address=" + end, path], capture_output=True, text=True).stdout
pages = {}
for line in out.splitlines():
    m = re.match(r"\s*([0-9a-f]+):\s+(\S+)\s*(.*)", line)
    if not m: continue
    pc, op, args = int(m.group(1), 16), m.group(2), m.group(3)
    note = ""
    if op == "adrp":
        r = args.split(",")[0]; pages[r] = int(args.split(",")[1].split()[0], 16)
    elif op in ("ldr", "add") and "[" in args or op == "add":
        mm = re.match(r"(\w+), \[?(\w+), #(0x[0-9a-f]+|\d+)", args)
        if mm and mm.group(2) in pages:
            n = name(pages[mm.group(2)] + int(mm.group(3), 0))
            if n: note = n
    elif op in ("bl", "b"):
        t = int(args.split()[0], 16)
        if insec(t, "__objc_stubs"): note = "-> [" + str(stub_sel(t)) + "]"
    if note: print("%x  %s %s   ; %s" % (pc, op, args.split("<")[0].strip(), note))
