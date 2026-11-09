# impact-lab-ansible

Ansible playbook for provisioning workstations, compute servers, and mobile
stations running **Ubuntu** (developed against Kubuntu; see
[Supported targets](#supported-targets)). It performs base system hardening,
installs a large scientific/software-development toolchain, configures desktop
environments, and integrates the CVMFS + Lmod module system.

## Supported targets

- **OS:** Ubuntu. The base roles use Launchpad PPAs, `deb822_repository`,
  `ubuntu-drivers`, and KDE/Kubuntu packages, so they are Ubuntu-specific.
- The CVMFS/Lmod integration (the `externals/cvmfs-ansible` submodule) supports
  Ubuntu 22.04 / 24.04 / 26.04, Debian 11 / 12 / 13 and (opt-in) Arch Linux, and
  fails fast on anything else. The parent playbook's own roles are Ubuntu-only.
- **Connection:** SSH as the `localadmin` user (set in `group_vars/all/all.yml`)
  with passwordless sudo. The playbook installs the controller's
  `~/.ssh/id_ed25519.pub` as an authorized key for that user.

## Prerequisites

On the machine you run Ansible from (the controller):

- **Ansible:** `ansible-core >= 2.15` (the playbook uses
  `ansible.builtin.deb822_repository`, added in 2.15). Developed on
  ansible-core 2.21.
- An Ed25519 SSH keypair at `~/.ssh/id_ed25519` (`.pub` is deployed to targets).
- Network/SSH access to the target hosts as `localadmin`.

## Setup

```bash
# clone with the CVMFS submodule
git clone --recurse-submodules https://github.com/Gabriel-Devenyi-Consulting/impact-lab-ansible.git
cd impact-lab-ansible

# if you cloned without --recurse-submodules:
git submodule update --init --recursive

# install the required Ansible collections
ansible-galaxy collection install -r requirements.yml
```

`requirements.yml` pulls in:

- `ansible.posix` (used for `authorized_key`)
- `community.general` (used for `ini_file`, `flatpak_remote`)

## Inventory

`inventory` defines four host groups, referenced by `site.yml`:

```ini
[workstations]
workstation-01.example.com
workstation-02.example.com
workstation-03.example.com

[computeservers]

[mobilestations]

[servers]
```

- `workstations` and `computeservers` get the **common** base role.
- `workstations` and `mobilestations` get the **workstation** desktop role.
- `servers` get only the **server** role (conservative automatic updates).
- All hosts get the **CVMFS + Lmod** integration (it targets `hosts: all`).

The committed `inventory` holds placeholder hostnames only. Keep your real
hosts in `inventory.local` (gitignored) and point Ansible at it:

```bash
cp inventory inventory.local   # then edit with your hostnames
ansible-playbook site.yml -i inventory.local
```

`computeservers`, `mobilestations` and `servers` are left as empty placeholders.

To manage the controller itself as a server, add it to `servers` with
`ansible_connection=local` in your `inventory.local`.

## Usage

```bash
# full run (all three plays, all hosts in inventory)
ansible-playbook site.yml

# target a single host directly
ansible-playbook site.yml -i ws01.example.com,

# dry run
ansible-playbook site.yml --check --diff

# run a subset via tags
ansible-playbook site.yml --tags packages
ansible-playbook site.yml --tags files,system
```

### Tags

| Tag        | What it covers                                              |
|------------|-------------------------------------------------------------|
| `snap`     | Removal and disabling of snapd                              |
| `system`   | Swap/zram, SSH key, locale, apparmor homedir                |
| `packages` | APT repositories and package installation (both roles)      |
| `files`    | Configuration file deployment (both roles)                  |
| `software` | DwarFS and uv/pixi tool installation                        |

The CVMFS play is currently untagged (it always runs when its hosts are
targeted).

## What it configures

### `roles/common` — base system (workstations, computeservers, mobilestations)

- **Snapd:** removes all snaps, purges snapd, and pins APT to block reinstall.
- **Swap:** configures `systemd-zram-generator` plus a disk `/swapfile` sized
  relative to RAM (capped at 8 GB), activated by a `swapfile.swap` systemd
  unit rather than an `/etc/fstab` entry.
- **Repositories:** Launchpad PPAs (graphics drivers, ansible, git-core) and
  `deb822_repository` entries for Apptainer, Kitware CMake, XanMod and Zabbly
  kernels.
- **Packages:** dist-upgrade plus a broad scientific/development package list
  (compilers, build tools, Java, apptainer, munge, FUSE, archive tools, etc.).
- **Files:** `/etc/profile.d` scripts (apptainer X11 forwarding, apptainer
  NVIDIA passthrough, bash-history timestamps), plus
  enabling Ubuntu's commented-out `/etc/profile.d` loop in `/etc/bash.bashrc`
  so those scripts also reach interactive non-login shells (see
  [Apptainer GUI and GPU access](#apptainer-gui-and-gpu-access)),
  unattended-upgrades (see [Automatic updates](#automatic-updates)), polkit rules
  (restrict power management, allow USB mounts, lock NetworkManager),
  systemd (disable suspend/hibernate, 10s shutdown timeout), per-user caches
  on local disk (see [Per-user caches](#per-user-caches)), local scratch
  space (see [Local scratch](#local-scratch)), apcupsd (USB
  UPS), watchdog (`iTCO_wdt`), smartmontools, Firefox APT pins.
- **Software:** installs [DwarFS](https://github.com/mhx/dwarfs) (version-pinned
  from GitHub), and [`uv`](https://github.com/astral-sh/uv) +
  [`pixi`](https://github.com/prefix-dev/pixi) plus a set of system-wide Python
  tools (rsyncy, globus-cli, visidata, awscli, datalad).

### `roles/workstation` — desktop environment (workstations, mobilestations)

- **Repositories:** Kubuntu PPAs, plus `deb822_repository` entries for VS Code,
  Zoom, Zotero, Google Chrome, Brave, and Mozilla Firefox.
- **Packages:** TeX Live, x2go, KDE utilities, language packs, LibreOffice,
  Inkscape, GIMP, browsers, VS Code, Zoom, Zotero, Flatpak.
- **Graphics:** runs `ubuntu-drivers install` (auto-detects NVIDIA drivers).
- **Flatpak:** enables the Flathub remote and a systemd timer for automatic
  flatpak updates.
- **fail2ban:** installs fail2ban with Ubuntu's `sshd` jail (systemd journal,
  nftables bans, which coexist with ufw). `jail.d/impact-lab.conf` bans for 1h
  after 5 failures in 10 minutes, doubling for repeat offenders up to 1 week.
  Only localhost is exempt by default. Add your Ansible controller to
  `workstation_fail2ban_ignoreip` in your untracked inventory so a failed run
  can't lock it out. The other `workstation_fail2ban_*` settings are in
  `roles/workstation/defaults/main.yml`.
- **Display manager:** installs GDM and makes it the default login manager —
  preseeding the shared debconf answer, `/etc/X11/default-display-manager`, and
  the `display-manager.service` symlink, so it wins over the SDDM that
  kubuntu-desktop pulls in. Applied at the next reboot; the role deliberately
  never restarts the display manager, which would kill live sessions.
- **Default session:** deploys accountsservice user templates
  (`/etc/accountsservice/user-templates/`) that record `Session=plasma` for
  users the machine has never seen, i.e. AD accounts at their first login.
  GDM has no `DefaultSession` option — it launches the session saved in
  AccountsService, and with an empty record it falls back to gnome-session,
  which doesn't exist on Kubuntu, so first logins would bounce back to the
  greeter ("Session never registered").
- **Plasma login resilience:** replaces the `xdg-desktop-portal` and
  `xdg-desktop-portal-gtk` user units and adds a plasmashell drop-in to break
  an ordering cycle against `graphical-session.target`. On a slow login that
  cycle stalled the portal long enough for plasmashell to exhaust its restart
  limit, leaving users at a black screen with only a cursor. User units are
  re-read at each login, so no running session is disturbed.

### `roles/server` — servers

- **Automatic updates:** `unattended-upgrades` for the Ubuntu archive only,
  with no automatic reboots. See [Servers](#servers).

### `externals/cvmfs-ansible` — CVMFS + Lmod (all hosts)

A git submodule imported via `import_playbook`. It installs and configures the
CVMFS client, Lmod, and Apptainer, wiring in the Compute Canada and Neurodesk
software repositories so they are usable through `module load`. It also
probes CVMFS at boot and hourly, and keeps a system-wide Lmod spider cache so
`module avail` stays fast. See
[`externals/cvmfs-ansible/README.md`](externals/cvmfs-ansible/README.md) for
full details.

## Project layout

```
.
├── ansible.cfg            # defaults: forks, pipelining, task_summary callback
├── callback_plugins/
│   └── task_summary.py    # prints a per-task failure/ok summary at run end
├── group_vars/all/all.yml # ansible_user: localadmin
├── inventory              # host groups: workstations, computeservers, mobilestations, servers
├── requirements.yml       # ansible.posix, community.general collections
├── roles/
│   ├── common/            # base system role (tasks, handlers, files, vars)
│   ├── server/            # automatic-update policy for servers (tasks, files)
│   └── workstation/       # desktop environment role (tasks, files, templates)
├── externals/
│   └── cvmfs-ansible/     # CVMFS + Lmod integration (git submodule)
└── site.yml               # playbook entry point (four plays)
```

## Apptainer GUI and GPU access

Neurodesk publishes its tools as Apptainer images on CVMFS, fronted by wrapper
scripts that `module load` puts on `PATH`. Those wrappers run

```
singularity --silent exec --cleanenv --env DISPLAY=$DISPLAY ... fsleyes "$@"
```

which forwards `DISPLAY` but nothing else, so the host side has to make up the
difference for a GUI such as `fsleyes` to work.

The X authority cookie used to be part of that. Apptainer binds `$HOME`, `/tmp`
and the cwd by default, but Xwayland keeps the cookie under `/run/user/$UID`,
and `--cleanenv` strips `XAUTHORITY` from the container's environment, so every
GUI died with `Authorization required, but no authorization protocol
specified`. That is now fixed upstream: the wrappers bind the cookie
themselves, and on 2026-08-25 upstream regenerated the wrappers already
published to CVMFS ([neurocommand#809][nd809]). `99-apptainer-display.sh` was
removed once that landed; `roles/common` still deletes it from hosts that got
the old version.

[nd809]: https://github.com/neurodesk/neurocommand/issues/809

What remains is handled by one `/etc/profile.d` script deployed by
`roles/common`:

- **`99-apptainer-gpu.sh` — the NVIDIA driver stack.** libglvnd asks the X
  server which GLX vendor it speaks and then `dlopen`s
  `libGLX_<vendor>.so.0` *from inside the container*. Neurodesk images ship
  Mesa's vendor library but not NVIDIA's, so on a machine where the monitor is
  plugged into an NVIDIA card the lookup fails and every OpenGL application
  dies. The script exports `APPTAINER_NV=1` (the environment-variable form of
  `--nv`) when the NVIDIA kernel module is loaded, which binds the host's
  driver libraries in. This also makes `libcuda.so.1` available, without which
  GPU tools such as FSL's `eddy_cuda` and `bedpostx_gpu` cannot run at all.
  It costs about 19ms of extra container startup per invocation, so opt a
  tight scripted loop — or any single command — out with `APPTAINER_NV=0 <cmd>`.

That script does nothing useful from `/etc/profile.d` alone: that directory is
only sourced by *login* shells. A Wayland desktop session is started by systemd
rather than a login shell, and the terminals opened inside it are non-login
shells, so `roles/common` also uncomments the `/etc/profile.d` loop that Ubuntu
ships disabled in `/etc/bash.bashrc`. Changing the script therefore takes
effect at the next new terminal, not the next reboot.

## Automatic updates

`roles/common` configures `unattended-upgrades` to:

- **Upgrade packages from every configured repository** (`Origins-Pattern
  "origin=*"`), not only the Ubuntu archive. Before this, the browsers, VS Code,
  Zoom, Zotero and the PPAs only updated when the playbook ran, and fell
  several major versions behind. It only upgrades installed packages; it never
  installs new ones.
- **Reboot at 03:00 when an update needs it, but only if nobody is logged
  in** (`Automatic-Reboot-WithUsers "false"`). Without reboots, kernel fixes
  never take effect, and old kernels stay installed. Their NVIDIA module
  packages then block NVIDIA driver security updates ("held broken packages"
  in `/var/log/unattended-upgrades/unattended-upgrades.log`).
- **Run at about 02:30** (an `apt-daily-upgrade.timer` drop-in, instead of the
  stock 06:00). `unattended-upgrades` checks for logged-in users when it runs,
  not at reboot time, so the run has to sit just before the reboot time.

A user who stays logged in (or leaves a desktop session open) prevents the
reboot. Check `/var/run/reboot-required` and reboot such machines by hand.

Flatpaks update daily from their own timer (`roles/workstation`).

### Servers

`roles/server` is more conservative, because a server reboot or a broken
upgrade interrupts every client of its services:

- **Ubuntu archive only:** the release, `-security`, ESM and `-updates`
  pockets. Third-party repositories are not upgraded automatically. A kernel
  and any out-of-tree modules built for it (for example a filesystem driver
  built with DKMS) have to move together, so upgrade those by hand in a
  maintenance window. Before rebooting, check that `dkms status` shows the
  modules built for the new kernel.
- **No automatic reboots** (`Automatic-Reboot "false"`). Check
  `/var/run/reboot-required` and reboot in a planned window.

The server play is tagged `packages` and `files` like the other roles:

```bash
ansible-playbook site.yml --limit servers --tags packages,files
```

## Per-user caches

`roles/common` moves `XDG_CACHE_HOME` off the home directory and onto local
disk at `/var/tmp/xdg-cache/<user>`. On sites with NFS home directories
(especially `sync` exports or Kerberos-secured mounts) every write to
`~/.cache` is a synchronous network round trip. Browsers, shader caches and
thumbnailers write there constantly, so the desktop stalls whenever the file
server is busy. The pieces are:

- `/etc/environment.d/60-xdg-cache.conf` sets `XDG_CACHE_HOME` for the
  systemd user session, and `/etc/profile.d/xdg.cache.sh` does the same for
  shells.
- A `user@.service` drop-in runs `/usr/local/libexec/xdg-cache-dir` to create
  the directory, owned by the user with mode 0700, when the user's systemd
  manager starts.
- `/etc/tmpfiles.d/xdg-cache.conf` deletes cache contents older than 30 days.

`/tmp` is not used because it is tmpfs on these hosts: caches would use RAM
and start empty after every reboot. The change takes effect at a user's next
login once all their existing sessions have ended.

## Local scratch

`roles/common` gives every user a directory on the host's local disk at
`/scratch/<user>`. Use it for job working directories and other intermediate
files, and write only final results to the NFS shares. A pipeline's
intermediate files then stay on the local disk, so they don't load the network
and the file server that every workstation shares. For example:

```bash
fmriprep ... -w /scratch/$USER/fmriprep_work
```

- `/usr/local/libexec/scratch-dir` creates the directory, owned by the user
  with mode 0700. A `user@.service` drop-in runs it at each login, and the
  playbook runs it once for users who are already logged in.
- `/etc/tmpfiles.d/scratch.conf` deletes contents not read or changed for 30
  days. Scratch is not backed up.
- `/etc/apptainer/apptainer.conf` binds `/scratch` into every container, so
  Neurodesk tools can use it without extra `APPTAINER_BIND` settings.

To apply only this part:

```bash
ansible-playbook site.yml --tags scratch
```

## Site-specific assumptions

This playbook was written for one lab's fleet. Review these values before you
run it anywhere else:

| Value | Where | Purpose |
|-------|-------|---------|
| `localadmin` | `group_vars/all/all.yml` | SSH/become user on the targets |
| `domain admins`, `domain users` groups | `roles/common/files/*.rules` | Active Directory groups (via SSSD) that polkit treats as admins, and as allowed to mount USB drives |
| `/home/ad` | `roles/common/tasks/main.yml` | Extra AppArmor home-directory root for AD accounts |
| `en_CA.UTF-8` | `roles/common/tasks/main.yml` | Default system locale |
| USB HID UPS | `roles/common/files/apcupsd.conf` | apcupsd configuration |

## Notes

- `ansible.cfg` sets `host_key_checking = False`, `forks = 500`, SSH
  pipelining, and enables the local `task_summary` callback.
- Tagged runs work because every `include_tasks` in the roles carries
  `apply: {tags: ...}`. A bare `tags:` on a dynamic include tags only the
  include itself, leaving the tasks it pulls in untagged and therefore filtered
  out by `--tags`, which silently turns those runs into no-ops.
- The snap-removal tasks intentionally ignore failures (`failed_when: false`)
  so the role is safe to re-run on systems where snapd is already gone.
- `roles/common/vars/main.yml` is currently an empty placeholder.
- `ansible.log` is written to the repository root and is gitignored.

## License

[MIT](LICENSE).
