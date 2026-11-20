# M15 – Secure remote access to office server dashboards

Status: **LIVE** since 20-Nov-2026 · Owner: Minmoy · Cloudflare account: Puja (Free plan + Zero Trust Free)

## How it works
Office server 192.168.1.190 runs **cloudflared** (Windows service `cloudflared`, auto-start, restarts on failure).
It makes an *outbound* connection to Cloudflare – **no port is opened on the office router**.
Every link is HTTPS-only and protected by **Cloudflare Access** (login) before any request reaches the server.

## Access URLs
| Dashboard | Outside link | Office link |
|---|---|---|
| Master Portal | https://portal.gmdalui.co.in | http://192.168.1.190:7777 |
| Enquiry to Quotation | https://enquiry.gmdalui.co.in | http://192.168.1.190:4173 |
| GMD Quotation | https://gmd-quotation.gmdalui.co.in | http://192.168.1.190:4570 |
| Tender Executive | https://tender-exec.gmdalui.co.in | http://192.168.1.190:3126 |
| BOM | https://bom.gmdalui.co.in | http://192.168.1.190:4555 |
| Inspection | https://inspection.gmdalui.co.in | http://192.168.1.190:5123 |
| Email Dashboard | https://email-dash.gmdalui.co.in | http://192.168.1.190:6002 |
| Invoice | https://invoice.gmdalui.co.in | http://192.168.1.190:6004 |
| Transporter & Delivery | https://transport.gmdalui.co.in | http://192.168.1.190:6010 |
| CEEBUILD Item | https://ceebuild.gmdalui.co.in | http://192.168.1.190:6011 |
| Sheet Automation | https://sheets.gmdalui.co.in | http://192.168.1.190:6321 |

## How login works (staff)
1. Open any link above in a browser (phone or laptop, any network).
2. Cloudflare "Sign in" page → enter your **@laserpowerinfra.com** email → **Send me a code**.
3. Enter the 6-digit code from your mailbox → the dashboard opens. Session lasts 24 h.
4. Emails from any other domain never receive a code. The dashboard's own login (if any) still applies after this.

## Machine access (n8n / Claude) – Enquiry to Quotation only
Send two headers with every request to `https://enquiry.gmdalui.co.in/...`:
```
CF-Access-Client-Id: <from C:\Users\Niloy Paul\cf-enquiry-service-token-gmdalui.co.in.txt>
CF-Access-Client-Secret: <same file>
```
Store them as an n8n "Header Auth" credential – never in workflow JSON. Token valid 1 year (renew before 20-Nov-2027).
The token is refused (403) on every other dashboard.

## Tests (20-Nov-2026)
| Test | Result |
|---|---|
| All 11 links without login → Cloudflare login page (302) | ✅ |
| http:// → https:// redirect | ✅ |
| Login method = email one-time code, only @laserpowerinfra.com | ✅ |
| Enquiry with service token → 200 | ✅ |
| Enquiry without token → login (302); wrong secret → 401 | ✅ |
| Service token on BOM / Invoice / Portal → 403 | ✅ |
| GMD website + Google mail still working after DNS move | ✅ |
| Login from mobile data with a real company email | ⬜ to be done by Minmoy |

## Revoke access
- One person: Zero Trust → My Team → Users → revoke session (and they can't log in without a company mailbox).
- n8n/Claude: Zero Trust → Access → Service Auth → delete `n8n-claude-enquiry-api`.
- Everything immediately: on the server, `Stop-Service cloudflared` (or delete tunnel `laser-office-server` in Zero Trust → Networks → Tunnels).

## Logs
- Who logged in / was blocked: Zero Trust → Logs → Access.
- Tunnel health: Zero Trust → Networks → Tunnels → laser-office-server. Server side: Windows Event Viewer → Application (source cloudflared).

## Rollback plan
1. **Turn off outside access** (office use unaffected): server → `Stop-Service cloudflared; Set-Service cloudflared -StartupType Disabled`.
2. **Remove the software** (optional): `& "C:\Program Files (x86)\cloudflared\cloudflared.exe" service uninstall`, then uninstall cloudflared from Apps.
3. **Return DNS of gmdalui.co.in to the old provider** (only if needed): ResellerClub → gmdalui.co.in → Name Servers → set back to
   `transinfo.earth.orderbox-dns.com`, `transinfo.mars.orderbox-dns.com`, `transinfo.mercury.orderbox-dns.com`, `transinfo.venus.orderbox-dns.com`.
   The old orderbox DNS records were left untouched, so website and email work as before.

## Important for the future
DNS for **gmdalui.co.in is now managed in Cloudflare** (Puja's account). Any new DNS record (email, website, verification) must be added there, not in ResellerClub/orderbox.

## Files
- Setup script (idempotent): `infrastructure/cloudflare/m15_setup.py`
- IDs (no secrets): `infrastructure/docs/m15-cloudflare-state-gmdalui.co.in.json`
- Secrets (not in project): `C:\Users\Niloy Paul\cf-token-puja.txt`, `cf-tunnel-token-gmdalui.co.in.txt`, `cf-enquiry-service-token-gmdalui.co.in.txt`
