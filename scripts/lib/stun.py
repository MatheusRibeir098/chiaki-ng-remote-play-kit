#!/usr/bin/env python3
"""Utilitário STUN (RFC 5389, só stdlib) usado por 00-check-env.sh e 30-stun-redirect.sh.

Subcomandos:
  test  [--timeout S] host:port ...   -> uma linha por host: STATUS host:port ms
                                          STATUS ∈ {OK, BLOCKED, DNS}
  nat   [--timeout S]                 -> consulta 3 servidores pelo MESMO socket e
                                          imprime "cone" ou "symmetric" + portas mapeadas
  list  [--count N]                   -> imprime os N primeiros hosts da lista
                                          always-online-stun (fallback embutido se offline)
"""
import argparse
import concurrent.futures as cf
import os
import socket
import struct
import sys
import time
import urllib.request

MAGIC = 0x2112A442
LIST_URL = "https://raw.githubusercontent.com/pradt2/always-online-stun/master/valid_hosts.txt"
# Os 7 primeiros da lista em set/2026 — exatamente os que redes corporativas costumam bloquear.
FALLBACK_LIST = [
    "stun.smslisto.com:3478", "stun.freevoipdeal.com:3478", "stun.voipbuster.com:3478",
    "stun.kotter.net:3478", "stun.voipconnect.com:3478", "stun.easyvoip.com:3478",
    "stun.sipdiscount.com:3478",
]
NAT_PROBES = [("stun.l.google.com", 19302), ("stun1.l.google.com", 19302), ("stun.cloudflare.com", 3478)]


def _request() -> bytes:
    return struct.pack(">HHI12s", 0x0001, 0, MAGIC, os.urandom(12))


def _mapped_port(data: bytes):
    """Extrai a porta do XOR-MAPPED-ADDRESS (0x0020) ou MAPPED-ADDRESS (0x0001)."""
    i = 20
    while i + 4 <= len(data):
        t, ln = struct.unpack(">HH", data[i:i + 4])
        v = data[i + 4:i + 4 + ln]
        if t == 0x0020 and len(v) >= 4:
            return struct.unpack(">H", v[2:4])[0] ^ (MAGIC >> 16)
        if t == 0x0001 and len(v) >= 4:
            return struct.unpack(">H", v[2:4])[0]
        i += 4 + ln + ((4 - ln % 4) % 4)
    return None


def probe(hostport: str, timeout: float):
    host, _, port = hostport.rpartition(":")
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(timeout)
    t0 = time.time()
    try:
        s.sendto(_request(), (host, int(port)))
        s.recvfrom(2048)
        return "OK", hostport, int((time.time() - t0) * 1000)
    except socket.gaierror:
        return "DNS", hostport, 0
    except (socket.timeout, OSError):
        return "BLOCKED", hostport, int((time.time() - t0) * 1000)
    finally:
        s.close()


def cmd_test(args):
    with cf.ThreadPoolExecutor(max_workers=min(32, max(1, len(args.hosts)))) as ex:
        for status, hp, ms in ex.map(lambda h: probe(h, args.timeout), args.hosts):
            print(f"{status} {hp} {ms}")


def cmd_nat(args):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(args.timeout)
    s.bind(("", 0))
    ports = []
    for host, port in NAT_PROBES:
        try:
            s.sendto(_request(), (host, port))
            data, _ = s.recvfrom(2048)
            p = _mapped_port(data)
            if p is not None:
                ports.append(p)
        except OSError:
            continue
    s.close()
    if len(ports) < 2:
        print("unknown", *ports)
        return 1
    print("cone" if len(set(ports)) == 1 else "symmetric", *ports)
    return 0


def cmd_list(args):
    hosts = []
    try:
        with urllib.request.urlopen(LIST_URL, timeout=8) as r:
            hosts = [ln.strip() for ln in r.read().decode().splitlines() if ln.strip()]
    except Exception:  # offline, bloqueado, etc. -> fallback embutido
        hosts = FALLBACK_LIST
    for h in hosts[: args.count]:
        print(h)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("test"); p.add_argument("--timeout", type=float, default=3.0); p.add_argument("hosts", nargs="+")
    p = sub.add_parser("nat"); p.add_argument("--timeout", type=float, default=4.0)
    p = sub.add_parser("list"); p.add_argument("--count", type=int, default=20)
    args = ap.parse_args()
    rc = {"test": cmd_test, "nat": cmd_nat, "list": cmd_list}[args.cmd](args)
    sys.exit(rc or 0)


if __name__ == "__main__":
    main()
