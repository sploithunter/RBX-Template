# Asset Pipeline

This project tracks generated game assets in source control before they become Roblox asset IDs.

## Current State

- Runtime pet config lives in `configs/pets.lua`.
- Pet asset tracking lives in `assets/manifest/pets.json`.
- Local source exports should live in `assets/source/pets/`.
- Processed or temporary exports should live in `assets/exports/pets/`.

Run:

```sh
mise run asset-report
```

Use a stricter check for config/manifest drift:

```sh
mise run asset-check
```

Print Meshy-ready prompts:

```sh
mise run asset-prompts
```

## Preferred Pet Creation Loop

For pets, the strongest workflow discovered so far is reference-image first:

1. Generate or draw a clean, front-facing, white-background style reference image.
2. Use Meshy image-to-3D or multi-image-to-3D in low-poly mode.
3. Texture the generated mesh with the same reference image when the shape is acceptable.
4. Download the `.glb` or `.fbx` source export into `assets/source/pets/`.
5. Upload the model to Roblox, then wire the resulting asset ID into the manifest and `configs/pets.lua`.

This is a developer workflow helper only. Meshy generation, API keys, source exports, and Roblox Open Cloud upload credentials must never be part of runtime game code.

## Manual Meshy To Roblox Loop

1. Pick a pet from `assets/manifest/pets.json` with `status = "needs_source"`.
2. Generate it in Meshy using either the stored prompt or a stored/source reference image.
3. Use Meshy's recommended order for the chosen workflow: generate the mesh, remesh/low-poly it, then texture it.
4. Download the `.glb` or `.fbx` to `~/Downloads`.
5. Copy the source export into `assets/source/pets/` with the manifest name, such as `bear_basic.glb`.
6. Import/upload the model through Roblox Studio.
7. Copy the resulting Roblox model asset ID.
8. Update the pet entry in `assets/manifest/pets.json`.
9. Update the matching `asset_id` in `configs/pets.lua`.
10. Run `mise run asset-check`.
11. Run `mise run build`, then verify in Studio through Rojo.

## Automation Direction

The repo-owned helper should automate the developer workflow, not the live game:

1. Read one entry from `assets/manifest/pets.json`.
2. Use `MESHY_API_KEY` from the local environment.
3. Submit either:
   - text-to-3D for prompt-only exploration, or
   - image-to-3D / multi-image-to-3D for approved style-reference images.
4. Poll or stream task status until the Meshy task succeeds.
5. Download the returned `glb`/`fbx` URLs into `assets/source/pets/`.
6. Mark the manifest entry as `generated` and store Meshy task metadata.
7. Pause for visual approval before Roblox upload.
8. Use Roblox Open Cloud credentials to upload/update the model asset.
9. Update `assets/manifest/pets.json` and `configs/pets.lua` with the Roblox asset ID.
10. Run `mise run asset-check` and `mise run build`.

Meshy's MCP server can be useful for interactive Codex-driven generation, but a checked-in script should remain the canonical portable path for this template. Other developers should only need repo scripts plus local environment variables.

## Runtime Insertion

`configs/pets.lua` is the runtime source of truth for pet and egg model IDs. On server startup, `AssetPreloadService` inserts configured models into `ReplicatedStorage.Assets.Models`, then generates viewport previews under `ReplicatedStorage.Assets.Images`.

Eggs placed in the world should clone the preloaded models from `ReplicatedStorage.Assets.Models.Eggs`. Direct `InsertService` loading is only a fallback if preload did not finish or the preloaded model is missing.

## Status Values

- `needs_source`: Roblox config has an ID, but the source mesh file is not present locally.
- `generated`: Meshy generated the asset, but it has not been uploaded or wired into config.
- `uploaded`: Roblox asset ID is known and config has been updated.
- `verified`: The asset has been checked in Studio.
- `rejected`: The generated asset should not be used.

## Notes

Keep API keys out of the repo. If we later automate Meshy or Roblox Open Cloud uploads, use local environment variables such as `MESHY_API_KEY` and Roblox Open Cloud credentials.
