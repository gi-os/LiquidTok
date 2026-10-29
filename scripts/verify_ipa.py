# verify_ipa.py <decrypted.ipa>   (python3 -I; macOS: needs /usr/bin/openssl and the system root keychain)
#
# The base IPA is a decrypted App Store TikTok from a stranger's GitHub release, so before anything is
# injected into it this checks how much of it is still Apple's build: every Mach-O in the app and its
# frameworks carries its App Store signature (a CMS by "Apple iPhone OS Application Signing" over the code
# directory, chained to Apple Root CA); every page outside the FairPlay-encrypted range hashes to what that
# code directory says, the header too once its cryptid is put back to 1 (so no load command, such as an
# extra dylib, was added); and every resource the bundles seal (CodeResources, itself sealed by the code
# directory) is there unchanged, with nothing unsealed added. What it can't see: Apple hashed the encrypted
# pages, so the decrypted code itself (__TEXT) has nothing to compare against. App extensions are skipped:
# the sign job strips them. Exits non-zero, naming what differs.
import hashlib
import os
import plistlib
import re
import struct
import subprocess
import sys
import tempfile
import zipfile

SKIP = ("PlugIns/", "Extensions/", "Watch/", "AppClips/")
HASHES = {1: hashlib.sha1, 2: hashlib.sha256, 3: lambda: _Trunc(hashlib.sha256()), 4: hashlib.sha384}
LEAF = "Apple iPhone OS Application Signing"
MACHO = (b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf")


class _Trunc:  # hash type 3: sha256 truncated to 20 bytes
    def __init__(self, h): self.h = h
    def update(self, b): self.h.update(b)
    def digest(self): return self.h.digest()[:20]


def fail(msg):
    print(f"verify_ipa: FAIL: {msg}")
    sys.exit(1)


def apple_root(tmp):
    pem = os.path.join(tmp, "apple-root.pem")
    out = subprocess.run(["/usr/bin/security", "find-certificate", "-a", "-c", "Apple Root CA", "-p",
                          "/System/Library/Keychains/SystemRootCertificates.keychain"],
                         capture_output=True, text=True, check=True).stdout
    certs = [c + "-----END CERTIFICATE-----\n" for c in out.split("-----END CERTIFICATE-----") if "BEGIN" in c]
    open(pem, "w").write("".join(certs))
    return pem


def slices(data):
    magic = struct.unpack_from(">I", data, 0)[0]
    if magic in (0xCAFEBABE, 0xCAFEBABF):
        n = struct.unpack_from(">I", data, 4)[0]
        wide = magic == 0xCAFEBABF
        for i in range(n):
            if wide:
                _, _, off, size, _ = struct.unpack_from(">iiQQI", data, 8 + i * 32)
            else:
                _, _, off, size, _ = struct.unpack_from(">iiIII", data, 8 + i * 20)
            yield off, size
    elif struct.unpack_from("<I", data, 0)[0] in (0xFEEDFACF, 0xFEEDFACE):
        yield 0, len(data)
    else:
        raise ValueError("not a Mach-O")


def check_macho(name, data, root, tmp):
    """Returns the code directory's special slots {-1: Info.plist hash, -3: CodeResources hash}, and the
    hash function, from the arm64 slice (the only one shipped)."""
    specials, hasher = None, None
    for base, size in slices(data):
        m = memoryview(data)[base:base + size]
        ncmds = struct.unpack_from("<I", m, 16)[0]
        off, sig, crypt = 32, None, None
        for _ in range(ncmds):
            cmd, csize = struct.unpack_from("<II", m, off)
            if cmd == 0x1D:  # LC_CODE_SIGNATURE
                sig = struct.unpack_from("<II", m, off + 8)
            elif cmd in (0x21, 0x2C):  # LC_ENCRYPTION_INFO(_64): cryptoff, cryptsize, cryptid
                crypt = (off,) + struct.unpack_from("<III", m, off + 8)
            off += csize
        if not sig:
            fail(f"{name}: no code signature")
        blob = bytes(m[sig[0]:sig[0] + sig[1]])
        magic, _, count = struct.unpack_from(">III", blob, 0)
        if magic != 0xFADE0CC0:
            fail(f"{name}: not an embedded signature")
        index = {t: o for t, o in (struct.unpack_from(">II", blob, 12 + i * 8) for i in range(count))}
        if 0 not in index or 0x10000 not in index:
            fail(f"{name}: no code directory or no CMS signature")
        cd_off = index[0]
        cd_len = struct.unpack_from(">I", blob, cd_off + 4)[0]
        cd = blob[cd_off:cd_off + cd_len]
        cms_len = struct.unpack_from(">I", blob, index[0x10000] + 4)[0]
        cms = blob[index[0x10000] + 8:index[0x10000] + cms_len]

        # Apple's signature over this code directory.
        cdp, cmsp, signer = (os.path.join(tmp, f) for f in ("cd.bin", "cms.der", "signer.pem"))
        open(cdp, "wb").write(cd)
        open(cmsp, "wb").write(cms)
        r = subprocess.run(["/usr/bin/openssl", "cms", "-verify", "-binary", "-inform", "DER", "-in", cmsp,
                            "-content", cdp, "-CAfile", root, "-purpose", "any", "-signer", signer,
                            "-out", os.devnull], capture_output=True, text=True)
        if r.returncode != 0:
            fail(f"{name}: Apple's signature doesn't verify over the code directory: {r.stderr.strip()}")
        subject = subprocess.run(["/usr/bin/openssl", "x509", "-noout", "-subject", "-in", signer],
                                 capture_output=True, text=True).stdout
        if LEAF not in subject:
            fail(f"{name}: signed by {subject.strip()}, not {LEAF}")

        # Every page Apple's hashes can speak for against the code directory.
        (_, _, version, _, hash_off, _, nspecial, ncode, limit, hsize, htype, _, page_log) = \
            struct.unpack_from(">IIIIIIIIIBBBB", cd, 0)
        if version >= 0x20300:
            limit64 = struct.unpack_from(">Q", cd, 56)[0]
            limit = limit64 or limit
        if htype not in HASHES:
            fail(f"{name}: unknown hash type {htype}")
        page = 1 << page_log if page_log else limit
        encrypted, patched = range(0), {}
        if crypt:
            lc, cryptoff, cryptsize, cryptid = crypt
            if cryptid != 0:
                fail(f"{name}: still encrypted (cryptid {cryptid})")
            if cryptoff % page or cryptsize % page:
                fail(f"{name}: encrypted range isn't page aligned")
            encrypted = range(cryptoff // page, (cryptoff + cryptsize) // page)
            # Apple hashed the header with cryptid 1, as it ships.
            first = lc // page
            pg = bytearray(m[first * page:(first + 1) * page])
            struct.pack_into("<I", pg, lc + 16 - first * page, 1)
            patched[first] = bytes(pg)
        bad = []
        for i in range(ncode):
            if i in encrypted:
                continue
            h = HASHES[htype]()
            h.update(patched.get(i, m[i * page:min((i + 1) * page, limit)]))
            if h.digest()[:hsize] != cd[hash_off + i * hsize:hash_off + (i + 1) * hsize]:
                bad.append(i)
        if bad:
            fail(f"{name}: {len(bad)} page(s) outside the encrypted code differ from Apple's (first at page {bad[0]})")
        specials = {-s: cd[hash_off - s * hsize:hash_off - (s - 1) * hsize] for s in range(1, nspecial + 1)}
        hasher = (HASHES[htype], hsize)
    return specials, hasher


def check_bundle(z, prefix, exe, root, tmp):
    """A bundle at prefix (".../X.app/" or ".../Y.framework/"): its executable, then its sealed resources.
    Returns the set of paths it accounts for."""
    data = z.read(prefix + exe)
    specials, (hfn, hsize) = check_macho(prefix + exe, data, root, tmp)
    seen = {prefix + exe}
    cr_path = prefix + "_CodeSignature/CodeResources"
    cr = z.read(cr_path)
    h = hfn(); h.update(cr)
    if specials.get(-3) != h.digest()[:hsize]:
        fail(f"{cr_path} isn't the one Apple sealed")
    seen.add(cr_path)
    info = prefix + "Info.plist"
    if info in z.NameToInfo:
        h = hfn(); h.update(z.read(info))
        if specials.get(-1) != h.digest()[:hsize]:
            print(f"verify_ipa: note: {info} differs from Apple's (decryptors often edit it; not code)")
        seen.add(info)
    seal = plistlib.loads(cr)
    files = seal.get("files2", {})
    # Files the seal leaves out on purpose (PkgInfo, .DS_Store, FairPlay's SC_Info) count as accounted for.
    omit = [re.compile(k) for k, v in seal.get("rules2", {}).items() if isinstance(v, dict) and v.get("omit")]
    for n in z.namelist():
        if n.startswith(prefix) and not n.endswith("/") and any(o.search(n[len(prefix):]) for o in omit):
            seen.add(n)
    for rel, entry in files.items():
        path = prefix + rel
        if path.startswith(tuple(prefix + s for s in SKIP)) or rel.startswith(SKIP):
            continue
        entry = entry if isinstance(entry, dict) else {"hash": entry}
        if "cdhash" in entry:  # nested code (a framework), checked as its own bundle
            continue
        if "symlink" in entry:
            seen.add(path)
            continue
        # FairPlay's files (decryptors drop them) and Mach-Os: the seal hashes code as shipped, encrypted;
        # each Mach-O is checked against its own code directory instead.
        if "/SC_Info/" in "/" + rel:
            seen.add(path)
            continue
        if path not in z.NameToInfo:
            if entry.get("optional"):
                continue
            fail(f"{path} is missing")
        if z.open(path).read(4) in MACHO:
            if path not in seen:
                check_macho(path, z.read(path), root, tmp)
                seen.add(path)
            continue
        want = entry.get("hash2")
        got = hashlib.sha256(z.read(path)).digest() if want is not None else hashlib.sha1(z.read(path)).digest()
        if got != (want if want is not None else entry["hash"]):
            fail(f"{path} differs from Apple's")
        seen.add(path)
    return seen


def main():
    ipa = sys.argv[1]
    with zipfile.ZipFile(ipa) as z, tempfile.TemporaryDirectory() as tmp:
        root = apple_root(tmp)
        names = [n for n in z.namelist() if not n.endswith("/")]
        apps = sorted({n.split("/")[1] for n in names if n.startswith("Payload/") and n.count("/") >= 2})
        if len(apps) != 1 or not apps[0].endswith(".app"):
            fail(f"expected one app in Payload, found {apps}")
        app = f"Payload/{apps[0]}/"
        plist = plistlib.loads(z.read(app + "Info.plist"))
        seen = check_bundle(z, app, plist["CFBundleExecutable"], root, tmp)
        bundles = 1
        for fw in sorted({n[:n.index(".framework/") + 11] for n in names
                          if n.startswith(app + "Frameworks/") and ".framework/" in n}):
            if fw.count(".framework/") > 1:
                continue
            fplist = plistlib.loads(z.read(fw + "Info.plist"))
            seen |= check_bundle(z, fw, fplist["CFBundleExecutable"], root, tmp)
            bundles += 1
        for dylib in [n for n in names if n.startswith(app + "Frameworks/") and n.endswith(".dylib")]:
            check_macho(dylib, z.read(dylib), root, tmp)
            seen.add(dylib)
        # Anything shipped that no seal covers (outside the skipped extensions and FairPlay's files).
        extra = [n for n in names if n.startswith(app) and n not in seen and not n[len(app):].startswith(SKIP)]
        if extra:
            fail(f"{len(extra)} file(s) no signature covers, e.g. {extra[:3]}")
        print(f"verify_ipa: OK: {plist.get('CFBundleIdentifier')} {plist.get('CFBundleShortVersionString')}, "
              f"{bundles} bundle(s) match Apple's signatures")


if __name__ == "__main__":
    main()
