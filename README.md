# my-roblox-game: Tower Defense

A co-op tower defense game for Roblox, built with Rojo. The server makes every decision, so clients can't give themselves cash, place towers on the path, or upgrade towers they don't own.

## Run it

1. Install [Aftman](https://github.com/LPGhatguy/aftman), then run `aftman install` here (installs Rojo, Selene and StyLua).
2. Install the Rojo plugin in Studio (`rojo plugin install`).
3. Run `rojo serve`, open an empty Baseplate in Studio, and click **Connect** in the Rojo plugin.
4. Press **Play**. Build towers, then click **START GAME**.

If there's no `Workspace.Map`, a default map is built automatically.

## Controls

| Action | Input |
| --- | --- |
| Pick a tower | Click a shop button or press 1 / 2 / 3 |
| Place it | Click the ground (hold **Shift** to keep placing) |
| Cancel | Right-click, **Q** or **Esc** |
| Upgrade / sell | Click one of your towers |
| Skip the break / 2× speed | Vote buttons under the top bar (passes with more than half the server) |

## How it fits together

```
src/shared/   Config (all balance), Path (path maths), Placement (shared rule), Net (remote names)
src/server/   init (remotes + validation + rate limits), Map, GameState (lives/wave/cash),
              EnemyService, TowerService (models + turret aim), WaveService (round loop),
              VoteService (skip / 2x speed), StatsService (saved stats)
src/client/   init (HUD, shop, placement ghost, upgrade/sell panel, votes), Effects (shots, blasts, deaths)
```

- **Balance:** edit `src/shared/Config.luau` to change towers, enemies, waves, prices and the sell refund.
- **Your own map:** in Studio, create `Workspace.Map` with a `Ground` part and a `Waypoints` folder holding parts named `1`, `2`, `3`... along the route. The server reads those instead of building the default map.
- **Rounds:** Lobby → (8 s intermission → wave) × 10 → Victory or Game Over → reset after 10 s. Cash resets each round; kill rewards and wave bonuses go to every player.

## Saved stats

Wins, best wave, kills and games played are saved per player in the `PlayerStats_v1` DataStore and shown on the leaderboard and in the bottom-left corner. Saves only add what changed this session (via `UpdateAsync`), retry with backoff, autosave every 2 minutes and run on shutdown. If a player's data fails to load, nothing is saved for them that session, so good data is never overwritten.

To test saving in Studio, turn on **Game Settings → Security → Enable Studio Access to API Services**.

## Claude Code

`.claude/settings.json` enables the LihFolk Roblox plugin for Claude Code sessions opened on this repo.
