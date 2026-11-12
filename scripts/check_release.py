#!/usr/bin/env python3
"""Release gate (docs/release.md §5): fail if the public tree or a package in dist/ carries a secret, owner data,
a local path, a third-party logo or private code. From PadTerm's scripts/check_release.py, extended for PadTube.

usage: check_release.py [tree]   tree: the export (scripts/export_public.sh), default build/public-repo; its dist/
holds the release files, built there with scripts/package_all.sh
Words of your own (name, device serial and UDID, Wi-Fi names, host names, account names), one per line, go in the
git-ignored build/release_denylist.txt of the private repository. A hit names the file and the word's line number,
never the word.
"""
import hashlib, io, pathlib, re, subprocess, sys, tarfile, tempfile, zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
TREE = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / "build/public-repo"
SECRET = {
    "private key": rb"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----\s+[A-Za-z0-9+/=]{40,}",
    "openssh key body": b"b3BlbnNzaC1" + b"rZXktdjE",
    "GitHub token": rb"(ghp_|gho_|ghs_|ghu_|github_pat_)[A-Za-z0-9_]{16,}",
    "Google API key": rb"AIza[0-9A-Za-z_-]{35}",
    "Google OAuth refresh token": rb"\b1//0[0-9A-Za-z_-]{30,}",
    "Google OAuth access token": rb"\bya29\.[0-9A-Za-z_-]{20,}",
    "Google OAuth client secret": rb"GOCSPX-[0-9A-Za-z_-]{20,}",
    "AWS key": rb"AKIA[0-9A-Z]{16}",
    "JWT": rb"eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}",
    "URL with password": rb"[a-z]+://[^:/\s\"'@]+:[^@/\s\"']+@[^/\s\"']+",
    "cookie": rb"\b(SAPISID|__Secure-[0-9]PSID|LOGIN_INFO)=",
}
LOCAL = {
    "home path": rb"/(Users|home)/[a-z][a-z0-9_-]+/",
    "LAN address": rb"\b(192\.168|10\.\d{1,3}|172\.(1[6-9]|2\d|3[01])|100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7]))\.\d{1,3}\.\d{1,3}\b",
    "machine name": rb"\b[a-z0-9-]+\.local\b",
    "Claude session folder": rb"claude-\d+/-Users-",
}
ALLOW = {"machine name": {"scripts/check_release.py"}, "home path": {"scripts/check_release.py"}}
PRIVATE_PATH = re.compile(r"^(local/|docs/STATUS\.md$|docs/design/reference/|docs/research/|tests/artifacts/|"
                          r"tests/device/joint_padbook\.py$|assets/icons/owner/|assets/art/)")
BAD_NAME = re.compile(r"(^|/)(id_(rsa|ed25519|ecdsa)[^/]*|[^/]*\.(key|pem|p12|mobileprovision|jsonl|ips|sqlite|db)|"
                      r"\.env[^/]*|[^/]*credentials[^/]*|\.claude(/.*)?)$")
IMAGE = re.compile(r"\.(png|jpe?g|gif|tiff?|heic|webp|mov|mp4)$", re.I)
PUBLIC_IMAGE = re.compile(r"^docs/images/[a-z0-9-]+\.(png|jpg|gif)$")  # each one looked at by eye before a release

problems = []
dl = ROOT / "build/release_denylist.txt"
if not dl.exists():
    problems.append("no build/release_denylist.txt: add the owner's words, one per line")
deny = [(i + 1, re.compile(re.escape(w.strip().encode()), re.I)) for i, w in
        enumerate(dl.read_text().splitlines() if dl.exists() else []) if w.strip()]
# Icon option A (D47) must not ship: its files' hashes, from the private tree.
owner_icons = {hashlib.sha256(p.read_bytes()).hexdigest() for p in (ROOT / "assets/icons/owner").glob("*.png")}


