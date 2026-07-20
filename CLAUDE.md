
## Binders (Quenty)

A **Binder** is a class attached to every Roblox `Instance` that carries a given `CollectionService` tag. Instead of writing per-instance `if isCharacter then ...` glue, you tag the instance and the binder constructs an OOP wrapper around it. Tag/untag is the lifecycle signal. The canonical implementation is `node_modules/@quenty/binder/src/Shared/Binder.lua` — read that before extending binder behavior.

### Mental model

- `Binder.new(tagName, ConstructorClass)` registers a tag → class mapping. `Binder:Start()` (driven by `BinderProvider` via the service bag) loops `CollectionService:GetTagged(tag)` and listens to `GetInstanceAddedSignal` / `GetInstanceRemovedSignal`.
- When a tag is added to an instance, the binder calls `ConstructorClass.new(inst, ...self._args)` and stores the result in `_instToClass[inst]`. `GetClassAddedSignal` fires.
- When a tag is removed (or the binder is destroyed), `GetClassRemovingSignal` fires, the class is dropped from the maps, and **if the class is a valid Maid task** (i.e. it has `:Destroy()` or is a callable / connection), `MaidTaskUtils.doTask(class)` is called — that's the mechanism that runs `class:Destroy()` automatically on tag removal. Then `GetClassRemovedSignal` fires.
- `binder:Get(inst)` returns the bound class for an instance. `binder:Promise(inst)` returns a Promise resolved when the class exists. `binder:ObserveBrio(inst)` gives a `Brio<class>` stream.

### How this project wires binders

Two binders matter for the combat loop, both registered in `src/client/UI/ServiceRoot.client.luau` and `src/server/ServiceRoot.server.luau` via `BinderProvider`: `"AnimationHandler"` and `"Armed"`.

Access pattern from anywhere:

```lua
local BinderProvider = _G.ServiceBag:GetService(_G.BinderProvider)
local WeaponBinder = BinderProvider:Get(Constants.ARMED_TAG)
local weaponHandler = WeaponBinder:Get(character) -- the bound class for this character
```

### Retrieving a service / binder from inside a service

A ServiceBag **service** is a module table with `ServiceName`, an `Init(self, serviceBag)` and (usually) a `Start(self)`. ServiceRoot registers it with `serviceBag:GetService(Module)` **before** `serviceBag:Init()` / `serviceBag:Start()`; the bag then calls each service's `Init(self, serviceBag)` (handing it the bag) and later `Start(self)`. So a service reaches its dependencies through the **bag it was handed at `Init`** — not through `_G` and not by `require`-ing another service directly.

```lua
function MyService.Init(self, serviceBag)
    -- Stash the bag in an UPVALUE, not a self field (see the servicebag-instance-
    -- vs-module-identity memory): the bag wraps the module in setmetatable({}, …),
    -- so a self field written here won't be visible to a direct require of the module.
    serviceBag = serviceBag
end
```

