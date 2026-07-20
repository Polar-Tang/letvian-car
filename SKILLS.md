# Skills

Hard-won, non-obvious lessons about the tools this project is built on. Each entry
exists because something broke, the cause was not visible from the surface, and the
fix only made sense after understanding the underlying machinery.

---

## Nevermore: writing a service

A "service" in Nevermore is any value you register with a `ServiceBag` that
follows a duck-typed shape. The bag holds it, wires it, and hands it back when
asked. There is no inheritance to satisfy and no base class to extend — only an
interface to match.

### 1. The three legal service shapes

`serviceBag:GetService(x)` accepts any of:

- **A plain module table** — `local M = {}; M.ServiceName = "Foo"; function M:Init(bag) ... end; return M`.
  The bag wraps it in a proxy (see §3) and runs `:Init`/`:Start` on the proxy.
- **A pre-built instance** — e.g. `Cooldown.lua` returns `Binder.new("Cooldown", Cooldown)`
  at module level. The bag stores the instance as-is, no proxy, no extra `:Init`
  (the instance already implements the shape).
- **A ModuleScript Instance** — the bag `require`s it, then treats the result by
  the above rules.

You do **not** pass `Class.new(args)` to `GetService` as a way to "fix" a missing
constructor. If you need constructor-time arguments, build the instance up front
and register it with `serviceBag:AddService(instance)`. Most services don't need
this; their `:Init(bag)` can pull everything they need from the bag.

### 2. The minimum service interface

```lua
local Service = {}
Service.ServiceName = "Service"           -- required, unique within the bag

function Service:Init(serviceBag)         -- required
    self._serviceBag = serviceBag
    -- wiring only: store references, build internal tables, allocate maids
end

function Service:Start()                  -- optional
    -- engage with the engine: RenderStepped, RemoteEvents, push initial state
end

function Service:Destroy()                -- optional, recommended
    self._maid:DoCleaning()
end

return Service
```

`:Init` and `:Start` must not yield. The bag actively checks `coroutine.status`
and hard-errors if they do.

### 3. What `serviceBag:GetService` actually returns

For a plain-table service, the bag does:

```lua
local service = setmetatable({}, { __index = serviceType })
service:Init(serviceBag)
```

This is **not a copy**. It is a fresh empty table whose metatable routes missing
reads through `__index` to your original module table. Reads of methods and
static fields fall through. Writes — including `self._foo = bar` inside `:Init` —
land on the proxy, never on your module. The original module table stays
read-only.

Consequences worth internalizing:

- `self` inside `:Init`/`:Start` is the proxy, not your module table.
- Every per-instance field you set in `:Init` lives on the proxy.
- The bag caches the proxy: every call to `GetService(X)` on the same bag
  returns the same proxy. Services are singletons within a bag.
- Different bags do not share proxies. (We have one ServiceBag per side
  client / server, so in practice this only matters for tests.)

### 4. The two-phase lifecycle: `Init` is wiring, `Start` is engagement

This is the part that bites hardest. `serviceBag:Init()` walks every registered
service and calls `:Init` on each, in dependency order. Then `serviceBag:Start()`
walks them again and calls `:Start`. The split exists so that during `:Init`,
every service can safely depend on every other service's *existence* without
worrying about ordering of *behavior*.

| Phase | What it's for | What is NOT allowed |
|---|---|---|
| `:Init` | Resolve dependencies (`bag:GetService(X)` to register X, store the reference), build internal tables, declare ValueObjects, allocate maids. | Calling methods on other services that depend on their `:Start` having run. Subscribing to anything that fires synchronously. RunService connections. RemoteEvent listeners. Reading `workspace.CurrentCamera`. Anything that touches the world. |
| `:Start` | Bind to `RenderStepped`/`Heartbeat`, connect RemoteEvents, push initial effects, kick off observables that should propagate. | Yielding. |

Rule of thumb when writing `:Init`:

- "Does this line touch the world?" → move it to `:Start`.
- "Does this line trigger code that touches the world?" (subscriptions, signals,
  callbacks that fire synchronously) → move it to `:Start`.
- "Am I just storing references and building my own tables?" → fine in `:Init`.

### 5. Why `GetService` during `:Init` can silently break things

`serviceBag:GetService(X)` during the *init phase* eagerly runs `X:Init` but
does **not** run `X:Start`. The returned proxy is a half-built service: tables
exist, but anything `:Start` was going to wire up — RunService bindings, event
hooks, default state — hasn't happened yet.

