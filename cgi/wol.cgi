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
  POST ?start=<svc>
                 → starts an on-demand service on leo through the Portainer API (same
                   calls docker_manager.py makes: container start / stack start).
                   {"state": "running"|"started"}; 404 for services not in the allowlist.

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
  start_<svc>=container:<name> | stack:<name>
                            # on-demand services (allowlist for ?start=<svc>, <svc> = the
                            # subdomain). Defaults: iventoy, jdownloader, filezilla.
  portainer_conf=/srv/tommyq/config/portainer.toml   # default; copy of ~/.tommyq/portainer.toml
                            # ([portainer] url / username / password / endpoint_id)

Unknown keys (e.g. `tiger=…`, `INTERFACE=…`) are ignored.
"""

import ipaddress
import json
import os
import re
import socket
import sys
import tomllib
import urllib.error
import urllib.parse
import urllib.request

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
    # On-demand services: subdomain -> what to start through Portainer.
    #   container:<name>  a stopped container inside an active stack
    #   stack:<name>      an inactive stack (Portainer removes its containers on stop)
    "start_iventoy": "stack:pxe",          # iVentoy + its nginx front (tommyq-docker stacks/pxe.yml)
    "start_jdownloader": "container:jdownloader2",
    "start_filezilla": "container:filezilla",
    "portainer_conf": "/srv/tommyq/config/portainer.toml",
}

_SVC_RE = re.compile(r"^[a-z0-9-]{1,40}$")
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


class PortainerError(Exception):
    pass


def portainer_request(base, path, method="GET", token=None, data=None, timeout=20):
    """One Portainer API call. Returns (http_status, parsed_json_or_None).

    HTTP error statuses are returned, not raised (Docker answers 304 for "already
    started"); only network failures raise PortainerError.
    """
    req = urllib.request.Request(
        base + path, method=method,
        data=json.dumps(data).encode() if data is not None else None,
        headers={"Content-Type": "application/json",
                 **({"Authorization": f"Bearer {token}"} if token else {})})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body, status = resp.read(), resp.status
    except urllib.error.HTTPError as e:
        body, status = e.read(), e.code
    except (urllib.error.URLError, OSError) as e:
        raise PortainerError(f"Portainer unreachable: {getattr(e, 'reason', e)}")
    try:
        return status, json.loads(body) if body else None
    except ValueError:
        return status, None


def start_service(conf, svc):
    """Start the on-demand service `svc` via Portainer. Returns "running" or "started".

    Mirrors docker_manager.py (`start <container>` / `stack start <stack>`); the
    credentials come from the same portainer.toml format.
    """
    kind, _, name = conf["start_" + svc].partition(":")
    try:
        with open(conf["portainer_conf"], "rb") as f:
            pcfg = tomllib.load(f)["portainer"]
        base, eid = pcfg["url"].rstrip("/"), pcfg["endpoint_id"]
        login = {"username": pcfg["username"], "password": pcfg["password"]}
    except (OSError, KeyError, ValueError) as e:
        raise PortainerError(f"portainer.toml unusable: {e.__class__.__name__}")

    status, body = portainer_request(base, "/api/auth", "POST", data=login)
    if status != 200 or not body or "jwt" not in body:
        raise PortainerError(f"Portainer login failed (HTTP {status})")
    token = body["jwt"]

    if kind == "container":
        status, containers = portainer_request(
            base, f"/api/endpoints/{eid}/docker/containers/json?all=true", token=token)
        found = next((c for c in containers or [] if f"/{name}" in c.get("Names", [])), None)
        if status != 200 or not found:
            raise PortainerError(f"container '{name}' not found")
        if found.get("State") == "running":
            return "running"
        status, _ = portainer_request(
            base, f"/api/endpoints/{eid}/docker/containers/{found['Id']}/start",
            "POST", token=token, timeout=30)
        if status not in (204, 304):
            raise PortainerError(f"container start failed (HTTP {status})")
        return "started"

    if kind == "stack":
        status, stacks = portainer_request(base, "/api/stacks", token=token)
        found = next((s for s in stacks or [] if s.get("Name", "").lower() == name.lower()), None)
        if status != 200 or not found:
            raise PortainerError(f"stack '{name}' not found")
        if found.get("Status") == 1:          # already active
            return "running"
        status, _ = portainer_request(
            base, f"/api/stacks/{found['Id']}/start?endpointId={eid}",
            "POST", token=token, timeout=60)
        if status != 200:
            raise PortainerError(f"stack start failed (HTTP {status})")
        return "started"

    raise PortainerError(f"bad start_{svc} setting")


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

    if "start" in params:
        if method != "POST":
            respond("405 Method Not Allowed", {"error": "use POST"}, origin)
        if origin and not _ORIGIN_RE.match(origin):
            respond("403 Forbidden", {"error": "bad origin"}, origin)
        svc = params["start"][0].lower()
        # Allowlist: only services that have a start_<svc> entry can be started.
        if not _SVC_RE.match(svc) or ("start_" + svc) not in conf:
            respond("404 Not Found", {"error": "unknown service"}, origin)
        try:
            state = start_service(conf, svc)
        except PortainerError as e:
            respond("502 Bad Gateway", {"error": str(e)}, origin)
        respond("200 OK", {"state": state}, origin)

    respond("400 Bad Request", {"error": "use ?status, POST ?wake or POST ?start=<svc>"}, origin)


if __name__ == "__main__":
    main()
