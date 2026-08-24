# Not Windforge

A side-scrolling, block-building **steampunk airship** sandbox: build and fly
fully-functional ships out of blocks, mine and craft a destructible sky world,
and fight physics-driven battles among sky whales and deep krakens. Everything
you see can be built or destroyed.

**▶ Play it in your browser:** https://rmuno.github.io/not-windforge/

> This is a hobby **reconstruction** — a from-scratch rebuild of the ideas behind
> *Windforge* (by Snowed In Studios), written to learn and to improve on them. It
> is not affiliated with or endorsed by the original's creators. All names, story,
> and code here are original; the original's names are referenced only for context.

## What's in it

- **Block-built ships** with emergent flight — lift from gasbags/blubber, thrust
  from engines + propellers, a power grid with brownouts, and hulls you can cut in
  half (severing keeps the core).
- **Physics combat** — momentum ramming, collision crush, 360° aiming, a grapple.
- **A destructible sky** — chunked procedural islands across three airspace bands,
  wind circulation, meteors up top, and a lethal molten **lava core** at the floor.
- **Mine · build · craft** — dig terrain, place blocks, harvest whale/kraken
  carcasses, craft goods; an RPG layer (four stats, perks, trainers, money).
- **Creatures** — tameable/rideable sky whales, small critters, and aggressive
  deep **krakens** (mouth grab + shell-tip ram) haunting the ember fog.
- **Carcass-as-airship** — tether helium balloons to a corpse to fly it.

## Play locally

1. Install **Godot 4.6-stable** (Forward+ desktop build).
2. Open `project.godot` in the editor and press **F5** (main scene: the 8× world).
3. Controls (see the in-game **F1** help for the full list): **WASD** walk / fly at
   the helm · **mouse** aim · **LMB** shoot · **RMB** grapple · **F** interact ·
   **Q/C** build/remove · **Z** mine · **Tab** map · **F5** save.

## Multiplayer

The browser build is **single-player**. The game has a server-authoritative
multiplayer foundation (ENet) for desktop, but browsers can't host a server, so
online multiplayer on the web would need a dedicated server + a WebSocket/WebRTC
transport — not part of the hosted build.

## License

Source-available, **all rights reserved** — see [LICENSE](LICENSE). You're welcome
to read the code and play the build; please ask before reusing or redistributing it.
