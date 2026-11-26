# Perky Crew fork changelog

Changes made in this fork (`Rockin-Vik/eq-autocombat-morituri`) so MoriAC runs on the **Perky Crew** server. Upstream changes are in [autocombat/CHANGELOG.md](autocombat/CHANGELOG.md).

Unless a change says otherwise, Morituri behaves exactly as before. Code that differs between servers checks `MORIAC_IS_MORITURI()` (in `lua/moriac.lua`), which reads the server name each time it's needed.

## Perky Crew facts the changes rely on

- One main class per character. Rebirth lets you buy AAs from other classes, but not their spells or discs.
- Level cap 54. Content is a mix of late Planes of Power and selected zones.
- `#attackmode` doesn't exist. Bows fire with the normal `/autofire`.
- `#nms` and the `kratos` buff NPC are Morituri-only.

## 2026-11-25 (4)

- **Boxnet is safer by default.** Peers can no longer make your boxes run plain slash commands unless you turn "also run slash commands" on. Even then, code-loading, chat, petition and logout commands (`/lua`, `/mac`, `/say`, `/tell`, `/ooc`, `/1`, `/quit` and similar) are always refused, also when wrapped in `/nomodkey`, `/squelch`, `/noparse`, `/timed N` or `/docommand`. Nested `/ac net` and `/multiline` are refused. Only the transport's sender name is trusted.
- **Spell memorising can no longer hang MoriAC.** Waiting for the casting window now gives up after 15 seconds.
- **Player chat can no longer trigger cast lockouts.** The "not ready", "insufficient mana" and "can't cast while" events now match only EQ's own system messages.
- **Saves are crash-safe.** Loadouts and the DPS, map, inventory and chat-trace files are written to a temp file and renamed into place, keeping a `.bak`. Loadouts load from `.tmp`/`.bak` if the main file is missing.
- **A UI error no longer freezes the game.** Page draws in the main and mini windows are guarded; an error shows in the window and is logged once.
- **Plugin fixes.** Enabling an enabled plugin does nothing; reloading calls the old instance's cleanup first. The Plugins/Update pages no longer start the plugin manager while drawing.
- **Death clears pending memorise, bard song and downtime steps.**
- **Alerts:** pattern edits apply when you leave the field; patterns that match every line (`#*#`, `#1#`, `*`) are rejected or skipped.
- **Updater downloads files from the exact commit in the manifest.**
- **Performance:** combat tick every 0.2 s measured from tick start; reposition after "too far" runs in the combat tick; fewer XTarget and spawn lookups; spell mana/duration cached; AA/ability rows rebuilt every 15 s instead of 1 s; AA ID scan spread over ticks; cheaper sorts on the Plugins page and HUD effects.

## 2026-11-25 (3): Settings files get the server name on Perky

- **Problem:** on Perky, `EverQuest.ServerName` and `Zone.Server` come back empty, so every character's settings went to `moriac_loadout__<char>.lua`. A character with the same name on another server that also reports an empty name would share the file, and the camp-to-another-server reload couldn't tell the servers apart.
- **Fix:** `runtime.currentServer()` still tries `ServerName`, then `Zone.Server`, so servers where those work keep their file names. It falls back to `EverQuest.Server`, so Perky files are now `moriac_loadout_Perky_Crew_<char>.lua`. Values that are empty, `NULL` or `nil` all count as empty. The MoriAC log file name follows the same name.
- **Existing settings:** the first time a Perky character loads under the new name, MoriAC copies `moriac_loadout__<char>.lua` (or its `.tmp`, or an older `triune_loadout__<char>.lua`) to the new name. It copies, never moves, and never overwrites a file that's already there. The copy never happens on Morituri, because the empty-name file is shared and may hold another server's settings.
- **Server-change reload:** MoriAC remembers which source named the server and only watches that one, so another source spelling the same server differently can't make it reload back and forth. If that source goes empty after a camp, the current name decides.
- **Timers:** the plugin's change-detection key now uses all three sources.
- **Review:** two review passes by a model from another vendor. The first found that the copy could pull the shared file into a Morituri character, that a spelling difference between sources could make it reload over and over, the missing `triune_` and `.tmp` sources, and the `NULL` placeholder. The second found that the first fix for the spelling problem could hold back a real camp's reload. All are fixed.