def scan(name, data, tree):
    for group, table in (("secret", SECRET), ("local", LOCAL)):
        for label, rx in table.items():
            if tree and name in ALLOW.get(label, ()):
                continue
            n = len(re.findall(rx, data))
            if n:
                problems.append(f"{group}: {label} x{n} in {name}")  # never the value
    for i, rx in deny:
        if rx.search(data):
            problems.append(f"denylist word #{i} in {name}")


if not (TREE / ".git").exists():
    sys.exit(f"no export at {TREE}: run scripts/export_public.sh first")
files = subprocess.run(["git", "ls-files", "--others", "--cached", "--exclude-standard", "-z"], cwd=TREE,
                       capture_output=True, check=True).stdout.split(b"\0")
files = [f.decode() for f in files if f]
for f in files:
    p = TREE / f
    if not p.is_file():
        continue
    for i, rx in deny:
        if rx.search(f.encode()):
            problems.append(f"denylist word #{i} in a file name: {f}")
    if PRIVATE_PATH.search(f) or BAD_NAME.search(f) or "__pycache__" in f:
        problems.append(f"file must not be published: {f}")
    if IMAGE.search(f) and not PUBLIC_IMAGE.search(f):
        problems.append(f"image outside docs/images/: {f}")
    data = p.read_bytes()
    if hashlib.sha256(data).hexdigest() in owner_icons:
        problems.append(f"icon option A in the tree: {f}")
    scan(f, data, True)
    if p.stat().st_size > 1_000_000:  # the largest source file is a JSON fixture of 140 KB
        problems.append(f"large file: {f} {p.stat().st_size} bytes")

# the release files are built in the export (scripts/package_all.sh there), so they come from the public tree only
dist = sorted((TREE / "dist").glob("*"))
newest = max((TREE / f).stat().st_mtime for f in files if f.split("/")[0] in ("core", "ios", "third_party", "tools") and (TREE / f).is_file())
with tempfile.TemporaryDirectory() as tmp:
    for pkg in dist:
        if pkg.stat().st_mtime < newest:
            problems.append(f"stale package, built before the newest source: {pkg.name}")
        d = pathlib.Path(tmp) / pkg.name
        d.mkdir()
        if pkg.suffix == ".ipa":
            zipfile.ZipFile(pkg).extractall(d)
        elif pkg.suffix == ".deb":
            subprocess.run(["dpkg-deb", "-x", str(pkg), str(d)], check=True)
            scan(f"{pkg.name}:control", subprocess.run(["dpkg-deb", "-f", str(pkg)], capture_output=True, check=True).stdout, False)
            tar = subprocess.run(["dpkg-deb", "--fsys-tarfile", str(pkg)], capture_output=True, check=True).stdout
            with tarfile.open(fileobj=io.BytesIO(tar)) as t:  # a tar entry records the builder's login name
                if {(m.uname, m.gname) for m in t.getmembers()} != {("root", "root")}:
                    problems.append(f"tar owner in {pkg.name} is not root")
        else:
            continue
        for p in d.rglob("*"):
            if not p.is_file():
                continue
            rel = f"{pkg.name}:{p.relative_to(d)}"
            data = p.read_bytes()
            if hashlib.sha256(data).hexdigest() in owner_icons:
                problems.append(f"icon option A in a package: {rel}")
            if p.name in ("tbjs",) or "/js/" in str(p) or b"PTSELFTEST" in data:
                problems.append(f"test code in a package: {rel}")
            if p.name == "PadTube" and (b"PWBrowserController" in data or b"PadWeb" in data):
                problems.append(f"private PadWeb code in a package: {rel}")
            scan(rel, data, False)

mail = subprocess.run(["git", "config", "user.email"], cwd=TREE, capture_output=True, text=True).stdout.strip()
if not mail.endswith("@users.noreply.github.com"):
    problems.append("commit identity: git user.email of the export is not a GitHub noreply address")

print(f"checked {len(files)} files in {TREE.name} and {len(dist)} packages")
for x in problems:
    print("FAIL", x)
print("ok: nothing found" if not problems else f"{len(problems)} problems")
sys.exit(1 if problems else 0)
