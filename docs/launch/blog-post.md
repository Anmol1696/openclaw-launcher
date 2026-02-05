# Introducing OpenClaw Launcher: OpenClaw in One Click

**TL;DR:** Double-click an app, get OpenClaw running in an isolated Docker container, chat in your browser. No terminal. No npm. No config files.

![OpenClaw Launcher Dashboard](images/dashboard-running.png)
*OpenClaw running in lockdown mode—one click to get here*

---

## The Problem

OpenClaw is powerful. The setup? Not so much.

If you've tried to get OpenClaw running, you know the drill:
- Clone the repo
- Install Node.js (right version?)
- `npm install` (hope nothing breaks)
- Configure environment variables
- Set up API keys
- Figure out the CLI flags
- Cross your fingers

For developers, this is Tuesday. For everyone else, it's a wall.

And here's the thing: **OpenClaw is evolving fast**. New features land weekly. But if you can't get past the setup, you're left out. I felt this myself—and I suspect many others do too.

## The Security Question

There's another concern that doesn't get talked about enough: **what exactly is this AI agent doing on my machine?**

OpenClaw is an autonomous agent. It can run commands, modify files, make API calls. That's the whole point—but it's also why you might hesitate before giving it free rein on your laptop.

I wanted to try OpenClaw, but I wanted guardrails. A sandbox. Something isolated from my actual system.

Docker was the obvious answer.

## The Solution: OpenClaw Launcher

OpenClaw Launcher is a native macOS app that:

1. **Installs Docker Desktop** if you don't have it
2. **Pulls the OpenClaw image** automatically
3. **Runs it in lockdown mode**—read-only filesystem, no root, memory limits, localhost-only
4. **Opens the Control UI** in your browser

That's it. Double-click → Docker runs → browser opens → done.

No terminal. No Node.js. No PATH issues. No CLI.

![Setup Progress](images/setup-progress.png)
*The app handles Docker, image pulling, and gateway startup automatically*

### What "Lockdown Mode" Means

The container runs with maximum restrictions:

| Security Feature | What It Does |
|-----------------|--------------|
| `--read-only` | Container can't modify its own filesystem |
| `--cap-drop ALL` | Zero Linux capabilities |
| `--no-new-privileges` | Can't escalate permissions |
| `--memory 2g` | Can't consume all your RAM |
| `--pids-limit 256` | Can't fork bomb |
| `127.0.0.1` binding | Not accessible from your network |

The agent runs in a box. It can still do its job—but it can't escape.

## The Workflow

Once the launcher starts OpenClaw, here's what happens:

1. Browser opens to the Control UI
2. Paste the gateway token (auto-generated, shown in the app)
3. Sign in with your AI provider (Anthropic, OpenAI, etc.)
4. Start chatting

Want to connect Telegram? Ask OpenClaw to set it up. Want to configure webhooks? Ask OpenClaw. The whole point is that **you use OpenClaw to configure OpenClaw**.

The WebUI is your interface. The agent does the work.

## Beta Launch

Full transparency: this is a beta release.

The app works, but it's not yet notarized with Apple. That means macOS will show a security warning on first launch. You'll need to run one command to bypass it:

```bash
xattr -cr /Applications/OpenClawLauncher.app
```

This is temporary. Apple Developer enrollment is pending, and v1 will be properly signed and notarized—no terminal commands needed.

## Try It

**Homebrew:**
```bash
brew tap anmol1696/openclaw-launcher
brew install --cask openclaw-launcher
xattr -cr /Applications/OpenClawLauncher.app  # beta only
```

**Direct download:**
[OpenClawLauncher.dmg](https://github.com/Anmol1696/openclaw-launcher/releases/latest/download/OpenClawLauncher.dmg)

---

OpenClaw is too useful to be gated behind setup friction. The Launcher removes that gate.

Give it a shot.
