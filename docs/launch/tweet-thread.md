# Tweet Thread: OpenClaw Launcher Launch

## Images

| Tweet | Attachment |
|-------|------------|
| Tweet 1 | Video demo OR `dashboard-running.png` |
| Tweet 3 | `setup-progress.png` |

---

**Tweet 1 — Hook + Demo**

OpenClaw is powerful. The setup? Not so much.

Today I'm releasing OpenClaw Launcher:

Double-click → Docker runs in lockdown → browser opens → done.

No terminal. No npm. No config.

60 seconds from download to chatting with your AI agent.

[attach video or dashboard screenshot]

---

**Tweet 2 — Why**

I wanted to try OpenClaw but:

→ Setup was a wall (clone, npm, env vars, CLI flags)
→ Giving an AI agent free rein on my machine felt risky

So I built a launcher that:
• Runs it in isolated Docker
• Read-only filesystem, no root, memory capped
• Localhost only

The agent works. But it can't escape its box.

---

**Tweet 3 — How it works**

The launcher handles everything:

1. Installs Docker Desktop (if needed)
2. Pulls the OpenClaw image
3. Runs container in lockdown mode
4. Opens browser to Control UI

Then you use OpenClaw to set up OpenClaw.

Want Telegram? Ask it. Webhooks? Ask it.

[attach setup-progress screenshot]

---

**Tweet 4 — CTA**

Try it:

```
brew tap anmol1696/openclaw-launcher
brew install --cask openclaw-launcher
```

Or download: github.com/Anmol1696/openclaw-launcher

⚠️ Beta: run `xattr -cr /Applications/OpenClawLauncher.app` once (proper signing coming in days)

OpenClaw is too useful to be gated behind setup friction.

---

## Alt: Single Tweet Version

If you want just one tweet:

---

OpenClaw Launcher — run OpenClaw in one click.

• Isolated Docker container
• Read-only, no root, memory capped
• No terminal, no npm, no config

Double-click → browser opens → start chatting.

```
brew tap anmol1696/openclaw-launcher
brew install --cask openclaw-launcher
```

github.com/Anmol1696/openclaw-launcher

[attach dashboard screenshot or video]

---

## Hashtags (optional, pick 1-2)

#OpenClaw #AI #MacOS #Docker #AIAgents
