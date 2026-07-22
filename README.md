# Ethernet Wi-Fi Switcher

A tiny macOS menu-bar app that turns **Wi-Fi off when you're on a wired connection**
(dock, Ethernet adapter, etc.) and turns it back **on when you unplug**.

## Build

Requires the Xcode Command Line Tools (`xcode-select --install`). Then:

```
./build.sh
```

This produces `EthernetWiFiSwitcher.app` and `EthernetWiFiSwitcher.zip`.

## Install

1. Drag **EthernetWiFiSwitcher.app** into your **Applications** folder.
2. **Right-click the app → Open**, then click **Open** in the dialog.
   (Needed only the first time — the app is unsigned, so macOS asks once.)

A small icon appears in the menu bar at the top of the screen. That's it.

## Using it

Click the menu-bar icon:

- **Automatic switching** — on by default. Uncheck to leave Wi-Fi alone.
- **Start at login** — check this so it runs every time you turn on your Mac.
- **Quit** — stops the app.

The icon shows the current state: a **cable plug** when wired (Wi-Fi off), an
**antenna** when on Wi-Fi, and a **pause** symbol when automatic switching is
turned off. (The antenna is used instead of the Wi-Fi symbol so it doesn't look
identical to macOS's own Wi-Fi menu-bar icon.)

## Uninstall

Click the menu-bar icon → **Uninstall…** and confirm. That turns Wi-Fi back on,
stops the app from starting at login, and moves it to the Trash. Nothing left behind.
