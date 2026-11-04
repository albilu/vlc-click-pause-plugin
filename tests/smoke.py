#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later
"""Exercise the compiled plugin in a real, isolated VLC/X11 session."""

import argparse
import os
from pathlib import Path
import re
import select
import shutil
import socket
import subprocess
import sys
import tempfile
import time


def run(args, **kwargs):
    return subprocess.run(args, check=True, text=True, capture_output=True,
                          timeout=20, **kwargs).stdout


def stop(process):
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)


def wait_for(description, predicate):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.1)
    raise AssertionError(f"Timed out waiting for {description}")


def command(remote, text):
    # Discard unsolicited state changes before requesting the current state.
    remote.settimeout(0.05)
    try:
        while remote.recv(65536):
            pass
    except socket.timeout:
        pass
    remote.sendall((text + "\n").encode())
    remote.settimeout(0.2)
    chunks = []
    while True:
        try:
            data = remote.recv(65536)
        except socket.timeout:
            break
        if not data:
            if text == "quit":
                break
            raise AssertionError("VLC closed the remote-control connection")
        chunks.append(data)
    return b"".join(chunks).decode(errors="replace")


def state(remote):
    response = command(remote, "status")
    # oldrc deliberately refuses status commands while its input is paused.
    if "Type 'pause' to continue." in response:
        return "paused"
    states = re.findall(r"\( (?:play|pause|stop) state: (\d+) \)", response)
    if not states:
        raise AssertionError(f"Missing playback state in VLC response: {response!r}")
    return {"3": "playing", "4": "paused", "5": "stopped"}.get(states[-1], states[-1])


