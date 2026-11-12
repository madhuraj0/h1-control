# H1 Control

**Unofficial** Android and macOS apps for the **realme TechLife Studio H1** headphones, which have no
companion app. Switch noise control, see battery and the codec in use, and check what the headphone
buttons have switched on.

> Not affiliated with, endorsed by or supported by realme. "realme" and "TechLife Studio H1" are used only
> to say which headphones this works with. Use at your own risk.

## Features

| | Android | macOS |
|---|---|---|
| Noise control: Off / Transparency / ANC | ✅ app + Quick Settings tiles | ✅ menu bar |
| Battery level | ✅ | ✅ |
| Game mode, spatial audio status¹ | ✅ | ✅ |
| Bluetooth codec in use and best supported (e.g. LDAC 96 kHz) | ✅ | — |
| Wired (USB-C) mode: supported formats | ✅ incl. bit-perfect support | ✅ incl. switching to 96 kHz / 24-bit |
| Sound check: channel test, moving sound for spatial audio, high-frequency sweep | ✅ | — |
| Reconnects automatically (e.g. after switching LDAC) | ✅ | ✅ |
| Material You colours, light and dark | ✅ | — |

¹ The headphones only report these when you press the button, so the apps show the last state they
reported. They can't be switched from an app; see [Limitations](#limitations).

## Install

Download from the [latest release](../../releases/latest).

**Android** (8.0 or later): install `H1-Control-<version>.apk`. You may need to allow installing apps
from your browser or file manager. Pair the headphones in Bluetooth settings, open the app and allow
Bluetooth access.

**macOS** (13 or later, Apple silicon): unzip `H1-Control-<version>-macOS-arm64.zip` and move
**H1 Control** to Applications. The app isn't notarized by Apple, so the first launch is blocked: open
**System Settings › Privacy & Security** and click **Open Anyway**. Allow Bluetooth access when asked. The
app lives in the menu bar (headphones icon).

The headphones accept **one control connection at a time**. If both your phone and Mac run H1 Control,
whichever connects first gets it, and the other waits and retries. If neither can connect after an app was
force-quit, turn the headphones off and on.

## Limitations

- **Game mode, spatial audio, LDAC and adaptive noise** can only be switched with the headphone buttons.
  No working command was found for setting them.
- **Game mode only works with LDAC off.** The headphones ignore the gesture while LDAC is on.
- **Adaptive noise** state isn't reported by the headphones at all.
- **Noise-mode changes made with the ANC button** aren't reported, so the apps show the last mode set from
  the app.
- **While on USB-C** the headphones switch Bluetooth off, so only audio-format information is available.
- Only tested with firmware 2.4.0, on one Android phone (Android 15) and one Mac (macOS 26, Apple silicon).

## Button guide

| Button | Action | Does |
|---|---|---|
| ANC | Press | Transparency / ANC on / ANC off |
| ANC | Press twice | Spatial audio on/off |
| ANC | Press 3 times | LDAC on/off |
| ANC | Hold 1 s | Game mode / music mode (LDAC must be off) |
| O | Press | Play/pause, answer or end a call |
| O | Press twice | Voice assistant |
| O | Press 3 times | Pairing mode |
| O | Hold 1 s | Decline a call |
| + / − | Press | Volume up / down |
| + / − | Hold 2 s | Next / previous track |
| ANC and + | Hold 1 s | Adaptive noise on/off |

## Project layout

- `core/`: Kotlin Multiplatform protocol library (framing, parsing, state). No Bluetooth code; bytes in,
  bytes out. Tested on the JVM and natively on macOS against bytes captured from real headphones.
- `androidApp/`: Android app (Jetpack Compose, Material 3) with Quick Settings tiles.
- `macApp/`: macOS menu bar app (SwiftUI + IOBluetooth), using the core as a Kotlin/Native framework.
- `tools/probe/`: macOS scripts used to work out the protocol.

## Build

```bash
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
./gradlew :core:jvmTest                 # protocol tests
./gradlew :androidApp:assembleRelease   # Android APK (signed if ~/.h1-control/keystore.properties exists)
macApp/build.sh                         # builds "macApp/build/H1 Control.app"
```

The Mac build needs only the Command Line Tools (`xcode-select --install`) and JDK 17. Kotlin/Native asks
`xcodebuild` for a version, so without full Xcode, `tools/make-devdir.sh` creates a local stand-in developer
directory (`.devdir/`: symlinks to the Command Line Tools plus a stub `xcodebuild`). The build script uses it
automatically.

## How it works

The headphones use a JieLi AC697 Bluetooth chip and accept JieLi's RCSP control protocol, without
authentication, on their serial-port (SPP) RFCOMM channel. Verified on firmware 2.4.0.

| RFCOMM | UUID | What |
|---|---|---|
| 1 | `00001101-…` (SPP) | JieLi RCSP: used by these apps |
| 10 | `df21fe2c-2515-4fdb-8886-f12c4d67927c` | Google Fast Pair message stream |

RCSP frame: `FE DC BA <flag> <opcode> <len BE16> <body> EF`. A command body is `<sn> <payload>`; a response
body is `<status> <sn> <payload>`. Flag `0xC0` marks a command that wants a response.

| Command | Bytes | Notes |
|---|---|---|
| Read status | `07` `FF FF FF FF FF` | TLVs `<len><attr><data>`: `00` battery %, `0D` current noise mode, `0E` all noise modes |
| Set noise mode | `08` `FF 0A 0D <mode> <8 gain bytes>` | mode `00` off, `01` ANC, `02` transparency; gains from attr `0E` |
| Change push | headphones → `09` | sent after a setting changes over Bluetooth |

Button presses send `85 86 87 02 <feature> <value>` frames on channel 1: feature `04` is game mode
(`01`/`00`) and `05` is spatial audio (`00` off, `06` on). Sending these back has no effect, and neither does
JieLi's standard work-mode setting, so setting game mode and spatial audio remains unsolved.

Over USB-C the headphones are a JieLi USB audio device (44.1/48/96 kHz, 16/24-bit) whose HID interface only
carries media keys, so there's no control channel when wired.

## Credits

Inspired by [BudsControl](https://github.com/amarsakore/BudsControl) for OnePlus Buds. Command names
follow JieLi's public [RCSP SDK documentation](https://github.com/Jieli-Tech/Android-JL_Bluetooth).
No code from either project is included.

## License

[MIT](LICENSE)
