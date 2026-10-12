# Iris

A tiny macOS menu bar app for adjusting your webcam: brightness, contrast, saturation,
sharpness, gain, zoom, white balance, exposure, focus, backlight compensation and
anti-flicker. A lightweight alternative to vendor apps like Logi Options+ / Logi Tune.

- **Small:** a ~2 MB app using ~26 MB of memory, with no background services.
- **Works everywhere:** talks to the camera directly over USB (UVC control requests via
  IOKit), so changes apply in Zoom, Teams, Meet, FaceTime, OBS, etc.
- **Remembers your settings:** most webcams forget them when they lose power, so Iris
  saves them per camera model and re-applies them when the camera reconnects or Iris launches.
- **Native look:** a Liquid Glass panel in the style of Control Center, with an optional
  live preview. Turning off an Auto toggle reveals its manual slider; hover a slider and
  click the reset arrow to restore its default.

Works with USB webcams that follow the UVC standard (most of them). Only the controls your
camera supports are shown. Built-in Mac and Studio Display cameras aren't UVC devices and
can't be controlled this way.

## Install

Requires an Apple Silicon Mac running macOS 26 (Tahoe).

1. Download `Iris.zip` from [Releases](../../releases/latest), unzip it, and move
   **Iris.app** to Applications.
2. Open it. Iris isn't notarized, so macOS will say it can't verify the developer. Go to
   **System Settings → Privacy & Security** and click **Open Anyway**.
   (Or run `xattr -dr com.apple.quarantine /Applications/Iris.app`.)

## Build from source

Needs only the Xcode Command Line Tools (`xcode-select --install`).

    ./build.sh        # builds, signs ad-hoc, installs to ~/Applications/Iris.app

Diagnostics:

    Iris.app/Contents/MacOS/Iris --probe [--set brightness=128]   # list/set camera controls
    Iris.app/Contents/MacOS/Iris --open                           # open the menu at launch

## License

MIT
