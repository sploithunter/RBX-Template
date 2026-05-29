#!/usr/bin/env bash
#
# release.sh — publish the place to Roblox via Open Cloud. No GUI, no cookie.
#
# Secrets/IDs are read from the environment and NEVER hardcoded:
#   ROBLOX_OPEN_CLOUD_KEY  Open Cloud API key with place-publish scope
#                          (create at https://create.roblox.com/credentials)
#   ROBLOX_UNIVERSE_ID     target universe id
#   ROBLOX_PLACE_ID        target place id (the asset id to publish to)
#
# Usage:
#   mise run release                 # publish
#   DRY_RUN=1 mise run release        # validate + print the command, do NOT publish
#
# The script refuses (non-zero) if any required variable is unset, so it can
# never publish with missing/blank credentials.

set -euo pipefail

: "${ROBLOX_OPEN_CLOUD_KEY:?refusing to publish: set ROBLOX_OPEN_CLOUD_KEY (Open Cloud API key)}"
: "${ROBLOX_UNIVERSE_ID:?refusing to publish: set ROBLOX_UNIVERSE_ID}"
: "${ROBLOX_PLACE_ID:?refusing to publish: set ROBLOX_PLACE_ID}"

echo "Release target: universe ${ROBLOX_UNIVERSE_ID}, place ${ROBLOX_PLACE_ID} (Open Cloud)"

if [ -n "${DRY_RUN:-}" ]; then
    echo "[dry-run] would run:"
    echo "  rojo upload --api_key *** --universe_id ${ROBLOX_UNIVERSE_ID} --asset_id ${ROBLOX_PLACE_ID}"
    echo "[dry-run] no upload performed."
    exit 0
fi

exec mise exec -- rojo upload \
    --api_key "${ROBLOX_OPEN_CLOUD_KEY}" \
    --universe_id "${ROBLOX_UNIVERSE_ID}" \
    --asset_id "${ROBLOX_PLACE_ID}"
