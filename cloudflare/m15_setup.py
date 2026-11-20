"""M15: create Cloudflare tunnel, routes, DNS, Access apps and service token (idempotent)."""
import json, os, sys, urllib.request, urllib.error

HOME = r"C:\Users\Niloy Paul"
TOKEN_FILE = os.environ.get("CF_TOKEN_FILE", "cf-token-puja.txt")
TOKEN = open(os.path.join(HOME, TOKEN_FILE), encoding="utf-8-sig").read().strip()
API = "https://api.cloudflare.com/client/v4"
ZONE_NAME = os.environ.get("CF_ZONE", "gmdalui.co.in")
LOGIN_EMAIL_DOMAINS = os.environ.get("CF_LOGIN_DOMAINS", "laserpowerinfra.com").split(",")
SERVER = "192.168.1.190"
TUNNEL_NAME = "laser-office-server"
ROUTES = [  # subdomain, port, label
    ("portal", 7777, "Master Portal"),
    ("tender-exec", 3126, "Tender Executive Dashboard"),
    ("enquiry", 4173, "Enquiry to Quotation"),
    ("bom", 4555, "BOM"),
    ("gmd-quotation", 4570, "GMD Quotation"),
    ("inspection", 5123, "Inspection Dashboard"),
    ("email-dash", 6002, "Email Dashboard"),
    ("invoice", 6004, "Invoice"),
    ("transport", 6010, "Transporter And Delivery Logs"),
    ("ceebuild", 6011, "CEEBUILD Item Dashboard"),
    ("sheets", 6321, "Sheet Automation UI"),
]


