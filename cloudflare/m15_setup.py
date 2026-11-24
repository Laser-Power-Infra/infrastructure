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
    ("notifier", 6025, "Notification Service API"),
    ("whatsapp", 6026, "WhatsApp (Evolution API + manager)"),
]
# Hostnames with their own Access app (staff + n8n service token), not in "Laser Office Dashboards".
WHATSAPP_HOSTS = ("notifier", "whatsapp")
# Staff log in with Google (no email code) on every app when HOME\cf-google-oauth.txt exists
# (line 1 client id, line 2 client secret; Google redirect URI
# https://<team>.cloudflareaccess.com/cdn-cgi/access/callback). Without it everything stays on the email OTP.
# One Cloudflare login covers all apps (team-domain session); n8n service tokens are unaffected.
SESSION = "168h"  # how long a login lasts before Cloudflare asks again (silent with Google if still signed in)
GOOGLE_OAUTH_FILE = os.path.join(HOME, "cf-google-oauth.txt")


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

# 4b. separate service token for n8n -> WhatsApp notifier (Evolution sendText, notifier API)
wa_st_name = "n8n-whatsapp-notifier"
wa_sts = [t for t in cf("GET", f"/accounts/{AID}/access/service_tokens") if t["name"] == wa_st_name]
wa_st_path = os.path.join(HOME, f"cf-whatsapp-service-token-{ZONE_NAME}.txt")
if wa_sts:
    wa_st = wa_sts[0]; print("service token exists", wa_st["client_id"])
else:
    wa_st = cf("POST", f"/accounts/{AID}/access/service_tokens", {"name": wa_st_name, "duration": "8760h"})
    open(wa_st_path, "w").write(f"CF-Access-Client-Id: {wa_st['client_id']}\nCF-Access-Client-Secret: {wa_st['client_secret']}\n")
    print("service token created; headers saved to", wa_st_path)

# 4c. service token for n8n -> Ceebuild dashboard API (/api/n8n/*: PO mails read by n8n)
cb_st_name = "n8n-ceebuild-api"
cb_sts = [t for t in cf("GET", f"/accounts/{AID}/access/service_tokens") if t["name"] == cb_st_name]
cb_st_path = os.path.join(HOME, f"cf-ceebuild-service-token-{ZONE_NAME}.txt")
if cb_sts:
    cb_st = cb_sts[0]; print("service token exists", cb_st["client_id"])
else:
    cb_st = cf("POST", f"/accounts/{AID}/access/service_tokens", {"name": cb_st_name, "duration": "8760h"})
    open(cb_st_path, "w").write(f"CF-Access-Client-Id: {cb_st['client_id']}\nCF-Access-Client-Secret: {cb_st['client_secret']}\n")
    print("service token created; headers saved to", cb_st_path)

# 5. Access apps (email OTP, @laserpowerinfra.com)
idps = cf("GET", f"/accounts/{AID}/access/identity_providers")
otp = [i for i in idps if i["type"] == "onetimepin"]
if not otp:  # staff log in with an email one-time code (not "Cloudflare account" login)
    otp = [cf("POST", f"/accounts/{AID}/access/identity_providers", {"name": "Email one-time code", "type": "onetimepin", "config": {}})]
    print("created login method: email one-time PIN")
otp_ids = [otp[0]["id"]]

# Google login (type "google"; the staff policy below still limits it to @laserpowerinfra.com).
google_ids = []
if os.path.exists(GOOGLE_OAUTH_FILE):
    gid, gsecret = [l.strip() for l in open(GOOGLE_OAUTH_FILE, encoding="utf-8-sig").read().strip().splitlines()[:2]]
    g_body = {"name": "Google", "type": "google", "config": {"client_id": gid, "client_secret": gsecret}}
    g = [i for i in idps if i["type"] == "google"]
    if g:
        cf("PUT", f"/accounts/{AID}/access/identity_providers/{g[0]['id']}", g_body); print("login method updated: Google")
        google_ids = [g[0]["id"]]
    else:
        google_ids = [cf("POST", f"/accounts/{AID}/access/identity_providers", g_body)["id"]]
        print("created login method: Google")
