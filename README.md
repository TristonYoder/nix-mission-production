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
| `modules/wallpaper.nix` | Wallpaper showing the machine's label (e.g. "CG 3"). |
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
- Asks for the operator's sudo password once per machine.
- Each Mac is reached at `<name>.local`; set `address` in the inventory to override.

## Adding a new Mac

**At the Mac** (the only hands-on part before deploying):

1. Run through Setup Assistant. Create the operator account (`user` in
   `inventory.nix`) as an admin with the shared password. Leave FileVault **off** if
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
   the host key and re-keys secrets (committing that change), installs Nix, then
   deploys. Push the commit afterwards.

**At the Mac again:**

- Reboot once so the login items and wallpaper apply.
- CG/Audio: install the vendor apps below, then approve their system extensions.
  Desktop Video's kernel extension needs **Reduced Security** set in Recovery
  (hold power → Options → Startup Security Utility) before macOS will load it.
- Activate licences: Dante Virtual Soundcard, ProPresenter, Resolume.

### Vendor apps (no Homebrew cask)

Each activation prints a warning while these are missing.

| App | Download |
|---|---|
| Blackmagic Desktop Video | https://www.blackmagicdesign.com/support/family/capture-and-playback |
| Dante Virtual Soundcard | https://my.audinate.com/ (account required) |

## Common changes

- **Add an app:** add an entry to the catalog in `modules/apps.nix`, then list it in
  a role or in a host's `apps`.
- **One-off tweak for one machine:** give the host a `config = { ... };` module in
  `inventory.nix`.
- **WiFi off on a machine** (for example, to keep Dante on wired only):
  `config = { production.wifi.mode = "off"; };`
- **Wallpaper background image:** set `production.wallpaper.background` to a path;
  the label is drawn on top.

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
