# Roblox Studio wouldn't start under Vinegar (2026-07-20)

**Symptom:** launching Vinegar printed a short burst of Wine errors and then
`Goodbye!` roughly a minute later. No Studio window ever appeared. It looked like a crash.

**Cause:** the `forced_version` pin in Vinegar's `config.toml` held Studio at 0.727.
That build started hanging during startup against Roblox's current backend config.

**Fix:** removed the pin so Vinegar installed Studio 0.730. Working immediately.

```bash
# ~/.var/app/org.vinegarhq.Vinegar/config/vinegar/config.toml
# delete the [studio] / forced_version block, then launch Vinegar normally
```

The pin was added because Vinegar 1.9.3 couldn't handle `RobloxStudioInstaller.exe`
in Roblox's package manifest. Vinegar 1.9.4 installs it fine, so the pin was obsolete
*and* had become the thing breaking Studio.

---

## Why the console output was misleading

Every alarming line in the terminal also appears in sessions that start perfectly.
None of them are the problem:

| Message | Verdict |
|---|---|
| `Failed to register with GameMode err=rejected` | Harmless — appears in every run |
| `NtUserChangeDisplaySettings ... returned -2` | Harmless — appears in every run |
| `initialize_display_settings Failed ...` | Harmless — appears in every run |
| `EnableNonClientDpiScaling() failed ... Call not implemented` | Harmless *by itself* — see below |

Studio was never crashing. It **hung** about two seconds into startup, inside Qt
initialization, before the UI or renderer came up. The process then sat there doing
nothing until it was closed or gave up.

## Where the real evidence lives

Vinegar's own console log is nearly useless here. Studio writes a much more detailed log:

```
~/.var/app/org.vinegarhq.Vinegar/data/vinegar/appdata/Roblox/logs/*_last.log
```

**File size alone tells you the outcome.** A session that starts produces hundreds of
KB to multiple MB. A hung session stops dead at **~4.8 KB**, with this as the final line:

```
[FLog::BackendConfigFetcher] Obtained meta data result with NNN ms for try 1
```

A healthy run continues past that into Qt setup — `qt.qpa.input.tablet`,
`setAssetFolder`, `Running instance count at launch 1`, then `MainWindow::MainWindow`.

### Two reliable signatures in the Vinegar log

Comparing every run from that day made the pattern obvious:

- **`EnableNonClientDpiScaling` appears once in good runs, twice in hung runs.**
  The second window is the tell.
- **`D3D11` / `DXGI` lines appear only in good runs.** Their absence means the
  renderer never initialized, i.e. startup never got that far.

```bash
# quick triage across all Vinegar logs
cd ~/.var/app/org.vinegarhq.Vinegar/cache/vinegar/logs
for f in *.log; do
  printf "%-30s %7s bytes  dpi=%s  d3d=%s\n" "$f" "$(stat -c%s "$f")" \
    "$(grep -c EnableNonClientDpiScaling "$f")" "$(grep -cE 'D3D11|DXGI' "$f")"
done
# dpi=1 d3d>0  -> started fine
# dpi=2 d3d=0  -> hung
```

## What was ruled out along the way

Each of these was tested and did **not** fix it — worth knowing so they don't get
retried next time:

- **Orphaned Wine processes.** Two stale Wine sessions were left running, including a
  `RobloxCrashHandler.exe` and a whole `msedgewebview2.exe` tree. Killing all ~20 of
  them changed nothing. (Still worth clearing — see below.)
- **The asset cache.** `rbx-storage.db` had leftover `-wal`/`-shm` files from an
  unclean close. Moving it aside changed nothing.
- **The Wine prefix.** Rebuilding it completely from scratch — fresh Wine, DXVK, and
  WebView2 — reproduced the identical 4.8 KB stall. This was the strongest single
  clue that the prefix wasn't at fault.
- **Wine and X11 themselves.** `wine notepad` opened a normal window, proving GUI,
  X11, and the prefix were all healthy.
- **Cached remote config.** Clearing `ClientSettings/Studio*Settings.json` changed nothing.
- **Network.** DNS and HTTPS to `clientsettingscdn.roblox.com` and `www.roblox.com`
  both returned 200 in under 0.4 s.
- **GPU and memory.** No `amdgpu` errors in the kernel log, no OOM kills, ~10 GB free.
- **Queued crash dumps.** ~556 MB of old minidumps were sitting in `logs/crashes/reports`,
  but they had been there through many successful launches.

The fact that a brand-new prefix failed exactly the same way is what pointed away from
anything local and toward the pinned client itself.

## If Studio misbehaves again

1. **Check Studio's log size first** — `~/.var/app/.../appdata/Roblox/logs/*_last.log`.
   ~4.8 KB means it hung during startup; large means it actually ran.
2. **Clear stale Wine processes** before retrying. Vinegar's `kill` subcommand did not
   work here (1.9.4 is GUI-first and just launched Studio instead), so do it directly:
   ```bash
   ps -eo pid,args | grep '[.]exe' | grep -v grep   # inspect first
   ```
   Kill those PIDs, then confirm none remain. Do **not** use `pkill -f '\.exe'` — the
   pattern matches its own command line and kills the calling shell.
3. **Don't re-pin the Studio version** unless a Vinegar release genuinely can't install
   Studio. A stale pin is what caused this outage.

Housekeeping worth doing sometime: `logs/crashes/reports` holds ~556 MB of minidumps and
`appdata/Roblox/rbx-storage` about 789 MB. Both are safe to delete; Studio regenerates them.