## 2026-11-25 (2): `/lua run mac` froze the game

Commit `7ad2423`.

- **Problem:** `/lua run mac` froze the client at 100% CPU the moment it started. The game never drew another frame and had to be ended in Task Manager. A trace showed the main loop running about 7,500 times a second instead of about 6.
- **Cause:** `lua/mac.lua` started `moriac.lua` with `dofile`. In MacroQuest's LuaJIT, `dofile` is a C call, so `mq.delay` can't pause through it and returned immediately every time.
- **Fix:** `mac.lua` now uses `loadfile(...)` and calls the result as a normal Lua function.
- `/lua run moriac` was never affected.
- This bug is also in upstream.

## 2026-11-25 (1): Run on Perky Crew

Commit `ffc3c0f`.

- **Server-only plugins:**
  - **Timers:** `/say kratos` is a default timer only on Morituri. The **Add Kratos** button still works everywhere.
  - **NMS Loot (`#nms`):** off by default except on Morituri. A plugin's `defaultEnabled` can now be a function, which is checked at every (re)start.
  - A saved on/off choice for a character always wins over these defaults.
- **Ranged style and bow pulls:** off Morituri they use `/autofire` instead of `/say #attackmode`, and turn it off again when you leave Ranged style or a pull ends.
- **Camping to another server:** MoriAC now reloads that server's settings, even if the character name is the same. Settings are flushed to the file of the server they came from.
- **Rebirth AAs:** off Morituri, the AAs page also lists activated AAs from other classes once you own a rank. Firing never checked class.
- **Updater:**
  - It now checks this fork, not `traylz2000/eq-autocombat-morituri`. Only what you push here reaches your install.
  - It still only offers updates; it never installs on its own.
  - `update_manifest.txt` is regenerated by hand on every push. Sizes and CRC-32 come from the LF bytes stored in git (`git show :autocombat/<path>`), not from Windows CRLF copies.
- **Review:** the change had two adversarial reviews by a model from another vendor, and their findings are fixed. They found that the server was only checked once at load, that Add Kratos did nothing off Morituri, that the updater would have rolled back the changed files, a per-tick `/attack off` repeat, timer edits lost on an off/on toggle, a missing `Zone.Server` fallback, and a non-boolean `defaultEnabled`.

## Install notes (`C:\E3NextAndMQ`)

- Installed: `lua/mac.lua`, `lua/moriac.lua`, `lua/tac/`, `config/moriac_data.lua`, `config/moriac_alarm.wav`. Copy them from git as LF (`git -c core.autocrlf=false archive`), so they match the manifest.
- **Not installed:** the repo's `config/ingame.cfg`, because it would auto-start MoriAC on every login. Yours keeps `/mono e3`.
- **E3Next:** E3Next lives in the same MQ folder. Don't run E3 and MoriAC on the same character.
- **Not downloaded:** the 950 MB `resources/` bundle (navmeshes and the game database). Hunt, Camp and Lure pulling need an MQ2Nav mesh per zone, and `MeshGenerator.exe` in the MQ folder can build one. The Game DB window warns that its files are missing.

## Known issues and gaps

- **Missing AAs:** AAs that aren't in `config/moriac_data.lua` at all, such as custom Perky AAs, don't show on the AAs page.
- **Cosmetic:** the window still shows four class slots, and the Spells level filter tops out at 70 (Perky's cap is 54).
- **Untested in game:** Ranged style with `/autofire`, rebirth AAs on the AAs page, and pulling.
- **Not assumed checked:** that EQ turns `/autofire` off when you zone.
- **Not caused by MoriAC:** a zone-in through Meldrath to Meldrath's Majestic Mansion stalled on 2026-11-25. The client sent `MSG_EQ_ADDPLAYER` and the server never answered with `MSG_SEND_PC`. MoriAC ran no code during it.
- **Upstream changes:** they don't reach this fork on their own. Merging upstream will overwrite the updater's repo setting and the manifest, so redo both after a merge.
