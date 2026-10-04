# Running the tour server

The server needs Node.js 22.9+, internet access and three values from the team: an Anthropic API key, an ElevenLabs API key and an ElevenLabs voice ID. Never paste the keys into the repository, a chat or a screenshot: they go only into `server/.env`.

The `.env` content is the same on every system:

```
PORT=8787
LLM_PROVIDER=claude
ANTHROPIC_API_KEY=<Anthropic key>
CLAUDE_MODEL=claude-haiku-4-5-20251001
LLM_TIMEOUT_MS=60000
TTS_PROVIDER=elevenlabs
ELEVENLABS_API_KEY=<ElevenLabs key>
ELEVENLABS_VOICE_ID=<voice id>
ELEVENLABS_MODEL_ID=eleven_multilingual_v2
```

A working server answers `http://localhost:8787/v1/health` with `{"ok":true,…,"llm":{"ok":true,"model":"claude-haiku-4-5-20251001"},"tts":{"ok":true,"provider":"elevenlabs"}}`.

## Windows laptop

1. Install Node.js LTS from [nodejs.org](https://nodejs.org) (the `.msi`, all defaults). Open a **new** Command Prompt (`cmd`, not PowerShell) and check `node -v` (v22.9 or later).
2. Download the repository as a ZIP (GitHub → Code → Download ZIP) and extract it, e.g. to `C:\`. Then `cd /d C:\hack-yeah-2026-main\server`.
3. Create the file with `notepad .env` (answer **Yes**), paste the content above with your values, save. `dir .env` must show `.env`, not `.env.txt` (fix with `ren .env.txt .env`).
4. `npm start`. Allow Node.js on private networks if the Windows Firewall asks. Keep the window open.
5. The emulator on the same laptop reaches it at `http://10.0.2.2:8787`, the app's default.

`npm run start:claude` does not work in `cmd`; `npm start` with `LLM_PROVIDER=claude` in `.env` does the same.

## Linux server

```sh
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs git
git clone https://github.com/UmarlyPoeta/hack-yeah-2026.git
cd hack-yeah-2026/server
nano .env                 # paste the content above, Ctrl+O, Enter, Ctrl+X
chmod 600 .env
npm test && npm start
```

To keep it running, a systemd unit (`/etc/systemd/system/tour.service`, replace `USER`):

```ini
[Unit]
Description=tour server
After=network-online.target

[Service]
User=USER
WorkingDirectory=/home/USER/hack-yeah-2026/server
ExecStart=/usr/bin/node --env-file=.env src/index.js
Restart=always

[Install]
WantedBy=multi-user.target
```

`sudo systemctl daemon-reload && sudo systemctl enable --now tour`, open port 8787 (`sudo ufw allow 8787/tcp` and the provider's firewall), then type `http://<server-ip>:8787` in the app under **Moje → Serwer**.

## Phone outside the laptop's network

Run a free tunnel next to the server: `cloudflared tunnel --url http://localhost:8787` (Windows: `cloudflared-windows-amd64.exe` from the cloudflared GitHub releases). Type the printed `https://…trycloudflare.com` address in **Moje → Serwer**. The address changes on every start. Anyone with the address can spend the API credits: close the tunnel after the demo.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `"llm":{"ok":false` or `LLM HTTP 401` in the log | wrong `ANTHROPIC_API_KEY`; fix `.env` and restart |
| Stories but no voice | wrong ElevenLabs key or voice ID, or the monthly character limit is used up |
| `EADDRINUSE :8787` | the server already runs in another window |
| App: "Brak połączenia z serwerem" | server not running, or a wrong address in Moje → Serwer (the emulator needs `10.0.2.2`, not `localhost`) |
