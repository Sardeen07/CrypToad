Screenshots used by the main README: `home.png`, `activity.png`, `trade.png`, `home-dark.png`.

They come from the UI tests in `CrypToadUITests/`: `ScreenTourUITests` attaches a screenshot of
every screen (light, dark, and accessibility text size) and `ServerFlowUITests` captures the
signed-in flow. Export them with `xcrun xcresulttool export attachments`.

To capture one, run the app in an iPhone simulator, open the screen, then:

```bash
./scripts/screenshot.sh home
```

The script sets a clean status bar (9:41, full battery) and saves to this folder.
