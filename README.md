# Claude Awake

A one-click Windows toggle that keeps your laptop awake with the lid closed, so Claude Code sessions keep running.

While it's on, a tray icon shows, closing the lid does nothing, and idle sleep is blocked (the screen can still turn off). Turning it off puts your original lid-close setting back.

## Install

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\ClaudeAwake.ps1 -Install
```

This creates a **Claude Awake** shortcut on your Desktop and in the Start Menu.

## Use

- **Turn on:** open the Claude Awake shortcut.
- **Turn off:** open the shortcut again, double-click the tray icon, or right-click it and pick **Turn off**.

Your original lid setting is restored on turn-off and on shutdown, restart or sign-out.

## Notes

- Turn it off before putting the laptop in a bag. With the lid closed it's still fully running and will get hot and drain the battery.
- If the PC crashes or loses power while it's on, the lid can be left on "Do nothing". Turning it on and off again fixes that, or run `ClaudeAwake.ps1 -Cleanup`.
- It only changes the lid-close action of your current power plan, for both plugged in and on battery. No admin rights needed.
