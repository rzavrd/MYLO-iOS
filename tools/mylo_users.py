#!/usr/bin/env python3
"""
MYLO VPN - decide who may log in.

How it works
  * The app contains NO VPN account. After a successful login it receives the VPN username/password
    from users.json, where every user's entry is encrypted with a key made from THAT user's password
    (PBKDF2-HMAC-SHA256 -> AES-256-GCM). Wrong password = the entry cannot be opened.
  * users.private.json (this folder) is YOUR source of truth: login passwords + the VPN account in
    plain text. Keep it on your computer only. Never upload it, never put it in the app or in git.
  * `build` turns it into dist/users.json (encrypted). Upload that file to your https server (or paste
    it into Defaults.embeddedUsers in the app, see `embed`).

Commands (run from anywhere; needs:  pip install cryptography)
  python3 mylo_users.py vpn --user VPNUSER --pass VPNPASS [--rid pointtoserver.com]
  python3 mylo_users.py add alice [--password SECRET] [--name "Alice"] [--days 30]
  python3 mylo_users.py passwd alice [--password SECRET]
  python3 mylo_users.py expire alice --days 30      (or --never)
  python3 mylo_users.py remove alice
  python3 mylo_users.py list
  python3 mylo_users.py build                        (also runs after every change above)
  python3 mylo_users.py check alice SECRET           (self-test: can this login open its entry?)
  python3 mylo_users.py embed                        (prints the Swift line for Defaults.embeddedUsers)
  python3 mylo_users.py publish --scp user@host:/var/www/mylo/

A removed user is locked out the next time the app can reach users.json (app start and every few hours).
Anything a user already copied (the VPN account itself) stays valid until you change it at the provider,
so give each person their own sub-account when you can: `add alice --vpn-user X --vpn-pass Y`.
"""
import argparse, base64, hashlib, json, os, pathlib, secrets, subprocess, sys, time

try:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
except ImportError:
    sys.exit("Missing dependency. Run:  pip install cryptography")

ROOT = pathlib.Path(__file__).resolve().parent
PRIVATE = ROOT / "users.private.json"
OUT = ROOT.parent / "dist" / "users.json"
ITER = 600_000          # PBKDF2 rounds (the app reads this value from users.json)
VERSION = 1


def b64(b: bytes) -> str:
    return base64.b64encode(b).decode()


def uid(login: str) -> str:
    return hashlib.sha256(("mylo:" + login.strip().lower()).encode()).hexdigest()


def load() -> dict:
    if PRIVATE.exists():
        return json.loads(PRIVATE.read_text())
    return {"vpn": {"user": "", "pass": "", "rid": "pointtoserver.com"}, "users": {}}


def save(d: dict) -> None:
    PRIVATE.write_text(json.dumps(d, indent=2, ensure_ascii=False))
    os.chmod(PRIVATE, 0o600)


def key_for(password: str, salt: bytes, iters: int = ITER) -> bytes:
    return hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, iters, 32)


def seal(login: str, u: dict, vpn: dict) -> dict:
    v = u.get("vpn") or vpn
    if not v.get("user") or not v.get("pass"):
        sys.exit("No VPN account set. Run:  mylo_users.py vpn --user ... --pass ...")
    payload = {"name": u.get("name") or login, "vpnUser": v["user"], "vpnPass": v["pass"],
               "rid": v.get("rid") or vpn.get("rid") or "pointtoserver.com", "exp": u.get("exp")}
    i = uid(login)
    salt = base64.b64decode(u["salt"])
    nonce = secrets.token_bytes(12)
    ct = AESGCM(key_for(u["password"], salt)).encrypt(nonce, json.dumps(payload).encode(), i.encode())
    return {"s": b64(salt), "n": b64(nonce), "c": b64(ct)}      # c = ciphertext || 16-byte tag


def build(d: dict) -> None:
    users = {uid(l): seal(l, u, d["vpn"]) for l, u in d["users"].items()}
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({"v": VERSION, "iter": ITER, "users": users}, separators=(",", ":")))
    print(f"built {OUT}  ({len(users)} user{'s' if len(users) != 1 else ''})")


