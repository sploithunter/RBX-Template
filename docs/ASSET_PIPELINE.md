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

## Meshy To Roblox Loop

1. Pick a pet from `assets/manifest/pets.json` with `status = "needs_source"`.
2. Generate it in Meshy using the stored prompt.
3. Use Meshy's recommended order: Generate, Remesh, Texture.
4. Download the `.glb` or `.fbx` to `~/Downloads`.
5. Copy the source export into `assets/source/pets/` with the manifest name, such as `bear_basic.glb`.
6. Import/upload the model through Roblox Studio.
7. Copy the resulting Roblox model asset ID.
8. Update the pet entry in `assets/manifest/pets.json`.
9. Update the matching `asset_id` in `configs/pets.lua`.
10. Run `mise run asset-check`.
11. Run `mise run build`, then verify in Studio through Rojo.

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
