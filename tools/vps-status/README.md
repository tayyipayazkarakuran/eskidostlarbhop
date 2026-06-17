# ESKIDOSTLAR BHOP VPS Status Helper

Cloudflare Pages Functions cannot query the CS 1.6 server over UDP directly, so this tiny Node service runs on the VPS and exposes the A2S result as HTTP JSON.

## Run

```powershell
cd C:\Users\TayyipPC\Desktop\botmod\bmod
$env:GAME_HOST="45.143.11.212"
$env:GAME_PORT="27015"
$env:HTTP_PORT="3001"
node tools/vps-status/server.mjs
```

Set the web project's `SERVER_STATUS_URL` to:

```text
http://45.143.11.212:3001/status
```

The endpoint returns:

```json
{
  "ok": true,
  "online": true,
  "server": { "name": "[ESKIDOSTLAR] BHOP SERVER", "map": "bhop_m_expert" },
  "players": []
}
```
