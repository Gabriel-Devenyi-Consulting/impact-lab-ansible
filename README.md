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

`inventory` defines three host groups, referenced by `site.yml`:

```ini
[workstations]
workstation-01.example.com
workstation-02.example.com
workstation-03.example.com

[computeservers]

[mobilestations]
```

- `workstations` and `computeservers` get the **common** base role.
- `workstations` and `mobilestations` get the **workstation** desktop role.
- All hosts get the **CVMFS + Lmod** integration (it targets `hosts: all`).

The committed `inventory` holds placeholder hostnames only. Keep your real
hosts in `inventory.local` (gitignored) and point Ansible at it:

```bash
cp inventory inventory.local   # then edit with your hostnames
ansible-playbook site.yml -i inventory.local
```

`computeservers` and `mobilestations` are left as empty placeholders.

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
  unattended-upgrades, polkit rules
  (restrict power management, allow USB mounts, lock NetworkManager),
  systemd (disable suspend/hibernate, 10s shutdown timeout), per-user caches
  on local disk (see [Per-user caches](#per-user-caches)), apcupsd (USB
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
├── inventory              # host groups: workstations, computeservers, mobilestations
├── requirements.yml       # ansible.posix, community.general collections
├── roles/
│   ├── common/            # base system role (tasks, handlers, files, vars)
│   └── workstation/       # desktop environment role (tasks, files)
├── externals/
│   └── cvmfs-ansible/     # CVMFS + Lmod integration (git submodule)
└── site.yml               # playbook entry point (three plays)
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
