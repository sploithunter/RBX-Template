# Pet System Architecture

## Overview

The Pet System allows players to equip and use pets that follow them around the game world. Pets provide visual appeal and assist in gameplay by attacking breakable objects. The system supports 0-99 pets per player with intelligent formation algorithms and customizable visibility settings.

> Implementation alignment note
>
> The current implementation in this repository is based on a server-driven system adapted from the legacy game (using a PetEquipmentBridge + server PetHandler). Some parts of this document described a future, client-driven architecture (PetVisualizationService, PetMovementController, PetCombatController). Those client services do not exist yet in code. The sections below have been updated to reflect the actual implementation, and the client services remain as future enhancements.

## Core Requirements

1. **Pet Spawning & Management**
   - Pets spawn when equipped (added to player's Equipped/pets folder)
   - Pets despawn when unequipped (removed from folder)
   - Support 0-99 pets per player
   - Replicate pet states across all clients

2. **Pet Following System**
   - Pets follow their owner with smooth movement
   - Maintain formation based on pet count
   - Handle obstacles and terrain navigation
   - Different movement speeds based on pet stats

3. **Pet Combat System**
   - Pets attack targeted breakables
   - Use ability system from pet configuration
   - Damage calculation based on pet power
   - Visual feedback for attacks

4. **Visibility Settings**
   - "Show All Pets" - Display all player pets
   - "Show My Pets" - Display only local player's pets
   - "Show No Pets" - Hide all pets for performance

## Architecture Design

### 1. **Folder Structure & Replication (Implemented)**

```
Player/
├── Equipped/
│   └── pets/
│       ├── slot_1 (StringValue: "pet_uid_123")
│       ├── slot_2 (StringValue: "pet_uid_456")
│       └── ... (up to configured max slots)
```

The Equipped/pets folder is already replicated to all clients via InventoryService. We'll use folder change events to spawn/despawn pets.

Implementation details:
- `InventoryService` owns the authoritative data and toggling logic. When a player equips/unequips a pet, the service updates the player profile and mirrors the state into `Player/Equipped/pets/slot_N` `StringValue`s via `InventoryService:_updateEquippedFolders`.
- Each slot contains the equipped pet UID or an empty string when not used.
- A dedicated server bridge `src/Server/Services/PetEquipmentBridge.server.lua` listens to changes under `Player/Equipped/pets/*` and converts them to the boolean-based format required by the imported PetHandler (`Inventory/pets/<uid>/Equipped` `BoolValue`). It then calls the registered `loadEquipped(player)` function provided by `PetHandler.server.lua` (with a small debounce).
- Pets are spawned in workspace under `workspace/PlayerPets/<Player.Name>`; control boxes are created under `workspace/PlayerPetControl/<Player.Name>`.

### 2. **Component Architecture**

#### **Client Components**

The following client services are a future-facing design and are not implemented yet. Current spawning, movement, and combat initiation are server-driven (see Server Components below).

**PetVisualizationService** (Client Service – planned)
```lua
-- Manages pet model spawning and despawning
-- Listens to Equipped/pets folder changes
-- Handles visibility settings
-- Creates pet models with proper tags

Key Methods:
- InitializeService()
- OnPetEquipped(player, slotName, petUid)
- OnPetUnequipped(player, slotName)
- UpdateVisibilitySettings(setting)
- CreatePetModel(owner, petData) → Model
- DestroyPetModel(petModel)
```

**PetMovementController** (Client Controller – planned)
```lua
-- Manages pet movement and formations
-- Uses RunService.Heartbeat for smooth updates
-- Handles pathfinding and obstacle avoidance

Key Methods:
- UpdatePetMovement(deltaTime)
- CalculateFormation(petCount) → Array<CFrame>
- GetTargetPosition(pet, owner, formationIndex) → Vector3
- SmoothMovePet(pet, targetPos, deltaTime)
```

**PetCombatController** (Client Controller – planned)
```lua
-- Manages pet attacks on breakables
-- Syncs with player targeting system
-- Handles ability cooldowns and effects

Key Methods:
- OnPlayerTargetChanged(target)
- UpdatePetCombat(deltaTime)
- ExecutePetAttack(pet, target, ability)
- PlayAttackAnimation(pet, ability)
```

#### **Server Components (Implemented)**

**InventoryService** (Server Service – implemented)
```lua
-- Receives equip/unequip requests via Signals.TogglePetEquipped (c->s)
-- Validates ownership, toggles profile data, and mirrors equipped state to
-- Player/Equipped/pets/slot_N StringValues.
-- Key methods:
--   _handleTogglePetEquipped(player, data)
--   _togglePetEquipment(player, petUid, pet, playerData)
--   _updateEquippedFolders(player, "pets")
```

**PetEquipmentBridge** (Server Service – implemented)
```lua
-- Bridges our folder-based equipped slots to the legacy boolean-based system.
-- Listens to Player/Equipped/pets/* changes, sets Inventory/pets/<uid>/Equipped (BoolValue),
-- and calls PetHandler.loadEquipped(player) via _G.SetPetLoadEquippedFunction.
```

**PetHandler** (Server Script – implemented)
```lua
-- Spawns/despawns pet models and movement control boxes in workspace based on
-- Inventory/pets/*/Equipped true/false.
-- Loads REAL pet models from ReplicatedStorage.Assets.Models.Pets.<petType>.<variant>.
-- Injects/ensures physics and attaches Follow/FollowBox scripts.
-- Key entry point: loadEquipped(player)
```

**AssetPreloadService** (Server Service – implemented)
```lua
-- On startup, loads all configured pet models (per variant) into
-- ReplicatedStorage.Assets.Models.Pets.<petType>.<variant> and generates images.
-- Also injects useful attributes/values on each variant model (PetType, Variant, Power, BaseHealth).
```
```lua
-- Validates pet equipment changes
-- Handles pet stat calculations
-- Manages pet ability server validation

Key Methods:
- ValidatePetAttack(player, petUid, target, ability)
- CalculateDamage(petData, ability, target) → number
- ApplyDamageToBreakable(target, damage, player)
```

#### **Shared Components**

**PetFormationAlgorithms** (Shared Module)
```lua
-- Provides various formation patterns
-- Scales with pet count dynamically

Formations:
- CircleFormation: Pets form circle around player
- VFormation: Flying V pattern behind player
- GridFormation: Rectangular grid for many pets
- SpiralFormation: Spiral pattern for 20+ pets
- AdaptiveFormation: Switches based on pet count
```

### 3. **Pet Model Structure (Implemented)**

```
PetModel (Model)
├── HumanoidRootPart (Part) - Anchored, CanCollide false
├── Body (Model/Part) - Visual representation
├── Attributes
│   ├── OwnerId (number) - Player.UserId
│   ├── PetUid (string) - Unique identifier
│   ├── PetType (string) - e.g., "bear"
│   ├── Variant (string) - e.g., "golden"
│   └── SlotIndex (number) - Formation position
├── Effects (Folder) - Particle effects, trails
└── Combat (Folder)
    ├── Target (ObjectValue) - Current attack target
    └── LastAttackTime (NumberValue)
```

### 4. **Formation Algorithm System**

```lua
-- Adaptive formation based on pet count
function GetFormationType(petCount)
    if petCount <= 3 then
        return "Line"          -- Simple line behind player
    elseif petCount <= 8 then
        return "Circle"        -- Circle around player
    elseif petCount <= 15 then
        return "DoubleCircle"  -- Two concentric circles
    elseif petCount <= 30 then
        return "Grid"          -- 5x6 or 6x5 grid
    elseif petCount <= 50 then
        return "Spiral"        -- Spiral outward
    else
        return "Swarm"         -- Dynamic swarm behavior
    end
end

-- Example: Circle Formation
function CalculateCircleFormation(petCount, radius)
    local positions = {}
    local angleStep = (2 * math.pi) / petCount
    
    for i = 1, petCount do
        local angle = angleStep * (i - 1)
        local offset = Vector3.new(
            math.cos(angle) * radius,
            0,
            math.sin(angle) * radius
        )
        positions[i] = offset
    end
    
    return positions
end
```

### 5. **Movement System**

```lua
-- Smooth pet following with lerping
function UpdatePetPosition(pet, owner, formationOffset, deltaTime)
    local ownerRoot = owner.Character.HumanoidRootPart
    local targetPos = ownerRoot.Position + 
        (ownerRoot.CFrame * formationOffset)
    
    local petRoot = pet.HumanoidRootPart
    local currentPos = petRoot.Position
    
    -- Calculate movement
    local moveSpeed = pet:GetAttribute("Speed") or 16
    local distance = (targetPos - currentPos).Magnitude
    
    -- Smooth lerping with catch-up speed
    local lerpAlpha = math.min(moveSpeed * deltaTime / distance, 1)
    local newPos = currentPos:Lerp(targetPos, lerpAlpha)
    
    -- Apply movement
    petRoot.CFrame = CFrame.lookAt(newPos, targetPos)
    
    -- Teleport if too far (anti-stuck)
    if distance > 50 then
        petRoot.CFrame = CFrame.new(targetPos)
    end
end
```

### 6. **Combat System Integration (Planned)**

```lua
-- Pet attack coordination
function InitiatePetAttack(pet, target)
    local petData = GetPetData(pet)
    local abilities = petData.abilities
    
    -- Select ability based on cooldowns
    local selectedAbility = SelectBestAbility(abilities, pet)
    if not selectedAbility then return end
    
    -- Check range
    local distance = (pet.Position - target.Position).Magnitude
    if distance > ATTACK_RANGE then
        -- Move closer first
        SetPetTarget(pet, target)
        return
    end
    
    -- Execute attack
    PlayAttackAnimation(pet, selectedAbility)
    
    -- Server validation
    PetService:ValidateAttack(pet, target, selectedAbility)
end
```

### 7. **Visibility Settings System (Planned)**

```lua
-- Settings stored in ReplicatedStorage or player data
local VisibilitySettings = {
    ALL_PETS = "all",      -- Show everyone's pets
    MY_PETS = "mine",      -- Show only local player's pets
    NO_PETS = "none"       -- Hide all pets
}

-- Apply visibility based on setting
function UpdatePetVisibility(setting)
    for _, petModel in CollectionService:GetTagged("Pet") do
        local ownerId = petModel:GetAttribute("OwnerId")
        local isLocalPet = ownerId == LocalPlayer.UserId
        
        if setting == VisibilitySettings.NO_PETS then
            petModel.Parent = nil
        elseif setting == VisibilitySettings.MY_PETS then
            petModel.Parent = isLocalPet and workspace or nil
        else -- ALL_PETS
            petModel.Parent = workspace
        end
    end
end
```

## Implementation Plan

### Phase 1: Core Pet Spawning (Week 1)
1. Create PetVisualizationService
2. Implement equipped folder monitoring (for current player and other players using player replication)
3. Basic pet model creation/destruction
4. Add CollectionService tags for pets

### Phase 2: Movement System (Week 1-2)
1. Create PetMovementController
2. Implement basic following behavior
3. Add formation algorithms (start with Circle)
4. Implement smooth movement and teleport failsafe

### Phase 3: Formation Scaling (Week 2)
1. Implement all formation types
2. Add adaptive formation switching
3. Test with 1-99 pets
4. Optimize performance for high pet counts

### Phase 4: Combat Integration (Week 3)
1. Create PetCombatController
2. Integrate with existing target system
3. Implement ability selection logic
4. Add attack animations and effects

### Phase 5: Settings & Polish (Week 3-4)
1. Add visibility settings to SettingsService
2. Create settings UI integration
3. Performance optimization
4. Visual effects and polish

### Phase 6: Testing & Optimization (Week 4)
1. Stress test with 99 pets
2. Network optimization
3. Mobile performance testing
4. Bug fixes and polish

## Performance Considerations

1. **Model Pooling**: Reuse pet models instead of creating/destroying
2. **LOD System**: Reduce detail for distant pets
3. **Update Throttling**: Update distant pets less frequently
4. **Batch Operations**: Group pet updates to reduce overhead
5. **Streaming**: Only show pets within range (e.g., 200 studs)

## Configuration Integration

The system will use existing configurations:
- `configs/pets.lua` - Pet stats, abilities, and variants
- `configs/ui.lua` - Settings panel integration
- `configs/game.lua` - Performance limits and defaults

## Network Optimization

1. **Minimal Replication**: Only replicate essential data (position updates handled client-side)
2. **Event Batching**: Batch multiple pet actions into single remote calls
3. **Predictive Movement**: Client predicts movement, server validates important actions
4. **Lazy Loading**: Load pet models on demand, not all at once

## Security Considerations

1. **Server Validation**: All damage calculations on server
2. **Rate Limiting**: Limit pet attack frequency
3. **Ownership Verification**: Verify player owns pet before actions
4. **Anti-Exploit**: Validate pet positions and targets

## Future Enhancements

1. **Pet Interactions**: Pets interact with each other
2. **Pet Emotes**: Command pets to do emotes
3. **Formation Presets**: Save custom formations
4. **Pet Abilities**: Special movement abilities (flying, swimming)
5. **Pet Customization**: Colors, accessories, names

---

## End-to-End Equip Flow (Implemented)

1. Client UI: `InventoryPanel` fires `Signals.TogglePetEquipped:FireServer({ bucket = "pets", itemUid = <uid>, itemId = <id> })` when player clicks equip/unequip.
2. Server: `InventoryService:_handleTogglePetEquipped` validates and calls `_togglePetEquipment`, which:
   - Adds/removes the pet UID to/from `playerData.Equipped.pets.slot_N`.
   - Persists in the player’s profile.
3. Server: `InventoryService:_updateEquippedFolders(player, "pets")` mirrors authoritative state to replication folders: `Player/Equipped/pets/slot_N` `StringValue` set to UID or "".
4. Server: `PetEquipmentBridge` detects changes under `Player/Equipped/pets` and builds the current set of equipped UIDs. It writes `Inventory/pets/<uid>/Equipped` (`BoolValue`) for each pet and then calls `loadEquipped(player)` (debounced ~0.1s).
5. Server: `PetHandler.loadEquipped(player)` reads `Inventory/pets` for entries with `Equipped.Value == true`, clears prior instances, and then for each pet:
   - Creates a control box under `workspace.PlayerPetControl/<Player>` and a model container under `workspace.PlayerPets/<Player>`.
   - Locates the model at `ReplicatedStorage.Assets.Models.Pets.<petType>.<variant>` and clones it.
   - Ensures a `PrimaryPart`, welds, and physics movers are set; attaches `PetScripts/Follow` to the pet and `PetScripts/FollowBox` to the box.
   - Sets pet values (`PositionNumber`, `AttackPos`, `Pos`, `PetID`) and parents to workspace.
6. Result: Pets appear around the player and follow their control boxes.

### Data and Values used
- Inventory data: `profile.Data.Inventory.pets.items[uid] = { id = <petId>, petType = <type>, variant = <variant>, ... }`
- Replication folders:
  - `Player/Equipped/pets/slot_N` (`StringValue`) → `uid | ""`
  - `Player/Inventory/pets/<uid>` (Folder) with values like `PetID` (`NumberValue`), `Type` (`StringValue`, expected by PetHandler), optional `variant` (`StringValue`), `Equipped` (`BoolValue` – set by bridge)
- Asset models: `ReplicatedStorage/Assets/Models/Pets/<petType>/<variant>` with attributes and values injected by `AssetPreloadService`.

---

## Known Mismatch and Open Bug: Variant Model Selection

Symptom:
- Some equipped pets spawn using the Basic model even when the inventory item is Golden or Rainbow.

Root cause (current code behavior):
- `PetHandler.server.lua` determines the variant by reading `petFolder:FindFirstChild("Type")` and uses that value when selecting the model folder: `ReplicatedStorage.Assets.Models.Pets.<basePetName>.<TypeValue>`.
- In several parts of the inventory/UI pipeline, the variant is recorded as `variant` (lowercase) on the inventory item and/or written to `Player/Inventory/pets/<uid>/variant` (lowercase). If `Type` is missing, `PetHandler` falls back to "basic" and thus clones the wrong model.

Evidence in code:
- PetHandler expects `Type`: `local petType = petFolder:FindFirstChild("Type")`.
- Inventory/UI frequently use `variant`: e.g. `InventoryPanel:_getPetImageFromAssets(item.petType, item.variant)` and stores/reads `variant`.
- `AssetPreloadService` creates variant models and also writes a `Variant` StringValue on the model asset for reference.

Impact:
- Golden/Rainbow pets may appear as Basic when equipped.

Proposed resolution (future change):
- Normalize on a single field name in player inventory folders. Options:
  1) Write both `Type` and `variant` with the same value during inventory creation/migration.
  2) Update `PetHandler` to prefer `variant` (lowercase) and fall back to `Type` for legacy.
- Add a validation step in `PetEquipmentBridge` (or `InventoryService:_updateEquippedFolders`) to ensure the corresponding `Player/Inventory/pets/<uid>` folder has a non-empty variant field before `loadEquipped` runs.

This document reflects the current behavior and the open issue; the fix will be tracked separately and implemented later.