Calling `X`'s methods on that half-built proxy fails silently: pushes to a
stack that nothing samples, signals to handlers that aren't connected, reads of
state that hasn't been initialized.

`serviceBag:GetService(X)` during the *start phase* is different: the bag
ensures `X` is both initialized **and** started before handing back the proxy
(`_ensureStarted` is the start-phase analogue of `_ensureInitialization`). So
the natural place to grab a service whose behavior you intend to use
immediately is `:Start`.

#### Concrete trap: `ValueObject:Observe():Subscribe(fn)`

`Subscribe` fires `fn` synchronously with the current value. If you write this
in `:Init`:

```lua
self._isFirstPerson = ValueObject.new(false, "boolean")
local CameraService = serviceBag:GetService(CameraStackService)
self._isFirstPerson:Observe():Subscribe(function(value)
    if not value then
        ThirdPerson.new(CameraService)  -- runs synchronously, right now, inside Init
    end
end)
```

…then `ThirdPerson.new(CameraService)` runs inside `:Init` against a
`CameraStackService` whose `:Start` hasn't been called. Effects get pushed onto
a render loop that isn't running yet. By the time `serviceBag:Start()`
eventually wires it up, your handler is already constructed against a stale
snapshot. Symptoms are silent: no errors, just nothing renders.

Fix: move both the `GetService` call and the `Subscribe` into `:Start`. In
`:Init`, only allocate the `ValueObject` and store `self._serviceBag`.

### 6. Bootstrap shape

`ServiceRoot.server.luau` and `ServiceRoot.client.luau` follow the same
sequence:

```lua
local serviceBag = ServiceBag.new()
serviceBag:GetService(...)                -- register everything you need
serviceBag:GetService(BinderProvider.new("Binders", function(self, ...) ... end))
serviceBag:Init()                          -- run all :Init
serviceBag:Start()                         -- run all :Start
_G.ServiceBag = serviceBag
_G.BinderProvider = serviceBag:GetService(BinderProvider)
```

After `:Start` returns, the bag is in a "fully live" state. Any further
`GetService` calls (e.g. from code outside the bootstrap) ensure the target is
init'd-and-started before returning.

### 7. Services that *return* a Binder

Some Quenty modules — `Cooldown`, `Ragdoll`, etc. — return `Binder.new(tagName, Class)`
at module level. The exported value is the binder instance, not the class. So
`serviceBag:GetService(require(Cooldown))` returns the same binder you'd get
from `BinderProvider:Get("Cooldown")`. The binder itself implements the service
shape (`Init`, `Start`, `Destroy`), which is why the bag accepts it directly.

The class behind the binder (`Cooldown` the prototype) is internal — you only
ever touch instances created via the binder when objects acquire the `Cooldown`
tag.

---

## Roblox Studio MCP

Claude Code can read and write the live game directly through a Studio plugin
that exposes an MCP server. Every tool call goes over HTTP to the plugin — no
file sync, no Rojo round-trip.

### Setup (one-time per machine)

1. **Plugin files** — copy both `.rbxmx` files into the Studio user-plugins
   folder:
   ```
   ~/.var/app/org.vinegarhq.Vinegar/data/vinegar/prefixes/studio/drive_c/users/nautilus/AppData/Local/Roblox/Plugins/
   ```
   `MCPPlugin.rbxmx` is the MCP bridge; `MCPInspectorPlugin.rbxmx` is optional
   debug tooling.

2. **MCP server** — configured in `~/.claude.json` as an HTTP server:
   ```json
   "robloxstudio": { "type": "http", "url": "http://localhost:58741/mcp" }
   ```
   If it is ever lost, re-add it with:
   ```
   ~/.local/bin/claude mcp add --transport http robloxstudio http://localhost:58741/mcp
   ```

3. **Verify** — open a browser and hit `http://localhost:58741/status`. You
   should see `"pluginConnected":true` and `"mcpServerActive":true`. If either
   is false, Studio is not running or the plugin is not loaded.

### Session startup checklist

Every new Claude Code session, before calling any `mcp__robloxstudio__*` tool:

1. Open Roblox Studio via Vinegar with the game file.
2. Wait for the Plugins tab to show the MCP plugin as active.
3. Confirm `http://localhost:58741/status` returns `pluginConnected:true`.
4. Restart Claude Code so it picks up the HTTP MCP server (see below).

The plugin only runs while Studio is open. If Studio crashes or is closed,
all tool calls will time out until Studio is restarted.

### Restarting Claude Code

Claude Code has no `/restart` command. To reload MCP servers after a config
change, **exit the current session and start a new one**:

