# Development Checklist

## Phase 0: Setup ✅ (Completed)
- [x] Install Roblox Studio
- [x] Install aftman: `curl https://mise.jdx.dev/install.sh | sh`
- [x] Run `aftman install` to get tools (rojo, wally, selene, stylua)
- [x] Install VS Code/Cursor with Rojo extension
- [x] Install Rojo plugin in Studio
- [x] Clone repository and run `wally install`

## Phase 1: Project Initialization ✅ (Completed)
- [x] Core folder structure created
- [x] Rojo project configuration (`default.project.json`)
- [x] Wally package management (`wally.toml`)
- [x] Configuration files in `/configs/`
- [x] Git repository initialized

## Phase 2: Core Systems ✅ (Completed)
- [x] Logger utility implemented
- [x] ModuleLoader with dependency injection
- [x] ConfigLoader for configuration management
- [x] NetworkBridge with packet system
- [x] Matter ECS world initialization
- [x] Reflex state management setup

## Phase 3: Services ✅ (Completed)
- [x] DataService with ProfileStore integration
- [x] EconomyService with multi-currency support
- [x] PlayerEffectsService with folder-based effects
- [x] GlobalEffectsService for server-wide effects
- [x] RateLimitService for anti-exploit protection
- [x] ServerClockService for time synchronization

## Phase 4: Game Features ✅ (Partially Completed)
- [x] Configuration-driven item system
- [x] Currency management (coins, gems)
- [x] Player effects with aggregate properties
- [x] Real-time effect replication via folders
- [x] Effect persistence across server restarts
- [x] Rate limiting with effect multipliers
- [ ] **TODO**: Basic UI components and screens
- [ ] **TODO**: Game mode-specific Matter systems
- [ ] **TODO**: Trading system implementation

## Phase 5: UI System (Next Priority)
- [ ] Create base UI component system
- [ ] Implement screen management
- [ ] Create inventory display UI
- [ ] Add shop interface with item previews
- [ ] Implement effect status displays
- [ ] Add currency display components

### UI Implementation Steps:
1. **Base Components** (`src/Client/UI/Components/`)
   - [ ] Button.lua - Reusable button component
   - [ ] Panel.lua - Container component
   - [ ] HealthBar.lua - Progress bar component
   - [ ] CurrencyDisplay.lua - Show coins/gems
   
2. **Screen Components** (`src/Client/UI/Screens/`)
   - [ ] MainMenu.lua - Game main menu
   - [ ] Inventory.lua - Player inventory screen
   - [ ] Shop.lua - Item purchase interface
   - [ ] Settings.lua - Game settings
   
3. **Effects UI** (`src/Client/UI/`)
   - [ ] EffectsStatusGUI.lua - Show active effects
   - [ ] GlobalEffectsGUI.lua - Server-wide effects

## Phase 6: Matter ECS Implementation (Planned)
- [ ] Define game-specific components
- [ ] Implement core game systems
- [ ] Add game mode detection in bootstrap
- [ ] Create system loading based on GameMode config

### ECS Implementation Steps:
1. **Components** (`src/Shared/Matter/Components/`)
   - [ ] Health.lua - Health/damage component
   - [ ] Transform.lua - Position/rotation component
   - [ ] Velocity.lua - Movement component
   - [ ] Inventory.lua - Item storage component
   
2. **Systems** (`src/Shared/Matter/Systems/`)
   - [ ] MovementSystem.lua - Handle entity movement
   - [ ] HealthSystem.lua - Damage and healing
   - [ ] InventorySystem.lua - Item management
   - [ ] CollectionSystem.lua (Simulator mode)

## Phase 7: Game Mode Extensions (Future)
- [ ] **Simulator Mode** (Current focus)
  - [ ] Resource collection systems
  - [ ] Pet/companion mechanics  
  - [ ] Prestige and rebirth systems
  - [ ] Achievement system
  
- [ ] **FPS Mode** (Planned)
  - [ ] Weapon component system
  - [ ] Damage and respawn systems
  - [ ] Team management
  - [ ] Killstreak effects
  
- [ ] **Tower Defense Mode** (Planned)
  - [ ] Wave spawning system
  - [ ] Enemy pathfinding
  - [ ] Tower placement system
  - [ ] Upgrade mechanics

