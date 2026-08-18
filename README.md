# PokeXGames — Asset & Cryptography Documentation

PokeXGames is a heavily customized PokeTibia (an OTClient-based Pokémon MMO). As of **18/08/2026**, the game ships **8,615 asset files** inside its `assets/` folder.

## 1. The Assets

| Extension | Count | Content |
|-----------|------:|---------|
| `.kpng` | 6,265 | Images (UI, sprites, backgrounds) — decrypt to PNG |
| `.kogg` | 929 | Audio (music, sound effects) — decrypt to Ogg/Vorbis |
| `.klua` | 354 | Game scripts — decrypt to LuaJIT bytecode |
| `.klua32` | 354 | 32-bit LuaJIT clones of the `.klua` files |
| `.klui` | 298 | UI stylesheets — decrypt to OTUI text |
| `.kfrag` | 154 | GLSL fragment shaders |
| `.klmod` | 117 | Module configs — decrypt to OTMod text |
| `.kttf` | 67 | Fonts — decrypt to TTF/OTF |
| `.spr` | 41 | Sprite pixel archives (`things0.spr` … `things40.spr`) — 274,256 sprite records |
| `.klpe` | 19 | Per-effect particle configs |
| `.klfont` | 8 | Font configs — decrypt to OTFont text |
| `.klml` | 4 | OTML markup |
| `.krev` | 1 | Build number |
| `.kmd` | 1 | Markdown-like text |
| `.kidx` | 1 | Sprite index (binary) |
| `.kdat` | 1 | Object definitions — the OTClient `.dat` equivalent |
| `.png` | 1 | Single unencrypted stray PNG |
| **Total** | **8,615** | |

There is also a plaintext YAML manifest at `.lam` (in the game root) listing ~8,500 assets with SHA1 hashes (of the encrypted bytes) and timestamps — it is used for version/integrity tracking, not encryption.

## 2. They Are Encrypted

Almost every asset is encrypted. The game marks encrypted files by putting a **`.k` in the extension**: `png` → `.kpng`, `ogg` → `.kogg`, `lua` → `.klua`, and so on. The loader (`pxgme.exe`) checks for `.k` in the filename and only then runs the decryption path; the 41 `.spr` archives are the exception — they use their own separate per-sprite encryption layer.


## 3. What Cryptography Does PxG Use?

**Algorithm:** Salsa20/8 (8 rounds = 4 double-rounds)
**Nonce:** 8 zero bytes. **Counter:** starts at 0.
**Key:** first 32 ASCII chars of `SHA256(basename).hexdigest()` — the basename includes the extension (`"init.klua"`, `"wailord.kogg"`).

Container format (current build):

```
r = len(ciphertext) % 64
ciphertext[0:r]     = plaintext[0:r]     ^ (KS[0:r] ^ KS[L-r:L])
ciphertext[r:L-r]   = plaintext[r:L-r]   ^  KS[r:L-r]
ciphertext[L-r:L]   = plaintext suffix, stored unencrypted
```

To decrypt: `plain = ciphertext ^ KS`, then XOR the first and last `r` bytes with `KS[L-r:L]`. After undoing the shift, the first 8 bytes are a `(uint32 size, uint32 Adler-32)` header; the payload starts at byte 8. Older repacks had stale header fields, so the decryptor strips the 8-byte header unconditionally — on the current build all headers validate again, but stripping first is still the safe order.

The `.spr` sprite archives do **not** use this scheme — they have their own per-sprite layer (next section).