else:
    print("no", GOOGLE_OAUTH_FILE, "- Google login skipped, those hosts stay on the email code")
staff_policy = {"name": "Company email (" + ", ".join("@" + d for d in LOGIN_EMAIL_DOMAINS) + ")", "decision": "allow",
                "include": [{"email_domain": {"domain": d}} for d in LOGIN_EMAIL_DOMAINS]}
apps = {a["name"]: a for a in cf("GET", f"/accounts/{AID}/access/apps")}


def upsert_app(name, hosts, policies):
    idp_ids = google_ids or otp_ids  # one login method -> auto-redirect straight to it, no chooser screen
    body = {"name": name, "type": "self_hosted", "domain": hosts[0],
            "destinations": [{"type": "public", "uri": h} for h in hosts],
            "session_duration": SESSION, "app_launcher_visible": True,
            "allowed_idps": idp_ids, "auto_redirect_to_identity": len(idp_ids) == 1,
            "policies": policies}
    if name in apps:
        cf("PUT", f"/accounts/{AID}/access/apps/{apps[name]['id']}", body); print("access app updated:", name)
    else:
        cf("POST", f"/accounts/{AID}/access/apps", body); print("access app created:", name)


upsert_app("Laser Office Dashboards",
           [f"{s}.{ZONE_NAME}" for s, _, _ in ROUTES if s != "enquiry" and s not in WHATSAPP_HOSTS], [staff_policy])
upsert_app("Enquiry to Quotation", [f"enquiry.{ZONE_NAME}"],
           [staff_policy, {"name": "n8n / Claude service token", "decision": "non_identity",
                           "include": [{"service_token": {"token_id": st["id"]}}]}])

upsert_app("WhatsApp Notifier", [f"{s}.{ZONE_NAME}" for s in WHATSAPP_HOSTS],
           [staff_policy, {"name": "n8n WhatsApp service token", "decision": "non_identity",
                           "include": [{"service_token": {"token_id": wa_st["id"]}}]}])

# Path app (more specific than the hostname app): only the n8n service token reaches /api/n8n.
# The dashboard checks its own x-api-key on these routes as well.
upsert_app("Ceebuild n8n API", [f"ceebuild.{ZONE_NAME}/api/n8n"],
           [{"name": "n8n Ceebuild service token", "decision": "non_identity",
             "include": [{"service_token": {"token_id": cb_st["id"]}}]}])

# 6. ingress LAST: only after Access apps protect every hostname
ingress = [{"hostname": f"{s}.{ZONE_NAME}", "service": f"http://{SERVER}:{p}", "originRequest": {}} for s, p, _ in ROUTES]
ingress.append({"service": "http_status:404"})
cf("PUT", f"/accounts/{AID}/cfd_tunnel/{TID}/configurations", {"config": {"ingress": ingress}})
print("ingress set:", len(ROUTES), "hostnames")


state = {"account_id": AID, "zone_id": ZID, "tunnel_id": TID, "tunnel_name": TUNNEL_NAME,
         "service_token_client_id": st["client_id"], "service_token_id": st["id"],
         "whatsapp_service_token_client_id": wa_st["client_id"], "whatsapp_service_token_id": wa_st["id"],
         "ceebuild_service_token_client_id": cb_st["client_id"], "ceebuild_service_token_id": cb_st["id"],
         "team_domain": cf("GET", f"/accounts/{AID}/access/organizations").get("auth_domain"),
         "routes": {f"https://{s}.{ZONE_NAME}": f"http://{SERVER}:{p}  ({l})" for s, p, l in ROUTES}}
out = os.path.join(HOME, r"Desktop\ALL PROJECT\infrastructure\docs\m15-cloudflare-state-" + ZONE_NAME + ".json")
json.dump(state, open(out, "w"), indent=2)
print("state (no secrets) ->", out)
