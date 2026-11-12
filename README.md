# Production Macs

nix-darwin config for the live-production Macs (all Apple Silicon). One Mac with
the deploy keys builds every machine and pushes it over SSH.

## Layout

| Path | What lives there |
|---|---|
| `inventory.nix` | **Start here.** Every host, its role and apps, the operator user, deploy keys, blackout windows. |
| `roles/` | What a kind of machine needs (`cg`, `audio`, `lighting`, `director`). |
| `modules/production.nix` | Baseline for every Mac: name, operator account, key-only SSH, never sleep, no auto-updates. |
| `modules/apps.nix` | App catalog: the only place that knows how an app is installed. |
| `modules/wallpaper.nix` | Wallpaper with an info card: location, function, hostname, IPs, boot time, support number. |
| `modules/menubar.nix` | Machine name in the menu bar (SwiftBar), card details in its dropdown. |
| `modules/cleanup.nix` | Deletes preinstalled apps (GarageBand, iMovie, iWork) and vendor extras, hides desktop widgets. The Dock shows only the machine's apps. |
| `modules/wifi.nix`, `modules/autologin.nix` | Use `secrets/`; do nothing until the secret exists. |
| `secrets/` | agenix secrets and host keys. |
| `deploy` | Build, copy, activate. Also bootstraps new Macs. |

Current fleet:

| Host | Role | Apps (plus Chrome everywhere) |
|---|---|---|
| cg-1, cg-2 | cg | Desktop Video, Dante Virtual Soundcard, ProPresenter |
| cg-3 | cg | Desktop Video, Dante Virtual Soundcard, Resolume Arena |
| cg-4 | cg | Desktop Video, Dante Virtual Soundcard, ProPresenter, Spotify |
| audio | audio | Dante Virtual Soundcard, Dante Controller |
| lighting, director | — | TBD |

## Deploying

```bash
./deploy cg-3              # one machine
./deploy --role cg         # every CG machine
./deploy --all
./deploy --build --all     # build only; nothing remote is touched
```

- Builds only committed code (refuses a dirty tree), so each machine maps to a commit.
- Refuses to run inside a blackout window from `inventory.nix` unless given `--force`.
- No sudo password: `deploy` forwards your SSH agent and sudo on the Mac accepts
  a key from `deployKeys` (pam_rssh). Without the agent, sudo falls back to the
  password, so console use is unchanged.
- Each Mac is reached at `<name>.local`; set `address` in the inventory to override.

## Adding a new Mac

**At the Mac** (the only hands-on part before deploying):

1. Run through Setup Assistant. Create the operator account as an admin with the
   shared password: full name **Mission Production**, account name
   **missionproduction** (`user` in `inventory.nix`). Leave FileVault **off** if
   the Mac should log in automatically.
2. Turn on **System Settings → General → Sharing → Remote Login**.
3. Note its IP address.

**From the deploy Mac:**

1. Add it to `hosts` in `inventory.nix` and commit.
2. Run:

   ```bash
   ./deploy bootstrap <name> <ip>
   ```

   This installs the deploy keys (asks for the operator password once), registers
   the host key and re-keys secrets (committing that change), installs the Xcode
   Command Line Tools and Nix, then deploys. Push the commit afterwards.

**At the Mac again:**

- Reboot once so the login items apply. Then ⌘-drag the machine name in the
  menu bar next to the clock (macOS remembers it).
- CG/Audio: approve the Desktop Video and Dante system extensions when prompted.
  Desktop Video's kernel extension needs **Reduced Security** set in Recovery
  (hold power → Options → Startup Security Utility) before macOS will load it.
- Activate licences: Dante Virtual Soundcard, ProPresenter, Resolume.

### Vendor installers (Desktop Video, Dante Virtual Soundcard)

These have no Homebrew cask, since the downloads sit behind a vendor form or
login. Instead, the repo pins the exact `.pkg` by file name and hash in
`modules/apps.nix`, and every machine gets that version.

- The `.pkg` files live in `~/ProductionInstallers` on the deploy Mac (override
  with `PRODUCTION_INSTALLERS`). They are never committed; `./deploy` imports them
  into the Nix store and ships them inside each machine's system.
- On activation, a machine runs `installer` only when the pinned `.pkg` differs
  from the one it last installed (tracked in `/var/db/production-installers`).
- If a pinned file is missing, the build stops and says where to download it.

To pin or upgrade:

1. Download the installer (Desktop Video comes as a `.dmg`; copy the `.pkg` out of
   it) into `~/ProductionInstallers`.
2. In `modules/apps.nix`, set `file` to the exact file name and `hash` to the
   output of:

   ```bash
   nix hash file ~/ProductionInstallers/<file>.pkg
   ```

3. Commit and deploy. Restart the affected machines afterwards.

While `file = null`, an app is unpinned: activation only warns if it's missing.

## Common changes

- **Add an app:** add an entry to the catalog in `modules/apps.nix`, then list it in
  a role or in a host's `apps`.
- **Remove something everywhere:** add its path to `production.remove` in
  `modules/cleanup.nix` (or to an app's `remove` in the catalog).
- **One-off tweak for one machine:** give the host a `config = { ... };` module in
  `inventory.nix`.
- **WiFi off on a machine** (for example, to keep Dante on wired only):
  `config = { production.wifi.mode = "off"; };`
- **Wallpaper:** commit the background as `assets/wallpaper.jpg` (used by every
  Mac). Card text comes from `wallpaper` and each host's `location`/`function` in
  `inventory.nix`. The card is drawn on the main screen only, at login, and
  redrawn within a minute when an IP changes.

## Secrets

This repo is public. Secrets only ever go in as agenix-encrypted `secrets/*.age`.
Every secret is readable by the admin key and every registered host.

| Secret | Contents |
|---|---|
| `wifi.age` | `SSID=...` and `PSK=...` lines |
| `autologin-password.age` | the operator password (enables auto-login) |

```bash
cd secrets
nix develop .. -c agenix -e wifi.age -i ~/.ssh/agenix
```

The admin private key is expected at `~/.ssh/agenix`; override it with
`AGENIX_IDENTITY`.

## Updating

```bash
nix flake update
./deploy --build --all
```

Commit the lock file, then deploy outside service times. Homebrew apps are not
auto-upgraded on deploy (`homebrew.onActivation.upgrade = false`), but apps that
update themselves (ProPresenter, Chrome, Resolume) still will unless you turn that
off inside each app.
