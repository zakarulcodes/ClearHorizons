# ClearHorizons

A small World of Warcraft addon for **WoW Forever** that clears the volumetric fog and the weather (rain, snow, sandstorms), and can mute weather sounds.

Many players get eye strain or headaches from the dense volumetric fog, and the game has no setting that turns it off. ClearHorizons clears it with a lightweight trick and a low performance cost.

## How it works

**Fog.** The volumetric fog builds up over many frames. Every time the `volumeFogLevel` setting changes, the game throws that built-up fog away and starts over. ClearHorizons changes the setting every few frames, so the fog never gets the chance to build up.

It always switches between fog levels **0 and 1**, the two cheapest levels. The fog is never visible either way, so there is no reason to pay for a higher quality level.

**Weather effects.** Weather needs no trick. You pick a level, Off, Light, Medium or Heavy, and ClearHorizons sets `weatherDensity` and `RAIDweatherDensity` to it (0 to 3). It checks every 2 seconds and puts your level back if a graphics preset or another addon changed it.

**Weather sounds.** ClearHorizons can mute the rain, snow, sandstorm and thunder sounds with WoW's `MuteSoundFile`, while other ambient sounds (birds, crowds, water) keep playing. This works on its own, so you can keep the weather visible and only lose the sound.

**Your settings are safe.** ClearHorizons remembers your original fog level and weather density. It puts them back when you turn an option off or log out, so removing the addon returns the game to how it was.

ClearHorizons only uses the normal addon API to change game settings. It does not touch game files or memory.

## Install

1. Download `ClearHorizons-<version>.zip` from the [latest release](../../releases/latest).
2. Extract it into `World of Warcraft\_forever_\Interface\AddOns\`, so you end up with `AddOns\ClearHorizons\ClearHorizons.toc`.
3. Restart the game.

Turn off any other fog addon in the AddOns list. Two addons changing the same setting would fight each other.

## Usage

**Minimap button**
- Left-click: open the options window
- Right-click: turn fog clearing on or off
- Drag: move the button around the minimap

**Slash commands**

| Command | What it does |
|---|---|
| `/ch` | Turn fog clearing on or off |
| `/ch on`, `/ch off` | Turn fog clearing on or off |
| `/ch 1` to `/ch 4` | Set the strength (how often the fog setting changes) |
| `/ch weather` | Switch weather effects between Off and your last level |
| `/ch weather 0` to `/ch weather 3` | Set the weather effects level (0 Off, 1 Light, 2 Medium, 3 Heavy) |
| `/ch sounds` | Mute or unmute weather sounds |
| `/ch options` | Open the options window |

**Strength.** Strength 4 changes the setting every frame and strength 1 every 4th frame. Higher is smoother but costs more FPS, because the fog setting changes more often. Raise it if you see the fog flicker or the camera jitter.

**Tip: cap your FPS.** At strength 4, every other frame is drawn at a different fog level, which can cause a slight jitter when you pan the camera. Setting Max Foreground FPS (System > Graphics) about 10 to 15% below your usual low FPS smooths it out.

## License

[MIT](LICENSE)
