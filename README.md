# VLC click to pause/play

A minimal native **Linux / VLC 3.x** plugin: left-click the video image to
pause, and click again to resume. Frames pass through unchanged, with no pixel
copies, background threads, or polling. The plugin uses VLC's standard
play/pause action and its normal on-screen indicator.

## Build and install

For Debian, Ubuntu, and derivatives using the distribution's native VLC package:

```sh
sudo apt install build-essential pkg-config python3 libvlccore-dev vlc
make
sudo make install
```

Restart VLC after installation. The build uses `pkg-config vlc-plugin` to find
the matching headers, libraries, and plugin installation directory. On other
Linux distributions, install the equivalent VLC development package and a C
compiler, GNU Make, Python 3, and pkg-config, then use the same build commands.

## Enable or disable

1. Open **Tools → Preferences** (`Ctrl+P`).
2. Set **Show settings** to **All**.
3. Select the **Filters** row under **Video** in the left tree.
4. In the **right-hand panel**, find **Click to pause/play** in the **Video filter
   module** checkbox list. Widen the window or scroll that panel vertically and
   horizontally to see both columns. Check it to enable, or uncheck to disable.
5. Click **Save**, then restart VLC.

There is no separate **Click to pause/play** page in the left tree. The text box
below the checkbox list is the active filter chain, not a search field: the
module name there must be `clickpause`, not `click`. Checking the box writes the
correct name automatically. Preserve any other filters you already have enabled.

The checkbox is VLC's built-in video-filter control. Installation leaves the
feature disabled until you enable it. Clicks on playback controls and outside
the video image are unaffected. Right and middle clicks are passed through.
The toggle happens on the left-button press; there is no delay to distinguish
single clicks from drags or double clicks. VLC still receives mouse events,
including its normal fullscreen double-click gesture.

To try the build without installing it or changing saved preferences:

```sh
VLC_PLUGIN_PATH="$PWD/build/en${VLC_PLUGIN_PATH:+:$VLC_PLUGIN_PATH}" \
    vlc --no-one-instance --video-filter=clickpause /path/to/video.mp4
```

Use `build/en` as the plugin directory for the English build, or `build/fr` for
the French build. Do not point `VLC_PLUGIN_PATH` at their common `build` parent:
VLC scans recursively and would discover both language variants.

This targets the desktop VLC player with its default hotkeys interface enabled.
Build against the VLC installation that will load the plugin; VLC 4.x and
Flatpak/Snap installations are outside this build's scope.

## French version

Build and package the French interface with:

```sh
sudo apt install gettext
make UI_LANGUAGE=fr
make UI_LANGUAGE=fr deb
sudo apt install ./dist/vlc-plugin-clickpause-fr_0.2.0_amd64.deb
```

Use the package matching your CPU architecture. The French package replaces the
English `vlc-plugin-clickpause` package; both use the same internal `clickpause`
filter identifier, so your saved enable/disable setting carries over. Restart
VLC after upgrading.

Dans **Outils → Préférences → Tous → Vidéo → Filtres**, cochez **Lecture/pause au
clic** dans la liste de droite, puis cliquez sur **Enregistrer** et redémarrez
VLC. L’aide de cette case est également traduite en français.

Translations live in `po/fr.po`. The selected catalog is compiled with GNU
gettext, then embedded in the plugin. This is a **build-time language choice**:
VLC 3's Qt filter list translates labels only through VLC's own catalog, and
plugin descriptors are cached independently of the interface language. Embedding
the translation makes the French label and help work with the normal plugin
cache. Changing VLC's interface language does not change this plugin's language.

`UI_LANGUAGE=en` (the default) builds the English version. Each language has its
own output directory under `build/`. Use `make pot` to refresh the translation
template after changing the English strings; it requires `xgettext` from the
gettext package. For manual installation or removal, pass the same
`UI_LANGUAGE=fr` to `make install` or `make uninstall`.

## Distribute

Create a source archive that users can build for their own Linux distribution:

```sh
make dist
# dist/vlc-click-pause-0.2.0.tar.gz
```

On Debian/Ubuntu, create an installable package without root or debhelper:

```sh
sudo apt install dpkg-dev binutils
make deb
sudo apt install ./dist/vlc-plugin-clickpause_0.2.0_*.deb
```

The package derives its VLC ABI dependency from the compiled plugin and its
library dependencies with `dpkg-shlibdeps`. Build separately for each target
distribution/release and CPU architecture; a `.so` is not a universal Linux
binary. Set `DEB_MAINTAINER='Your Name <you@example.org>'` when producing a
release. Include the matching source archive when distributing binaries under
the LGPL.

For distro packaging or a staged installation:

```sh
make install DESTDIR="$PWD/stage"
make install DESTDIR="$PWD/stage" PLUGINDIR=/usr/lib/vlc/plugins
```

`PLUGINDIR` defaults to `pkg-config --variable=pluginsdir vlc-plugin` and can be
overridden for a custom VLC installation. `PREFIX` controls documentation paths;
it does not relocate VLC's plugin search path. The `.deb` uses the system plugin
directory and `/usr/share/doc/vlc-plugin-clickpause` (or
`/usr/share/doc/vlc-plugin-clickpause-fr` for the French package).

Remove a manual installation with `sudo make uninstall`, or a packaged one with
`sudo apt remove vlc-plugin-clickpause`. If VLC does not discover a newly installed
plugin, close VLC and run `vlc --reset-plugins-cache` once.
For the French package, use `sudo apt remove vlc-plugin-clickpause-fr`.

## Verify

```sh
sudo apt install python3 xvfb xdotool ffmpeg
make check
# After installing the .deb, test the system-installed copy:
make check-installed
# Test the French build or an installed French package:
make UI_LANGUAGE=fr check
make UI_LANGUAGE=fr check-installed
```

The smoke test creates its own video, X display, and temporary VLC configuration.
It checks plugin discovery, pause and resume via real mouse clicks, unchanged
playback for other mouse buttons and black bars, and disabled behavior. It does
not change your running VLC instance or preferences.
`check-installed` uses VLC's normal plugin search path and cache without a
`VLC_PLUGIN_PATH` override, and does not need the VLC development headers.

Verified with VLC 3.0.24 on Linux, including saving the Preferences checkbox in
both states. Compilation was also checked against VLC 3.0.21 headers.

The implementation follows VLC's [video-filter mouse API](https://github.com/videolan/vlc/blob/3.0.x/include/vlc_filter.h)
and [play/pause action handler](https://github.com/videolan/vlc/blob/3.0.x/modules/control/hotkeys.c).
Licensed under [LGPL-2.1-or-later](LICENSE).
