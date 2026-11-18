#!/usr/bin/env python3
"""Wake-on-LAN for leo (the NAS) — backs the tommyq.cz dashboard.

leo hosts most of the services on the dashboard (via lighttpd reverse proxies).
When it sleeps, clicking a service icon wakes it, waits until the service
answers, and then opens it.

Endpoints (deployed at https://tommyq.cz/cgi/wol.cgi):
  GET  ?status   → {"up": bool, "leo": bool, "routing": bool, "ip": "…"}
                   up == leo: the NAS answers on its alive port (default SSH 22), which
                   comes up long before the Docker containers do.
                   routing: the routing stack (BRouter + tile server) accepts
                   connections on `routing_ports` — this is what the sport planner needs.
  POST ?wake     → sends a Wake-on-LAN magic packet, {"sent": true}

Used by the loading screen that lighttpd shows for leo-hosted services
(errors/status-503.html) and by the sport planner's "leo" button.

Access: LAN only (REMOTE_ADDR must be inside `lan_cidr`). From anywhere else the
CGI answers 403 and the dashboard falls back to a plain link. A POST also needs
an Origin of tommyq.cz / *.tommyq.cz (when the browser sends one).

CORS: none is set here. TurrisOS (90-turris-root.conf) already adds
`Access-Control-Allow-Origin: *` to every response, which is enough for the
simple GET/POST requests used by sport.tommyq.cz; a second header from the CGI
would make browsers reject the response (duplicate ACAO).

Config: /srv/tommyq/config/wol.conf (override with $WOL_CONF), `key=value` lines
in the same format as ~/.tommyq/wol.conf used by the `wol` helper on tiger:

  leo=aa:bb:cc:dd:ee:ff     # required for ?wake (MAC of leo)
  leo_ip=192.168.2.4        # default
  leo_broadcast=192.168.2.255   # default; see send_magic_packet()
  leo_alive_port=22         # default
  routing_ports=17777,12347 # default: BRouter, tile server (overpass is optional, left out)
  lan_cidr=192.168.2.0/24   # default; comma-separated list allowed

Unknown keys (e.g. `tiger=…`, `INTERFACE=…`) are ignored.
"""

import ipaddress
import json
import os
import re
import socket
import sys
import urllib.parse

CONF_FILE = os.environ.get("WOL_CONF", "/srv/tommyq/config/wol.conf")

DEFAULTS = {
    "leo_ip": "192.168.2.4",
    # Subnet-directed broadcast of the LAN. NOT 255.255.255.255: on the router
    # that one follows the default route and leaves via the WAN port (verified
    # with tcpdump), so it never reaches the LAN. The directed broadcast leaves
    # via br-lan. Also avoids leaking leo's MAC into the ISP's network.
    "leo_broadcast": "192.168.2.255",
    "leo_alive_port": "22",
    "routing_ports": "17777,12347",
    "lan_cidr": "192.168.2.0/24",
}

_MAC_RE = re.compile(r"^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$")
_ORIGIN_RE = re.compile(r"^https?://([a-z0-9-]+\.)*tommyq\.cz$", re.I)


def load_conf():
    conf = dict(DEFAULTS)
    try:
        with open(CONF_FILE) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, _, val = line.partition("=")
                conf[key.strip().lower()] = val.split("#", 1)[0].strip()
    except OSError:
        pass
    return conf


def respond(status, data=None, origin=""):
    """Send a JSON response (CORS is added globally by TurrisOS, see module doc)."""
    print(f"Status: {status}")
    print("Content-Type: application/json")
    print("Cache-Control: no-store")
    print()
    if data is not None:
        print(json.dumps(data, ensure_ascii=False))
    sys.exit(0)


def from_lan(conf):
    try:
        addr = ipaddress.ip_address(os.environ.get("REMOTE_ADDR", ""))
    except ValueError:
        return False
    for cidr in conf.get("lan_cidr", "").split(","):
        try:
            if addr in ipaddress.ip_network(cidr.strip(), strict=False):
                return True
        except ValueError:
            continue
    return False


def tcp_open(ip, port, timeout=1.5):
    try:
        with socket.create_connection((ip, port), timeout=timeout):
            return True
    except OSError:
        return False


def send_magic_packet(mac, broadcast):
    """UDP magic packet for `mac` to the LAN's directed broadcast, port 9.

    Needs no root and no external tool (etherwake), only SO_BROADCAST.
    """
    mb = bytes.fromhex(mac.replace(":", "").replace("-", ""))
    packet = b"\xff" * 6 + mb * 16
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        s.sendto(packet, (broadcast, 9))
    finally:
        s.close()


def main():
    origin = os.environ.get("HTTP_ORIGIN", "")
    method = os.environ.get("REQUEST_METHOD", "GET")
    if method == "OPTIONS":
        respond("204 No Content", None, origin)

    conf = load_conf()
    if not from_lan(conf):
        respond("403 Forbidden", {"error": "LAN only"}, origin)

    params = urllib.parse.parse_qs(os.environ.get("QUERY_STRING", ""), keep_blank_values=True)
    ip = conf["leo_ip"]
    try:
        alive_port = int(conf["leo_alive_port"])
    except ValueError:
        alive_port = 22

    if method == "GET" and "status" in params:
        up = tcp_open(ip, alive_port)
        ports = [int(p) for p in conf.get("routing_ports", "").split(",") if p.strip().isdigit()]
        routing = bool(up and ports and all(tcp_open(ip, p, 1.0) for p in ports))
        respond("200 OK", {"up": up, "leo": up, "routing": routing, "ip": ip}, origin)

    if "wake" in params:
        if method != "POST":
            respond("405 Method Not Allowed", {"error": "use POST"}, origin)
        if origin and not _ORIGIN_RE.match(origin):
            respond("403 Forbidden", {"error": "bad origin"}, origin)
        mac = conf.get("leo", "")
        if not _MAC_RE.match(mac):
            respond("500 Internal Server Error", {"error": "leo MAC not configured (wol.conf)"}, origin)
        try:
            send_magic_packet(mac, conf["leo_broadcast"])
        except OSError as e:
            respond("500 Internal Server Error", {"error": f"wake failed: {e}"}, origin)
        respond("200 OK", {"sent": True}, origin)

    respond("400 Bad Request", {"error": "use ?status or POST ?wake"}, origin)


if __name__ == "__main__":
    main()