**Getting another service:** `serviceBag:GetService(OtherServiceModule)` — pass the *module* as the key; the bag returns the started, cached instance. Grab services whose runtime behavior you need in `Start`, not `Init` (an `Init`-time `GetService` returns a half-built proxy whose `Start` hasn't run — see the CameraStackService gotcha below).

**Getting a binder:** binders are reached through the BinderProvider service, and `_G.BinderProvider` is the **registration KEY** for it (it holds the raw provider object ServiceRoot built, whose binders have *not* started). The **started** provider — the one whose binders are live — only comes back from `serviceBag:GetService(_G.BinderProvider)`:

```lua
local provider = serviceBag:GetService(_G.BinderProvider) -- started instance, NOT _G.BinderProvider itself
local flagBinder = provider:Get(GameModeConstants.CTF_FLAG_TAG)
```

Calling `:Get(tag)` straight on `_G.BinderProvider` is the trap (it bit `CaptureTheFlag` — it returned binders that looked empty). Always go through `GetService` first.

**Non-service objects** that the bag never `Init`s directly (the game-mode strategies, for instance) get the bag handed *down* to them — modes receive it as `deps.serviceBag` (set in `GameModeService.Init`, passed through `BaseMode.Init`). Use that, not `_G`.

**Tags are constants, not literals:** the binder tags (`ARMED_TAG`, `ANIMATION_HANDLER_TAG`, `CD_TAG`, `NPC_TAG`) live in `src/myNeverMoreS/abilities/src/Shared/Constanst.luau`. Both ServiceRoots register the `Binders` table and `AddTag` characters using those constants — never re-hardcode the string.


### Common pitfalls

- **Binders are services**: always retrieve via the *started* provider — `serviceBag:GetService(_G.BinderProvider):Get(tag)` (`_G.BinderProvider` is the registration key, not the started provider; `:Get(tag)` straight on it is the trap) — never construct your own. See *Retrieving a service / binder from inside a service* above.
- **Constructor must not yield**: yielding constructors race the tag-removed signal and trigger `[Binder._add] - Failed to load instance, removed while loading!` warnings (Binder.lua:691).
- **Destroy is automatic on untag**: if your bound class has `:Destroy()`, it will be called by `MaidTaskUtils.doTask` when the tag is removed. You don't need a `ClassRemovingSignal` listener for cleanup — just implement `Destroy` correctly.
- **Instantiation is deferred — never snapshot `binder:GetAll()` at one instant**: `Binder:Start` schedules each pre-tagged instance with `task.spawn(self._add, …)` (Binder.lua:216) and binds the rest through `GetInstanceAddedSignal`, so a class can be constructed a frame (or more) *after* your consumer code runs. A one-shot `binder:GetAll()` / `provider:Get(tag):GetAll()` read at the top of some `Start` races that and silently returns `{}` even though the instances exist and bind moments later (this bit `CaptureTheFlag.Start` — flags tagged in the map came back empty). The tell: the bound class's own constructor *is* firing (prints land), but the consumer saw nothing. **Fix = react, don't snapshot**: connect `binder:GetClassAddedSignal()` (catches binds now *and* later, and re-fires on a destroy→re-tag), pair with `GetClassRemovingSignal()` to drop stale entries, and run a `GetAll()` sweep for whatever was already bound — make the per-instance handler idempotent since the sweep and the signal can both reach the same instance (same re-entry lesson as the ServiceRoot NPC sweep). `GetClassAddedSignal` fires from *inside* `_add` **after** the constructor returns (Binder.lua:722, post line-688 `constructor.new`), so anything the constructor built synchronously (a ProximityPrompt, etc.) is guaranteed to exist when your handler runs — there is no "signal fired before the object was ready" race **as long as the constructor doesn't yield** (which it must not anyway). If you genuinely need a single instance and can yield, use `binder:Promise(inst)`; to stream use `binder:ObserveBrio(inst)` / `ObserveAllBrio()`.
- **Session services must never cache `player.Character` in a field (respawn)**: both ServiceRoots and every ServiceBag service survive death; only the character Model is replaced. Anything character-scoped is (re)applied per spawn: the server re-tags + re-applies combat attributes in `onCharacterAdded` (`ServiceRoot.server.luau`, calls `CombatMediator.CharacterAdded(char)`), the client rebuilds the tool `ChildAdded`/`ChildRemoved` wiring in its own `onCharacterAdded` (per-character maid), `shiftLockController` re-acquires the rig on `LocalPlayer.CharacterAdded` (and drops its cached `_weaponClient`), `handHeadCamera` re-resolves its Motor6D rig lazily when `LocalPlayer.Character` changes, and `MainApp` re-injects the new character's WeaponClient into the Roact tree on every "Armed" rebind. New code should either read the character live each use or hook `CharacterAdded` with per-character cleanup — never capture it once at module/service init.



This project is initialized with rojo for a roblox game, this is what we need to do:
Radar system + UI $48
Radar detection: raycast from the police car to detect the vehicle ahead and read its velocity
Overhead speed tag: each detected car gets a floating sign showing its current speed, like in the image  you sent
Alert logic: when a target's speed hits the limit, the readout flips green → red and the alarm sound loops until it drops back under
I'll test everything against a moving dummy so you can see it working before delivery
UI replication
Replace the current bottom bar with a new one matching your reference image (date/time, location, etc). It will be a placeholder, if you expect certain functionallity for the bottom UI you should tell me.
Out of scope
I do not include in this task:

    A car system
    A custom camera system
    Anything i haven't mentioned


## Build & run

```bash
npm install                                            # fetch @quenty/* + @quentystudios/* packages
rojo serve                                             # live-sync src/ into an open Studio session (primary dev loop)
rojo build -o "arcadeShit.rbxlx"                       # build a place file from src/
rojo sourcemap default.project.json -o sourcemap.json  # regenerate the sourcemap
```

Open `arcadeShit.rbxlx` in Roblox Studio, then `rojo serve` to push edits live.
`rojo` is the source of truth — any code that ships lives in `src/`.

**Tooling reality (verify before relying on a command):** `rojo` is the *only*
Luau/Roblox tool on PATH. There is **no** `stylua`, `selene`, `luau-lsp`, or
`luau-analyze` installed; `package.json` has **no `scripts` block** and there is
no `tools/` directory — so `npm run lint/format/build` commands do **not** exist
here. Don't promise a clean lint or type-check you can't actually produce.

- `rojo sourcemap` validates the **project tree and require paths** but does
  **not** parse or type-check Luau — it won't catch a syntax or type error.
- Type-checking and formatting happen inside **Roblox Studio**. If you need
  type/format gating on the CLI, install `stylua` + `luau-lsp`/`luau-analyze`
  yourself (cargo/rokit) — they are not provisioned.

## Layout (`default.project.json` is the map)

The project JSON defines how files land in the DataModel. Key mappings:

| Source | Roblox location | Notes |
|---|---|---|
| `src/server` | `ServerScriptService.Server` | Server code; entry is `init.server.luau` |
| `src/client` | `StarterPlayer.StarterPlayerScripts.Client` | Client code; entry is `init.client.luau` |
| `src/shared` | `ReplicatedStorage.Shared` | Code shared across both sides |
| `src/myNeverMoreS` | `ReplicatedStorage.Nevermore.Custom` | Our own Nevermore-style packages (see *Custom package layout* below) |
| `node_modules/@quenty` | `ReplicatedStorage.Nevermore.Quenty` | Quenty's Nevermore packages |
| `node_modules/@quentystudios` | `ReplicatedStorage.Nevermore.QuentyStudios` | jest-lua etc. |

The `Workspace`, `Lighting`, and `SoundService` property blocks in the project
JSON (Baseplate, ambient lighting, FilteringEnabled) are bootstrap scaffolding —
the real map is built/streamed separately.

### Custom package layout (`myNeverMoreS/<package>/src/{Client,Server,Shared}`)

Each custom package follows the same folder shape Quenty's npm packages use:

```
myNeverMoreS/
  <packageName>/
    src/
      Client | Server | Shared
        <Module>.luau
```

**Only the `Client` / `Server` / `Shared` leaf folder names are load-bearing —
the rest is pure convention.** The loader (`@quenty/loader`) decides a module's
*replication type* by walking the tree and matching folder names against exactly
those three strings:

- `DependencyUtils.iterModules` recurses every child of a package and calls
  `ReplicationTypeUtils.getFolderReplicationType(folderName, ancestorType)`
  (`node_modules/@quenty/loader/src/Dependencies/DependencyUtils.lua:73`).
- That function (`…/Replication/ReplicationTypeUtils.lua:25`) returns `SHARED`
  for a folder literally named `Shared`, `CLIENT` for `Client`, `SERVER` for
  `Server`, and **otherwise just inherits the ancestor's type**. So
  `myNeverMoreS` (→ `Custom`), the `<packageName>` folder, and `src` are
  *transparent passthrough*: they could be renamed and nothing breaks — they
  only forward whatever replication type was set above them (root infers from
  `RunService`: server vs client vs plugin). `node_modules` is the one other
  special name — it's skipped during the walk.
- Names are matched **case-sensitively and exactly** — `client`, `server`,
  `Servers`, etc. would silently fall through to "inherit ancestor", so a
  misspelled folder leaks server code to the client (or vice versa). Spell them
  `Client` / `Server` / `Shared`.

Replication type is **enforced**, not cosmetic: requiring a `Server` module from
the client errors `"%q is only available on the server"` (and the reverse), and
the client-side replicator only copies `Shared` + `Client` modules down to the
client — `Server` modules never replicate. `Shared` is requireable from both
sides. So put a module under the leaf that matches where it's allowed to run;
the `src/` and package-name levels are just there to mirror the Quenty package
convention.

## Bootstrap (`src/server/init.server.luau`)

Server boot sequence:

1. Find `ReplicatedStorage.Nevermore`, locate `LoaderUtils`, and
   `require(loader).bootstrapGame(NeverMorePackages)` to get the `Nevermore`
   require function.
2. `Players.CharacterAutoLoads = false` — **manual respawn is deliberate.** The
   first spawn is issued in `PlayerAdded`; later spawns only happen on an
   explicit `LoadCharacter` (e.g. a Roact respawn button → `RespawnRequest`).
3. Build a `ServiceBag`, stash it on `_G.FistBag` during init, call
   `serviceBag:Init()` then `serviceBag:Start()`, then move it to
   `_G.ServiceBag` (and clear `_G.FistBag`).
4. On `PlayerAdded`, wire `CharacterAdded` → `setCollider`.

[`setCollider.luau`](src/server/setCollider.luau) registers `Players`/`Weapons`
collision groups (non-collidable with each other) and tags every `BasePart` of a
character into the `Players` group. It re-runs on **every** spawn because
CollectionService tags live on the character Model and a respawn starts untagged.

## Nevermore service model — read [SKILLS.md](SKILLS.md)

`SKILLS.md` is the authoritative, hard-won reference. The essentials:

- A "service" is any value matching a duck-typed shape registered with a
  `ServiceBag`. Required: `ServiceName` (unique) and `Init(serviceBag)`.
  Optional: `Start()`, `Destroy()`.
- **Two-phase lifecycle.** `:Init` is *wiring only* — resolve dependencies via
  `serviceBag:GetService(X)`, build tables, allocate maids. `:Start` is
  *engagement* — RunService connections, RemoteEvent listeners, anything that
  touches the world or fires synchronously. Neither may yield (the bag errors).
- `GetService` returns a cached **proxy** (singleton per bag), not your module
  table — `self` inside `:Init`/`:Start` is the proxy.
- Grabbing a service in `:Init` runs only its `:Init` (half-built); grab in
  `:Start` to use behavior immediately. `ValueObject:Observe():Subscribe(fn)`
  fires synchronously — keep it out of `:Init`.

## Map design

`voyague.drawio` (open in diagrams.net) holds the multi-floor floorplan across
4 pages: floors from `-2nd` up to `2nd`, with a spawn location, Bar, Libraries,
cinema, living quarters, a portal room, kitchen, nursery, generator and robot
rooms, connected by ladders and spiral stairs. It's a design reference, not
generated code.

## Verification & testing

There are **no automated tests** wired up and no test runner on PATH. Verify
changes by:

- `rojo sourcemap …` to confirm a new file is actually wired into the tree.
- A **Studio playtest** for runtime behavior — debug with `print()` and inspect
  attributes/events in the Studio explorer.

`@quentystudios/jest-lua` ships in `node_modules/` but is **not** set up as a
runnable suite; don't assume `npm test` works.

## Conventions

- Indentation is tabs (matching existing `.luau` files).
- Optional: Roblox Studio MCP (`mcp__robloxstudio__*`) can read/write the live
  session — see SKILLS.md § "Roblox Studio MCP". Edits via MCP are overwritten
  by the next Rojo sync; use file tools for permanent changes.