def cf(method, path, body=None):
    req = urllib.request.Request(API + path, method=method,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            d = json.load(r)
    except urllib.error.HTTPError as e:
        d = json.load(e)
    if not d.get("success"):
        sys.exit(f"FAILED {method} {path}: {d.get('errors')}")
    return d["result"]


zone = cf("GET", f"/zones?name={ZONE_NAME}")[0]
ZID, AID = zone["id"], zone["account"]["id"]
print("zone", ZID, "account", AID)

# 1. tunnel
tun = [t for t in cf("GET", f"/accounts/{AID}/cfd_tunnel?is_deleted=false&name={TUNNEL_NAME}")]
if tun:
    tun = tun[0]; print("tunnel exists", tun["id"])
else:
    tun = cf("POST", f"/accounts/{AID}/cfd_tunnel", {"name": TUNNEL_NAME, "config_src": "cloudflare"})
    print("tunnel created", tun["id"])
TID = tun["id"]
ttok = cf("GET", f"/accounts/{AID}/cfd_tunnel/{TID}/token")
tok_path = os.path.join(HOME, f"cf-tunnel-token-{ZONE_NAME}.txt")
open(tok_path, "w").write(ttok)
print("tunnel run-token saved to", tok_path)

if not tun.get("conns_active_at") and tun.get("status") == "inactive":  # brand-new tunnel only
    cf("PUT", f"/accounts/{AID}/cfd_tunnel/{TID}/configurations", {"config": {"ingress": [{"service": "http_status:404"}]}})
    print("new tunnel blocked (404) until Access is ready")

# 3. DNS
target = f"{TID}.cfargotunnel.com"
for s, _, _ in ROUTES:
    name = f"{s}.{ZONE_NAME}"
    ex = cf("GET", f"/zones/{ZID}/dns_records?name={name}")
    rec = {"type": "CNAME", "name": name, "content": target, "proxied": True, "comment": "M15 tunnel"}
    if ex:
        if ex[0]["type"] != "CNAME" or ex[0]["content"] != target:
            if ex[0].get("comment") != "M15 tunnel":
                sys.exit(f"refusing to overwrite existing record {name} -> {ex[0]['content']}")
            cf("PUT", f"/zones/{ZID}/dns_records/{ex[0]['id']}", rec)
    else:
        cf("POST", f"/zones/{ZID}/dns_records", rec)
print("DNS CNAMEs ok ->", target)

# 4. service token for n8n / Claude (Enquiry only)
st_name = "n8n-claude-enquiry-api"
sts = [t for t in cf("GET", f"/accounts/{AID}/access/service_tokens") if t["name"] == st_name]
st_path = os.path.join(HOME, f"cf-enquiry-service-token-{ZONE_NAME}.txt")
if sts:
    st = sts[0]; print("service token exists", st["client_id"])
else:
    st = cf("POST", f"/accounts/{AID}/access/service_tokens", {"name": st_name, "duration": "8760h"})
    open(st_path, "w").write(f"CF-Access-Client-Id: {st['client_id']}\nCF-Access-Client-Secret: {st['client_secret']}\n")
    print("service token created; headers saved to", st_path)

# 5. Access apps (email OTP, @laserpowerinfra.com)
idps = cf("GET", f"/accounts/{AID}/access/identity_providers")
otp = [i for i in idps if i["type"] == "onetimepin"]
if not otp:  # staff log in with an email one-time code (not "Cloudflare account" login)
    otp = [cf("POST", f"/accounts/{AID}/access/identity_providers", {"name": "Email one-time code", "type": "onetimepin", "config": {}})]
    print("created login method: email one-time PIN")
otp_ids = [otp[0]["id"]]
staff_policy = {"name": "Company email (" + ", ".join("@" + d for d in LOGIN_EMAIL_DOMAINS) + ")", "decision": "allow",
                "include": [{"email_domain": {"domain": d}} for d in LOGIN_EMAIL_DOMAINS]}
apps = {a["name"]: a for a in cf("GET", f"/accounts/{AID}/access/apps")}


def upsert_app(name, hosts, policies):
    body = {"name": name, "type": "self_hosted", "domain": hosts[0],
            "destinations": [{"type": "public", "uri": h} for h in hosts],
            "session_duration": "24h", "app_launcher_visible": True,
            "allowed_idps": otp_ids, "auto_redirect_to_identity": bool(otp_ids),
            "policies": policies}
    if name in apps:
        cf("PUT", f"/accounts/{AID}/access/apps/{apps[name]['id']}", body); print("access app updated:", name)
    else:
        cf("POST", f"/accounts/{AID}/access/apps", body); print("access app created:", name)


upsert_app("Laser Office Dashboards",
           [f"{s}.{ZONE_NAME}" for s, _, _ in ROUTES if s != "enquiry"], [staff_policy])
upsert_app("Enquiry to Quotation", [f"enquiry.{ZONE_NAME}"],
           [staff_policy, {"name": "n8n / Claude service token", "decision": "non_identity",
                           "include": [{"service_token": {"token_id": st["id"]}}]}])

# 6. ingress LAST: only after Access apps protect every hostname
ingress = [{"hostname": f"{s}.{ZONE_NAME}", "service": f"http://{SERVER}:{p}", "originRequest": {}} for s, p, _ in ROUTES]
ingress.append({"service": "http_status:404"})
cf("PUT", f"/accounts/{AID}/cfd_tunnel/{TID}/configurations", {"config": {"ingress": ingress}})
print("ingress set:", len(ROUTES), "hostnames")


state = {"account_id": AID, "zone_id": ZID, "tunnel_id": TID, "tunnel_name": TUNNEL_NAME,
         "service_token_client_id": st["client_id"], "service_token_id": st["id"],
         "team_domain": cf("GET", f"/accounts/{AID}/access/organizations").get("auth_domain"),
         "routes": {f"https://{s}.{ZONE_NAME}": f"http://{SERVER}:{p}  ({l})" for s, p, l in ROUTES}}
out = os.path.join(HOME, r"Desktop\ALL PROJECT\infrastructure\docs\m15-cloudflare-state-" + ZONE_NAME + ".json")
json.dump(state, open(out, "w"), indent=2)
print("state (no secrets) ->", out)
