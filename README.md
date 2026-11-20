# Production Macs

nix-darwin config for the live-production Macs (all Apple Silicon). One Mac with
the deploy keys builds every machine and pushes it over SSH.

## Layout

| Path | What lives there |
|---|---|
| `inventory.nix` | **Start here.** Every host, its role and apps, the operator user, deploy keys, blackout windows. |
| `roles/` | What a kind of machine needs (`cg`, `audio`, `video`, `lighting`, `service-director`). |
| `modules/production.nix` | Baseline for every Mac: name, operator account, key-only SSH, never sleep, no auto-updates. |
| `modules/apps.nix` | App catalog: the only place that knows how an app is installed. |
| `modules/pager.nix` | 13 Years pager on every Mac (menu bar cue light, countdown, messages): producer address (west-cg4), and per-role settings such as `production.pager.role`. |
| `modules/wallpaper.nix` | Wallpaper with an info card: location, function, hostname, IPs, boot time, support number (from `secrets/support.age`). |
| `modules/menubar.nix` | Machine name in the menu bar (SwiftBar), card details in its dropdown. |
| `modules/cleanup.nix` | Deletes preinstalled apps (GarageBand, iMovie, Numbers, Pages), leftovers from the old CGs (Frame.io Transfer, 13 Years Pager) and vendor extras, hides desktop widgets. The Dock shows only the machine's installed apps (no "?" tiles): production apps, support apps, Chrome, then Downloads and the Trash (layout in `modules/apps.nix`). |
| `modules/rustdesk.nix` | Unattended RustDesk: system service, permanent password, enrollment in the RustDesk console's "Mission Production" group. Server details come from `secrets/rustdesk.age`. |
| `modules/network.nix` | Static IP, subnet, router and DNS on the built-in Ethernet for hosts with `ip` in the inventory. The Dante adapter stays on DHCP. |
| `modules/fonts.nix`, `fonts/` | System-wide fonts: Inter on every Mac; files in `fonts/cg/` go on CG machines. |
| `modules/wifi.nix` | Production WiFi, plus a watchdog (`wifi-watchdog.sh`) that turns WiFi off while a wired port has internet and back on when none does. |
| `modules/vlans.nix` | Renames each port's network service after its VLAN or WiFi network (from `vlans` in `inventory.nix`), e.g. "Dante Primary", "Production Control - WiFi". |
| `modules/syncthing.nix` | Syncthing on every Mac (Nix build, never self-upgrades). Macs with Resolume keep their Resolume folder in sync (not `Preferences` or `Extra Effects`). On those Macs it lives at `~/Resolume Arena`, with a symlink at `~/Documents/Resolume Arena`, so macOS never stops Syncthing to ask about Documents access. Devices outside the fleet join through `secrets/syncthing-peers.age`. Paths that compositions built elsewhere point at (`authorPaths`) are symlinked to the local folder. Identities in `secrets/syncthing`, made by `./deploy bootstrap`. Web UI at `https://<mac>:8384`, user `missionproduction`, password in `secrets/syncthing-gui.age`. |
| `modules/resolume.nix` | "This Week" in the Dock next to Arena on Macs with Resolume: opens the week's show (`Compositions/YYYY.MM.DD.avc`, the earliest dated this week's Monday or later, else the latest), leaving it alone if already open. Also runs at login in place of Arena. |
| `modules/nas.nix` | Mounts the NAS's Creative Team share at `/Volumes/Creative Team` as `missionproduction` (CG machines). Remounts after reboots and network drops. |
| `modules/wifi.nix`, `modules/autologin.nix`, `modules/rustdesk.nix`, `modules/nas.nix` | Use `secrets/`; do nothing until the secret exists. |
| `secrets/` | agenix secrets and host keys. |
| `deploy` | Build, copy, activate. Also bootstraps new Macs. |
| `macos-firstboot/` | First-boot package for a hands-off reinstall: any Mac becomes a generic `missionproduction-<mac>` (see [Zero-touch reinstall](#zero-touch-reinstall-generic-macs)). |
| `modules/generic.nix`, `roles/generic.nix` | The generic profile: baseline only, and it pulls main from GitHub itself every 15 minutes. |
| `.github/workflows/enroll-host.yml` | Turns a generic Mac's enrollment issue into a PR with its host key and re-keyed secrets. |

Current fleet:

| Host | Role | Apps (plus Chrome and Google Drive everywhere) |
|---|---|---|
| west-cg5hs (hot spare, .95) | cg | Desktop Video, Dante Virtual Soundcard, ProPresenter, Resolume Arena |
| west-cg1, west-cg2 (.91, .92) | cg | Desktop Video, Dante Virtual Soundcard, ProPresenter |
| west-cg3 (.93) | cg | Desktop Video, Dante Virtual Soundcard, Resolume Arena |
| west-cg4 (.94) | cg | Desktop Video, Dante Virtual Soundcard, ProPresenter, Spotify, 13 Years Producer |
| audio | audio | Dante Virtual Soundcard, Dante Controller |
| service-director | service-director | ATEM Software Control, Dante Controller |
| video | video | ATEM Software Control |
| lighting | — | TBD |

## Deploying

```bash
./deploy west-cg3          # one machine
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
   the host key, re-keys secrets and makes the Mac's Syncthing identity
   (committing that change), installs the Xcode
   Command Line Tools and Nix, then deploys. Push the commit afterwards.

**At the Mac again:**

- Reboot once so the login items apply. Then ⌘-drag the machine name in the
  menu bar next to the clock (macOS remembers it).
- CG/Audio: approve the Desktop Video and Dante system extensions when prompted.
  Desktop Video's kernel extension needs **Reduced Security** set in Recovery
  (hold power → Options → Startup Security Utility) before macOS will load it.
- Activate licences: Dante Virtual Soundcard, ProPresenter, Resolume.
- RustDesk: System Settings → Privacy & Security → turn RustDesk on under
  **Screen & System Audio Recording** and **Accessibility**. macOS allows no
  other way to grant these; until then remote sessions connect to a black screen.

Expect a few "App Background Activity" notifications on a new Mac, one per
newly installed background item. Later deploys don't repeat them: launch agents
start through `/bin/sh` or `/usr/bin/open`, whose identity never changes.

### Taking over a Mac that's already in use

Same as above, without wiping it. Do it outside the blackout window, at the Mac.

1. **Create the operator account next to the old one** (over SSH as the old
   admin; it prompts for passwords):

   ```bash
   sudo sysadminctl -addUser missionproduction -fullName "Mission Production" -admin -password -
   sudo createhomedir -c -u missionproduction
   ```

   Its password doesn't matter: every deploy sets it from
   `secrets/autologin-password.age` (and writes auto-login from the same
   secret). Copy your SSH key into `/Users/missionproduction/.ssh/authorized_keys`
   or let bootstrap ask for the password. The old account stays as a fallback;
   copy what's needed out of it (e.g. `~/Documents/ProPresenter`) after the
   deploy, and delete it once a service has run cleanly.
2. Quit the show apps. Remote Login is usually on already.
3. `./deploy bootstrap <name> <ip>` as for a new Mac. Hand-installed copies of
   apps that Homebrew now manages (Chrome, ProPresenter, Spotify, ...) go to the
   operator's Trash first, so Homebrew can install its own. Their settings stay.
4. Restart (it logs in as the operator), then do the "At the Mac again" steps. Desktop Video and Dante
   Virtual Soundcard move to the pinned versions, so expect the system
   extension prompt again.
5. **Re-patch Dante.** If the Mac's name changed, its Dante Virtual Soundcard
   device name probably did too, which breaks its routes in Dante Controller.
   ProPresenter's network name changes with it (remotes, stage displays).

Apps installed outside the catalog (TeamViewer, Chrome Remote Desktop, ...) are
left alone. Remove them with their vendor uninstaller.

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

## Zero-touch reinstall (generic Macs)

Wipe and reinstall any Apple Silicon Mac so it sets itself up with no
commands at the machine. It becomes **`missionproduction-<mac>`** (the last 6
hex digits of en0's hardware address), running the shared
`darwinConfigurations.missionproduction` profile (`inventory.generic`): baseline
only (Chrome, Google Drive, RustDesk, SSH with the deploy keys, Syncthing,
wallpaper, pager). It keeps itself on main and is not part of `./deploy`.

### One-time setup

1. **Developer ID Installer certificate** (account holder only): Xcode →
   Settings → Accounts → Manage Certificates → + → Developer ID Installer.
   The "Developer ID Application" certificate can't sign packages.
2. **Notary profile** in your keychain (app-specific password from
   appleid.apple.com):

   ```bash
   xcrun notarytool store-credentials notary --apple-id <apple-id> --team-id JFFQ4Z6YQ5
   ```

3. **Enrollment** (CI re-key key, GitHub environment and settings):

   ```bash
   macos-firstboot/setup-enrollment.sh
   ```

   Then push, and make the issue-only token it describes. The token stays out
   of the repo: keep it in a file next to the install USB.

### Build the package

```bash
macos-firstboot/build.sh --token-file /path/to/enroll-token
```

This signs as `Developer ID Installer: 7 and Co LLC (JFFQ4Z6YQ5)` (override
with `SIGN_IDENTITY`), notarizes with the `notary` profile (`NOTARY_PROFILE`),
staples, checks the signature and prints the payload. The output lands in
`macos-firstboot/build/` (git-ignored). **With a token inside, the package is
sensitive**: keep it on the USB only, and revoke the token if the USB goes
missing. The token can only open issues, and nothing gets access until you
merge a PR. Without `--token-file`, enrollment is manual (below).
`--unsigned` builds a package for checking the layout only.

The package holds only a LaunchDaemon
(`/Library/LaunchDaemons/org.missionproduction.firstboot.plist`), the script
and its settings (`/usr/local/libexec/org.missionproduction.firstboot/`). The
same package can later go out through MDM unchanged: its postinstall starts the
daemon right away when installed on a running system.

### Reinstall a Mac

On the Mac, from its current macOS, with the installer app in /Applications
(or on the USB):

```bash
sudo "/Applications/Install macOS <name>.app/Contents/Resources/startosinstall" \
  --eraseinstall --agreetolicense --newvolumename "Macintosh HD" \
  --installpackage /Volumes/<usb>/missionproduction-firstboot-<version>.pkg \
  --user <admin on this Mac> --passprompt
```

Booting the USB into the installer does **not** run the package; this command
is the only route.

### What happens

1. Setup Assistant runs as usual. Create **Mission Production /
   `missionproduction`** as an admin (as for any production Mac). Leave
   FileVault off if it should log in automatically.
2. At that first login, `firstboot.sh` (root, from launchd) waits for the
   network, then installs the Command Line Tools and Nix, names the Mac, builds
   the profile from the commit main points at and activates it (Homebrew and
   the apps come with it). Nothing is shown on screen until it finishes. A
   notification says when it's done.
3. It opens an issue with the Mac's SSH host key. The **Enroll host** Action
   turns that into a PR that adds `secrets/host-keys/<host>.pub` and re-keys
   every secret. Compare the fingerprint in the PR with the Mac (at the Mac or
   over SSH: `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`) and merge.
4. Within 15 minutes the Mac switches to the new main
   (`/var/log/follow-main.log`). It can now decrypt its secrets, so RustDesk
   enrolls in the console's "Mission Production" group, WiFi joins, and the
   operator password and auto-login are set from the secrets.
5. **At the Mac, once** (macOS allows no other way without MDM): System
   Settings → Privacy & Security → turn RustDesk on under **Screen & System
   Audio Recording** and **Accessibility**. Until then remote sessions show a
   black screen.

Without a token, step 3 is manual: copy the host key from
`/var/log/firstboot.log` into `secrets/host-keys/<host>.pub`, re-key
(`cd secrets && nix develop .. -c agenix -r -i ~/.ssh/agenix`), commit and
push.

### Logs and reruns

- First boot: `/var/log/firstboot.log`. Finished steps are marked in
  `/var/db/org.missionproduction.firstboot/`. A failed step is retried at the
  next boot and every 15 minutes. To retry now:
  `sudo launchctl kickstart -k system/org.missionproduction.firstboot`. To
  redo a step, delete its `<step>.done` file. Once everything succeeds, the
  daemon and its files remove themselves.
- Following main: `/var/log/follow-main.log`; skipped during blackout windows.
  A commit that fails 3 times is skipped until main moves again. To run it now:
  `sudo launchctl kickstart system/org.missionproduction.follow-main`.
- Enrollment conflicts (two Macs enrolled at once): after merging one, re-run
  **Actions → Enroll host → Run workflow** with the other's issue number.

### Promoting a generic Mac

To give it a role and a real name: add it to `hosts` in `inventory.nix`,
delete `secrets/host-keys/missionproduction-<mac>.pub`, commit, then
`./deploy bootstrap <name> missionproduction-<mac>.local`. Bootstrap registers
the same host key under the new name and re-keys. The follow-main daemon goes
away with the generic profile.

## Common changes

- **Add an app:** add an entry to the catalog in `modules/apps.nix`, then list it in
  a role or in a host's `apps`.
- **Remove something everywhere:** add its path to `production.remove` in
  `modules/cleanup.nix` (or to an app's `remove` in the catalog).
- **One-off tweak for one machine:** give the host a `config = { ... };` module in
  `inventory.nix`.
- **WiFi:** by default (`production.wifi.mode = "auto"`; CG machines default to
  `"off"` in `roles/cg.nix`) a watchdog runs on every
  network change and every 30s: if any wired port can ping the internet
  (1.1.1.1 / 8.8.8.8, through that port), WiFi goes off; otherwise it comes on.
  A port that only carries Dante doesn't count as internet. Changes are logged
  to `/var/log/wifi-watchdog.log`. If the venue blocks ping, set
  `production.wifi.probeHosts` to hosts that answer.
- **NIC labels:** each port (WiFi included) is named after the network its
  address falls in (`vlans` in `inventory.nix`); that name shows in System Settings → Network, on
  the wallpaper card and in the menu bar. An unplugged port keeps its last label;
  a port on an unknown subnet goes back to its hardware name. Renames are logged
  to `/var/log/vlan-labels.log`. Add or change a VLAN in `inventory.nix`.
- **WiFi always on** (no watchdog): `config = { production.wifi.mode = "join"; };`
- **WiFi off on a machine** (for example, to keep Dante on wired only):
  `config = { production.wifi.mode = "off"; };`
- **Wallpaper:** commit the background as `assets/wallpaper.jpg` (used by every
  Mac). Card text comes from `wallpaper` and each host's `location`/`function` in
  `inventory.nix`; the support number comes from `secrets/support.age`. The card
  is drawn on the main screen only, at login, and redrawn within a minute when an
  IP changes.

## Secrets

This repo is public. Secrets only ever go in as agenix-encrypted `secrets/*.age`.
Every secret is readable by the admin key and every registered host, generic
Macs included, plus the CI key in `secrets/ci-key.pub` (it re-keys for
enrollment PRs; its private half is the `rekey` environment's `AGENIX_CI_KEY`
on GitHub. Delete the file and re-key to revoke it).

| Secret | Contents |
|---|---|
| `wifi.age` | `SSID=...` and `PSK=...` lines |
| `autologin-password.age` | the operator password (enables auto-login) |
| `support.age` | the support phone number shown on the wallpaper and menu bar |
| `nas-password.age` | the `missionproduction` account's password on the NAS (Mission-NAS) |
| `rustdesk.age` | `SERVER=`, `KEY=`, optional `API=`, `PASSWORD=` (unattended access) and `TOKEN=` (console API token) lines |

```bash
cd secrets
nix develop .. -c agenix -e wifi.age -i ~/.ssh/agenix
nix develop .. -c agenix -e support.age -i ~/.ssh/agenix
```

To set a password without it landing in an editor buffer or shell history
(zsh), pipe it in:

```bash
cd secrets && read -rs "pw?NAS password: " && printf %s "$pw" | nix develop .. -c agenix -e nas-password.age -i ~/.ssh/agenix; unset pw
```

The support number is encrypted so the real line isn't published for spam
callers to scrape; edit `support.age` with the same command when it changes.

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