- In the terminal running Claude Code: press `Ctrl+C` or type `/exit`, then
  run `~/.local/bin/claude` again from the project directory.
- In the TUI: press `Escape` then `q`, or use the quit keybinding.

After restarting, `~/.local/bin/claude mcp list` should show
`robloxstudio: http://localhost:58741/mcp - ✓ Connected`.

### Tool calls time out but the plugin panel says "Connected"

**Failure mode:** every `mcp__robloxstudio__*` call returns
`Studio plugin connection timeout … Make sure the Roblox Studio plugin is
running and activated`, yet the standalone MCP Server app panel is all green
("Connected / HTTP server OK / MCP bridge OK") and the plugin looks healthy.
The plugin is fine — it is connected to a **different MCP server than the one
this Claude Code session is bound to**. The timeout comes *from* the server
Claude reached, reporting that *it* can't see a plugin.

**Root cause:** MCP servers are configured **per project** under
`projects.<project-path>.mcpServers` in `~/.claude.json`, and the two transport
types resolve to different processes/ports:

- `{"type":"http","url":"http://localhost:58741/mcp"}` — Claude connects to the
  **already-running** standalone MCP Server app (the panel, on 58741). The
  Studio plugin also connects to that same app. Both meet on 58741. ✓
- `{"type":"stdio","command":"npx","args":["-y","robloxstudio-mcp@latest"]}` —
  Claude **spawns its own** `robloxstudio-mcp` process on a *different* default
  port. The plugin is still on 58741, so the two legs never meet → every call
  times out. Reconnecting `/mcp` in-session just respawns the same lonely stdio
  server (often on a fresh port), which does not help.

A project scaffolded from a stdio template lands on the wrong transport even
though another project on the same machine (e.g. `gun_shit`) works — they have
independent `mcpServers` blocks.

**Diagnose** which transport each project uses:

```bash
python3 -c "import json;d=json.load(open('$HOME/.claude.json'));[print(p, (c.get('mcpServers') or {}).get('robloxstudio')) for p,c in d['projects'].items() if isinstance(c,dict) and 'robloxstudio' in (c.get('mcpServers') or {})]"
```

The timing-out project prints `stdio`; a working one prints `http` on 58741.

**Fix:** edit `~/.claude.json` →
`projects.<project-path>.mcpServers.robloxstudio` to the http form so it points
at the running server, then **restart Claude Code** (config is read at startup;
an in-session reconnect will not reliably re-bind a live session):

```json
"robloxstudio": { "type": "http", "url": "http://localhost:58741/mcp" }
```

Back up the file first — it holds all project state. After the restart the very
first `get_selection` returns instead of timing out.

### Key tools

| Tool | What it does |
|---|---|
| `get_project_structure` | Full game hierarchy tree. Use `maxDepth` to go deeper. |
| `get_script_source` | Read a script's full source by instance path. |
| `set_script_source` | Overwrite a script's source in the live session. |
| `edit_script_lines` | Surgical line-range edits — prefer this over full rewrites. |
| `grep_scripts` | Regex search across all scripts in the game. |
| `execute_luau` | Run arbitrary Luau in Studio (edit or playtest context). |
| `get_instance_properties` | Read every property of any instance. |
| `set_property` | Change a single property on an instance. |
| `get_output_log` | Fetch the Studio output log (prints, errors, warnings). |
| `start_playtest` / `stop_playtest` | Launch or end a playtest session. |
| `capture_screenshot` | Screenshot the Studio viewport (requires EditableImage). |

### Addressing instances

Most tools take a `path` argument — a dot-separated hierarchy starting from
a top-level service:

```
game.Workspace.Map.SpawnPoint
game.ReplicatedStorage.RemoteEvents.Equipment
game.Players.LocalPlayer.Character.HumanoidRootPart
```

`get_project_structure` returns the tree so you can find exact paths.
`get_instance_children` lets you inspect one node at a time for deep trees.

### Writing scripts via MCP vs. Rojo

Rojo is source of truth for anything in `src/`. Edits made via `set_script_source`
or `edit_script_lines` live only in the Studio session — they are overwritten
the next time Rojo syncs. Use MCP tools for:

- Reading live game state (properties, output logs, hierarchy).
- Quick experiments and debugging in the running session.
- Executing Luau snippets to inspect runtime values.

Use the normal file tools (`Edit`, `Write`) for permanent code changes, and
let Rojo push them into Studio.

Shirts, Pants, Accessories, Faces, UGC Items