def opened(d: dict, login: str, password: str):
    """Independent decrypt (same steps as the app) - used by `check`."""
    f = json.loads(OUT.read_text())
    e = f["users"].get(uid(login))
    if not e:
        return None
    try:
        raw = AESGCM(key_for(password, base64.b64decode(e["s"]), f["iter"])).decrypt(
            base64.b64decode(e["n"]), base64.b64decode(e["c"]), uid(login).encode())
        return json.loads(raw)
    except Exception:
        return None


def main() -> None:
    ap = argparse.ArgumentParser(description="MYLO VPN user manager")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("vpn"); p.add_argument("--user", required=True); p.add_argument("--pass", dest="pw", required=True); p.add_argument("--rid", default="pointtoserver.com")
    p = sub.add_parser("add"); p.add_argument("login"); p.add_argument("--password"); p.add_argument("--name"); p.add_argument("--days", type=int); p.add_argument("--vpn-user"); p.add_argument("--vpn-pass")
    p = sub.add_parser("passwd"); p.add_argument("login"); p.add_argument("--password")
    p = sub.add_parser("expire"); p.add_argument("login"); p.add_argument("--days", type=int); p.add_argument("--never", action="store_true")
    p = sub.add_parser("remove"); p.add_argument("login")
    sub.add_parser("list"); sub.add_parser("build"); sub.add_parser("embed")
    p = sub.add_parser("check"); p.add_argument("login"); p.add_argument("password")
    p = sub.add_parser("publish"); p.add_argument("--scp", required=True)
    a = ap.parse_args()
    d = load()
    login = getattr(a, "login", "").strip().lower() if hasattr(a, "login") else ""

    if a.cmd == "vpn":
        d["vpn"] = {"user": a.user, "pass": a.pw, "rid": a.rid}
        save(d); build(d)
    elif a.cmd == "add":
        if not login: sys.exit("empty login")
        if login in d["users"]: sys.exit("user exists - use passwd / expire")
        pw = a.password or secrets.token_urlsafe(9)
        u = {"password": pw, "salt": b64(secrets.token_bytes(16)), "name": a.name or login,
             "exp": int(time.time() + a.days * 86400) if a.days else None}
        if a.vpn_user and a.vpn_pass: u["vpn"] = {"user": a.vpn_user, "pass": a.vpn_pass}
        d["users"][login] = u
        save(d); build(d)
        print(f"\n  login:    {login}\n  password: {pw}\n")
    elif a.cmd == "passwd":
        u = d["users"].get(login) or sys.exit("no such user")
        u["password"] = a.password or secrets.token_urlsafe(9)
        u["salt"] = b64(secrets.token_bytes(16))        # new salt: old sessions stop working
        save(d); build(d)
        print(f"\n  login:    {login}\n  password: {u['password']}\n")
    elif a.cmd == "expire":
        u = d["users"].get(login) or sys.exit("no such user")
        u["exp"] = None if a.never or not a.days else int(time.time() + a.days * 86400)
        save(d); build(d)
    elif a.cmd == "remove":
        if d["users"].pop(login, None) is None: sys.exit("no such user")
        save(d); build(d)
    elif a.cmd == "list":
        for l, u in sorted(d["users"].items()):
            exp = time.strftime("%Y-%m-%d", time.localtime(u["exp"])) if u.get("exp") else "never"
            print(f"{l:20} name={u.get('name')!s:16} expires={exp}  {'(own VPN account)' if u.get('vpn') else ''}")
        print(f"{len(d['users'])} user(s); VPN account set: {bool(d['vpn'].get('user'))}")
    elif a.cmd == "build":
        build(d)
    elif a.cmd == "check":
        r = opened(d, a.login, a.password)
        print("OK - entry opens" if r else "FAILED - wrong login/password or file out of date")
        sys.exit(0 if r else 1)
    elif a.cmd == "embed":
        if not OUT.exists(): build(d)
        s = json.dumps(OUT.read_text(), ensure_ascii=True)
        print("static let embeddedUsers = " + s)
    elif a.cmd == "publish":
        if not OUT.exists(): build(d)
        subprocess.check_call(["scp", str(OUT), a.scp])
        print("uploaded")


if __name__ == "__main__":
    main()
