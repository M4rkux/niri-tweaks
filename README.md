# niri-tweaks

A small patch for the [niri](https://github.com/YaLTeR/niri) Wayland compositor, plus a set of
window-management shortcuts in the style of
[DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell).

**Tested with niri `v26.04`** (commit `8ed0da4`). Other versions may work if the patch still
applies; `install.sh` tells you if it doesn't.

## What's included

All patch features are **off by default**. You turn them on in your niri config, so installing the
patch alone changes nothing.

### 1. Right-aligned columns per monitor: `align-columns-right`

niri always lays columns out from the left edge. With two monitors side by side, you may want the
**left** monitor's windows pushed to its **right** edge, so windows on both screens meet in the
middle and you turn your head less.

```kdl
// Use `niri msg outputs` to find your monitor's name.
output "HDMI-A-1" {
    layout {
        align-columns-right
    }
}
```

On that monitor:

- When the columns fit on screen, the last one sits against the right edge. When they don't fit,
  niri's normal scrolling takes over.
- **New windows open to the left** of the focused one (the mirror image of normal niri).
  This also applies to dialogs and to windows moved in from another monitor.
- Resizes are anchored on the right: when a window changes width, the windows to its right stay
  put. This matters when you move a window from a bigger monitor and the app shrinks a few frames
  later. Without it, the window that was already there slides out and back.
- Fullscreen and maximized windows behave as usual.

It also works globally (in the top-level `layout {}`), but it's mostly useful per output.

### 2. Toggle `center-column`: `toggle-center-column`

By default, `center-column` (`Mod+C` in the shortcuts below) centers the focused column, and
pressing it again does nothing. With this option, **pressing it again returns the view to where it
was** before centering. It only goes back if you're still on the same window and the view is still
centered. Otherwise the press centers again. `center-window` keeps its normal behavior.

```kdl
layout {
    toggle-center-column
}
```

### 3. Reset window height when it's alone in a column: `reset-height-when-alone`

If you stack windows in a column and give one a fixed or preset height (e.g. with
`switch-preset-window-height`), niri keeps that height after the other windows close. The
survivor then doesn't fill the column. With this option, the last window in a column goes back
to auto height. This happens in the same layout update as the close, so there's no second jump.

```kdl
layout {
    reset-height-when-alone
}
```

(This replaces the `extras/auto-reset-height` daemon, which does the same thing on stock niri by
watching the IPC event stream and fixing the height after the fact.)

### 4. Shortcuts: `binds.kdl`

Window-management binds from DankMaterialShell's niri setup: focus/move columns and windows,
`Mod+Ctrl` focuses monitors, `Mod+Shift+Ctrl` moves columns to monitors, workspaces, and sizing
(`Mod+R` preset width, `Mod+Shift+R` preset height, `Mod+Ctrl+R` reset height, `Mod+C` center,
`Mod+±` width, `Mod+Shift+±` height). See [`binds.kdl`](binds.kdl) for the full list. They only
use niri actions: no app launchers, no shell-specific IPC.

## Install

### 1. Build dependencies

You need `git`, a Rust toolchain (`cargo`), and niri's build dependencies:

- **Arch / CachyOS / Manjaro:**
  ```sh
  sudo pacman -S --needed git rust clang libxkbcommon libinput mesa libdisplay-info pipewire pango seatd
  ```
- **Fedora:**
  ```sh
  sudo dnf install git cargo gcc clang libudev-devel libgbm-devel libxkbcommon-devel wayland-devel libinput-devel dbus-devel systemd-devel libseat-devel pipewire-devel pango-devel cairo-gobject-devel libdisplay-info-devel
  ```
- **Ubuntu 24.04:**
  ```sh
  # Ubuntu's packaged cargo is too old for niri; install Rust with https://rustup.rs instead.
  sudo apt-get install -y git gcc clang libudev-dev libgbm-dev libxkbcommon-dev libegl1-mesa-dev libwayland-dev libinput-dev libdbus-1-dev libsystemd-dev libseat-dev libpipewire-0.3-dev libpango1.0-dev libdisplay-info-dev
  ```

You also need niri itself installed from your distro (for `niri-session`, the systemd units, and
the portals config). This repo only replaces the `niri` binary.

### 2. Build and install the patched niri

```sh
git clone https://github.com/M4rkux/niri-tweaks.git
cd niri-tweaks
./install.sh
```

`install.sh`:

1. detects your installed niri version (`pacman -Q niri`, or `/usr/bin/niri --version`),
2. clones niri into `~/.cache/niri-tweaks/niri` and checks out that tag,
3. applies `patches/niri-tweaks.patch` and builds it (the first build takes a few minutes),
4. checks your current config with the new binary,
5. installs it to **`/usr/local/bin/niri`** (asks for sudo).

`/usr/local/bin` comes before `/usr/bin` in `PATH`, including systemd's, so `niri-session` picks up
the patched build. Your package manager still owns `/usr/bin/niri`, so there's no file conflict.

**Log out and back in** to start using it. Then check:

```sh
ls -l /proc/$(pidof niri)/exe   # -> /usr/local/bin/niri
```

### 3. Turn things on

```sh
./setup-config.sh
```

This script:

- reads the binds already in your config (every `.kdl` under `~/.config/niri`),
- lists the shortcuts whose keys are free and adds them after one confirmation,
- **asks key by key** when a shortcut would replace one of yours (`y` replace, `n` keep,
  `a` replace all, `s` keep all), and skips the ones you already have,
- offers to enable `toggle-center-column` and `reset-height-when-alone` (only if the patched niri
  is running),
- writes everything to `~/.config/niri/niri-tweaks.kdl` and adds `include "niri-tweaks.kdl"` at the
  end of `config.kdl`. It backs up both files first and rolls back if `niri validate` fails.

Run it again any time to change your answers. `align-columns-right` depends on your monitor
names, so add it yourself as shown above.

## After a niri update

A distro update replaces `/usr/bin/niri`, but `/usr/local/bin/niri` (the old patched build) keeps
running, so nothing breaks. You just stay on the old version until you rebuild:

```sh
./install.sh          # rebuilds for the newly installed version
```

Then log out and back in. If the patch no longer applies to the new version, the script stops
without installing anything. You can stay on the tested version with `./install.sh v26.04`.

## Uninstall

```sh
./install.sh --uninstall   # removes /usr/local/bin/niri
```

Then remove the `include "niri-tweaks.kdl"` line from `config.kdl`. The layout options aren't
valid on stock niri. Also remove `align-columns-right` if you added it. Log out and back in.

## Development

The patch also adds tests (`src/layout/tests/align_right.rs`, `src/layout/tests/tweaks.rs`). To work
on it:

```sh
cd ~/.cache/niri-tweaks/niri            # patched checkout made by install.sh
cargo test --release --lib layout::
RUN_SLOW_TESTS=1 PROPTEST_CASES=5000 cargo test --release --lib random_operations
git add -A && git diff --cached > /path/to/niri-tweaks/patches/niri-tweaks.patch
```

## License

GPL-3.0-or-later, same as niri. The patch modifies niri's source.