def exercise(directory, env, clip, enabled, cache_options):
    label = "enabled" if enabled else "disabled"
    address = directory / f"{label}.sock"
    log_path = directory / f"{label}.log"
    with log_path.open("w+") as log:
        process = subprocess.Popen([
            "vlc", "--ignore-config", "--no-one-instance", "--no-media-library",
            *cache_options, "--intf=oldrc", "--rc-unix=" + str(address),
            "--rc-fake-tty", "--vout=xcb_x11", "--avcodec-hw=none",
            "--no-audio", "--aout=dummy", "--no-video-title-show", "--no-osd", "--loop",
            "--video-filter=" + ("clickpause" if enabled else ""), str(clip),
        ], env=env, stdout=log, stderr=log)
        try:
            wait_for("VLC remote socket", address.exists)
            with socket.socket(socket.AF_UNIX) as remote:
                remote.settimeout(2)
                remote.connect(str(address))
                wait_for("initial playback", lambda: state(remote) == "playing")

                def find_window():
                    result = subprocess.run([
                        "xdotool", "search", "--onlyvisible", "--pid", str(process.pid),
                        "--name", "VLC",
                    ], env=env, text=True, capture_output=True, timeout=5)
                    return result.stdout.splitlines()[0] if result.stdout.strip() else None

                window = wait_for("VLC video window", find_window)
                run(["xdotool", "mousemove", "--sync", "--window", window,
                     "160", "120"], env=env)

                def click(button):
                    run(["xdotool", "click", str(button)], env=env)

                if enabled:
                    click(1)
                    wait_for("left click to pause", lambda: state(remote) == "paused")
                    time.sleep(0.3)
                    assert state(remote) == "paused", "A single click toggled twice"
                    click(1)
                    wait_for("left click to resume", lambda: state(remote) == "playing")
                    for button in (2, 3):
                        click(button)
                        time.sleep(0.2)
                        assert state(remote) == "playing", f"Button {button} paused playback"
                    # Repeated toggles catch stale mouse or playback state.
                    for expected in ("paused", "playing", "paused", "playing"):
                        click(1)
                        wait_for(expected, lambda: state(remote) == expected)
                    run(["xdotool", "windowsize", "--sync", window, "640", "360"], env=env)
                    time.sleep(0.3)
                    run(["xdotool", "mousemove", "--sync", "--window", window,
                         "10", "180"], env=env)
                    click(1)
                    time.sleep(0.3)
                    assert state(remote) == "playing", "Click on a black bar paused playback"
                else:
                    click(1)
                    time.sleep(0.3)
                    assert state(remote) == "playing", "Disabled plugin paused playback"
                    command(remote, "pause")
                    wait_for("pause via VLC", lambda: state(remote) == "paused")
                    click(1)
                    time.sleep(0.3)
                    assert state(remote) == "paused", "Disabled plugin resumed playback"
                    command(remote, "pause")
                    wait_for("resume via VLC", lambda: state(remote) == "playing")
                command(remote, "quit")
                process.wait(timeout=5)
                assert process.returncode == 0, f"VLC exited with {process.returncode}"
                print(f"PASS: {label} click behavior", flush=True)
        except Exception:
            log.flush()
            log.seek(0)
            print(log.read(), file=sys.stderr)
            raise
        finally:
            stop(process)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plugin", nargs="?", type=Path,
                        help="path to the plugin built in the workspace")
    parser.add_argument("--installed", action="store_true",
                        help="test VLC's default plugin path and cache")
    args = parser.parse_args()
    if args.installed == (args.plugin is not None):
        parser.error("provide either a plugin path or --installed")
    plugin = args.plugin.resolve() if args.plugin is not None else None
    if plugin is not None and not plugin.is_file():
        raise SystemExit(f"Missing plugin: {plugin}")
    for executable in ("vlc", "Xvfb", "xdotool", "ffmpeg"):
        if shutil.which(executable) is None:
            raise SystemExit(f"Missing test dependency: {executable}")

    with tempfile.TemporaryDirectory(prefix="vlc-click-pause-test-") as tmp:
        directory = Path(tmp)
        env = os.environ.copy()
        env.update({
            "LC_ALL": "C", "QT_QPA_PLATFORM": "xcb",
            "XDG_CONFIG_HOME": str(directory / "config"),
            "XDG_CACHE_HOME": str(directory / "cache"),
            "XDG_DATA_HOME": str(directory / "data"),
            "XDG_RUNTIME_DIR": str(directory),
        })
        if args.installed:
            env.pop("VLC_PLUGIN_PATH", None)
            cache_options = []
        else:
            env["VLC_PLUGIN_PATH"] = str(plugin.parent)
            cache_options = ["--no-plugins-cache"]
        listing = run(["vlc", "--ignore-config", *cache_options, "--list"], env=env)
        assert re.search(r"^\s+clickpause\s+Click to pause/play", listing, re.M), (
            "VLC did not discover clickpause. Check the installed package and VLC version."
        )
        label = "installed plugin (default path and cache)" if args.installed else "built plugin"
        print(f"PASS: VLC discovers the {label}", flush=True)

        clip = directory / "sample.avi"
        run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i",
             "testsrc2=size=320x240:rate=15", "-t", "8", "-c:v", "mpeg4",
             "-q:v", "5", str(clip)])

        with (directory / "xvfb.log").open("w") as log:
            display = subprocess.Popen([
                "Xvfb", "-displayfd", "1", "-screen", "0", "800x600x24",
                "-nolisten", "tcp",
            ], stdout=subprocess.PIPE, stderr=log, text=True)
            try:
                ready, _, _ = select.select([display.stdout], [], [], 10)
                assert ready, "Xvfb did not start"
                number = display.stdout.readline().strip()
                assert number.isdecimal(), (directory / "xvfb.log").read_text()
                env["DISPLAY"] = ":" + number
                env.pop("WAYLAND_DISPLAY", None)
                exercise(directory, env, clip, enabled=True, cache_options=cache_options)
                exercise(directory, env, clip, enabled=False, cache_options=cache_options)
            finally:
                stop(display)
                display.stdout.close()


if __name__ == "__main__":
    try:
        main()
    except (AssertionError, OSError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error)) from error