Note: Salsa20/**8** is the reduced-round variant — most crypto libraries only ship Salsa20/20, so a stock `Salsa20` will **not** work. A minimal, tested implementation is included in `salsa208.py`.


## 4. The `.spr` Sprite Archives

Sprites live in 41 files (`things0.spr` … `things40.spr`, in `assets/things/`): **274,256 sprite records** as of 18/08/2026. They use their own encryption — **not** the per-file asset scheme.

**Key:** one global hardcoded 32-byte key, same for every sprite:

```
f87055e183222c97f2539b131e98a4fd4608a75095f80683c8f991ea06094599
```

**Cipher:** Salsa20/8, counter 0. **Nonce** is per-sprite: `(0xDEADBEEF, compressed_size ^ 0xBABACA11)`.

Each `.spr` starts with a 4-byte magic, then repeating records — an 8-byte obfuscated header followed by the encrypted payload:

```
width           = uint16_le(header[0:2]) ^ 0xFACE
height          = uint16_le(header[2:4]) ^ 0xFACE
compressed_size = uint32_le(header[4:8]) ^ 0xBABACA11
```

Decrypt with Salsa20/8, undo the same length-mod-64 keystream shift as the `.k*` assets, then zlib-inflate → raw RGBA pixels (`width × height × 4`).

**Finding a sprite:** the game keeps a flat lookup vector — `vector_index = sprite_id - 1`, each 8-byte entry is `(file_index, header_offset)`. The same vector can be rebuilt offline just by walking the record headers.

**Categories:** there is only one sprite archive. Item / Creature / Effect / Missile are groupings of the object records inside `things.kdat`, not separate files.

Verified 18/08/2026: oldest and newest sprites both decrypt to valid PNGs with this exact recipe.


## 5. `things.kdat` — Object Definitions

The OTClient `.dat` equivalent: every object (item, outfit, effect, missile) with its dimensions, patterns, animation phases, and sprite references. Encrypted with the standard asset scheme (section 3).

Layout of the decrypted file:

```
+0x00   header (12 bytes)
+0x0C   property-length table: (uint16 property_id, uint16 length) pairs,
        66 entries, terminated by (0xFFFF, 0xFFFF)
+0x118  four category counts (uint32): Item, Creature, Effect, Missile
+0x128  object records, grouped by category in that order, to EOF
```

Each object record:

```
property list:  uint16 property_id + payload, until pid == 0xFFFF
                - length from the table; 0xFFFF = variable-length
                  (uint16 actual length, then payload)
                - pid not in table and <= 183 -> flag-only, 0 payload bytes
dimensions:     7 bytes — width, height, layers, patternX, patternY, patternZ, animationPhases
sprites:        layers × patternX × patternY × patternZ × animationPhases entries,
                8 bytes each: uint32 sprite_id + 2 × uint16
```

Two gotchas: the sprite count does **not** include `width × height` (one entry per layer/pattern/frame slot), and the category counts at `0x118` are slightly off — the real boundaries have to be corrected by the parser.

As of 18/08/2026: **86,406 objects**, parsed cleanly to end-of-file. Category enum (from `const.klua`): `Item=0, Creature=1, Effect=2, Missile=3`.


## 6. ObjectBuilder Conversion

The decrypted assets can be rebuilt into the **Tibia 10.56 / ObjectBuilder extended format**: `.dat` (object metadata) + `.spr` (sprite archive) + `.otfi` (auto-detection).

- Categories map to ObjectBuilder as: things → **items** (IDs from 100), creatures → **outfits**, effects → **effects**, missiles → **missiles** (IDs from 1).
- Every sprite reference is tiled onto a `width × height` grid of 32×32 cells, anchored to the **bottom** of the cell. Tiles are stored in Tibia's native order: **bottom-right first, moving left and up** — getting this wrong slices multi-tile outfits into pieces.
- `.spr` pixels are RLE-compressed; colored pixels are stored as `[R, G, B, A]` (a `[G, B, A, R]` bug once caused a blue/pink tint on every outfit).
- Signatures: `.dat` = `0x542143B0`, `.spr` = `0x542143DE`.
- Item IDs are `uint16`, so the item category caps at **65,535**. PxG has more — the excess goes to a separate overflow archive, remapped to IDs 100–2971.
- Per-object limit: `width × height × layers × patterns × frames ≤ 4096` sprite references; oversized objects get their frame count capped.
- PxG reuses the animation field for addons/variants/evolutions, so animated outfits get **similarity-filtered** (SSIM + histogram) to stop them cycling through unrelated sprites.
- Property flags and real animation timings are **not** preserved (no known mapping to Tibia flags) — `.dat` objects are bare, every frame runs at 100 ms.

Latest build (June 2026 — predates the current asset update, so a fresh build will produce higher counts): **83,167 objects / 2,944,549 unique sprites** in the main archive, **2,872 objects / 24,558 sprites** in the overflow archive.

Output format spec:

```
.dat:
  u32 signature 0x542143B0
  u16 max item ID, u16 max outfit ID, u16 max effect ID, u16 max missile ID
  objects (items, then outfits, effects, missiles):
    0xFF                        -- LAST_FLAG, no properties written
    outfits only: u8 group_count, u8 group_type (0)
    u8 width, u8 height
    u8 exact_size               -- only if width > 1 or height > 1
    u8 layers, patternX, patternY, patternZ, frames
    if frames > 1: u8 mode, u8 loop_count, u8 start_frame,
                   u32 min_duration, u32 max_duration  (per frame)
    u32 sprite_index × (width × height × layers × patternX × patternY × patternZ × frames)

.spr:
  u32 signature 0x542143DE
  u32 sprite count
  u32 addresses[count]          -- file offset of each sprite
  per sprite: 3-byte marker 0xFF 0x00 0xFF, u16 data length, RLE pixels
    RLE: alternating u16 transparent_run, u16 colored_run,
         then colored_run × 4 bytes [R, G, B, A]
    transparent = all four channels zero
    always ends with a final colored_run, even if 0

.otfi:
  version: 1056
  sprites-count: <same as .spr count>
  frame-durations: true
  frame-groups: true
  transparency: true
```


## 7. Format Quirks

- **`.kogg`** — after decryption the payload does not start at `OggS`. There's a variable-size Vorbis identification header in front (the game statically links libVorbis). Locate the first real `OggS` page — or rebuild the BOS page from the prefix — or audio players will reject the file.
- **`.klua`** — decrypts to LuaJIT **bytecode** (`.luac`), not readable Lua source. To get readable code out of them you need a LuaJIT decompiler: [luajit-decompiler-v2](https://github.com/marsinator358/luajit-decompiler-v2). Only two of the 354 are plain text and readable directly: `init-repair.klua` and `modules/terminal/commands.klua`.
- **`.klua32`** — 32-bit LuaJIT clones of the `.klua` scripts. Same key scheme, same content. Safe to ignore on 64-bit.
- **`.kidx`** — decrypts fine with the standard scheme, but its purpose is still unknown. Not needed for anything: the category split comes from `things.kdat`, and the sprite lookup vector can be rebuilt from the `.spr` headers alone.