## Phase 8: Advanced Features (Future)
- [ ] **Trading System**
  - [ ] Secure escrow mechanics
  - [ ] Trade validation
  - [ ] Anti-scam protection
  - [ ] Trade history tracking
  
- [ ] **Social Features**
  - [ ] Friend system
  - [ ] Guild/clan mechanics
  - [ ] Chat system with filtering
  - [ ] Leaderboards
  
- [ ] **Monetization**
  - [ ] Game pass integration
  - [ ] Developer product purchases
  - [ ] VIP membership system
  - [ ] Premium currency flow

## Phase 9: Polish & Optimization (Future)
- [ ] **Performance Optimization**
  - [ ] Profile with MicroProfiler
  - [ ] Optimize hot code paths
  - [ ] Memory leak detection
  - [ ] Network bandwidth optimization
  
- [ ] **Visual Polish**
  - [ ] Particle effects system
  - [ ] Sound management
  - [ ] Animation system
  - [ ] Loading screens
  
- [ ] **Quality Assurance**
  - [ ] Comprehensive test suite
  - [ ] Multi-player stress testing
  - [ ] Edge case handling
  - [ ] Error recovery systems

## Phase 10: Launch Preparation (Future)
- [ ] **Analytics Integration**
  - [ ] Player behavior tracking
  - [ ] Economy metrics
  - [ ] Retention analysis
  - [ ] A/B testing framework
  
- [ ] **Production Setup**
  - [ ] Game metadata and thumbnails
  - [ ] Description and tags
  - [ ] Group permissions
  - [ ] Beta testing program
  
- [ ] **Launch Strategy**
  - [ ] Soft launch testing
  - [ ] Community feedback
  - [ ] Marketing preparation
  - [ ] Post-launch monitoring

---

## 🎯 Current Priority Tasks

### Immediate Next Steps (This Week):
1. **Complete UI System Foundation**
   - Create base components (Button, Panel, CurrencyDisplay)
   - Implement screen management system
   - Add inventory and shop interfaces

2. **Test Current Systems**
   - Verify effect persistence across server restarts
   - Test multi-currency transactions
   - Validate rate limiting with effects
   - Check ProfileStore data integrity

3. **Documentation Updates**
   - Complete code examples in SAMPLE_CODE.md
   - Update troubleshooting guide
   - Document UI component usage

### Medium Term (Next 2-3 Weeks):
1. **Matter ECS Implementation**
   - Define components for chosen game mode
   - Implement core systems (movement, health, inventory)
   - Integrate with existing services

2. **Game Mode Specialization**
   - Choose primary game mode (Simulator recommended)
   - Implement mode-specific systems
   - Create progression mechanics

3. **Advanced Features**
   - Trading system framework
   - Social features foundation
   - Analytics preparation

---

## 🧪 Testing Checklist

### Before Each Development Session:
- [ ] Verify Rojo server is running (`rojo serve`)
- [ ] Check Studio connection to Rojo
- [ ] Run basic functionality tests
- [ ] Check for errors in Studio output

### After Major Changes:
- [ ] Test with multiple players in Studio
- [ ] Verify data persistence (leave/rejoin game)
- [ ] Check effect calculations are correct
- [ ] Validate network packet flow
- [ ] Run any existing unit tests

### Before Committing Code:
- [ ] No errors or warnings in Studio output
- [ ] All new features tested in multi-player
- [ ] Performance is acceptable (check frame time)
- [ ] Code follows established patterns
- [ ] Documentation updated if needed

---

## 🚨 Common Gotchas

1. **Configuration Changes**: After modifying configs, restart the game to reload
2. **ProfileStore**: Always test data persistence by leaving/rejoining
3. **Effects**: Verify aggregates recalculate correctly after effect expiry
4. **Network**: Rate limiting can prevent rapid testing - adjust limits in dev
5. **Matter ECS**: Systems run each frame - watch for performance issues

---

## 📋 Definition of Done

A feature is considered complete when:
- [ ] Implemented according to architecture patterns
- [ ] Tested with multiple players
- [ ] Data persists correctly in ProfileStore
- [ ] No errors or warnings in output
- [ ] Performance impact is acceptable
- [ ] Configuration-driven where applicable
- [ ] Documentation updated
- [ ] Code committed to git

This checklist ensures systematic development while maintaining the quality and architecture principles of the game template. 