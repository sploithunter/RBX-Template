# 🎮 RBX-Template

A production-ready, configuration-driven Roblox game template built with modern development practices. This template provides a robust foundation for building scalable Roblox games with advanced features like persistent player effects, economy systems, and defensive programming patterns.

## ✨ Features

### 🏗️ **Core Architecture**
- **Configuration as Code**: All game logic driven by Lua configuration files
- **Dependency Injection**: ModuleLoader system for clean service management
- **Defensive Programming**: Comprehensive error handling with no silent failures
- **Server-Authoritative**: All critical logic runs on the server for security

### 🔄 **Player Effects System**
- **Folder-Based Replication**: Uses native Roblox folders for real-time client updates
- **Perfect Persistence**: Effects survive server restarts with accurate time tracking
- **Aggregate Stats**: Single source of truth for calculated player bonuses
- **Extensible Configuration**: Add new effects without code changes

### 💰 **Economy System**
- **Multi-Currency Support**: Coins, gems, crystals with transaction logging
- **Rate Limiting**: Advanced protection against exploits and spam
- **Item System**: Configurable shops with effects and consumables
- **ProfileStore Integration**: Robust data persistence with auto-saves

### 🛡️ **Security & Reliability**
- **Anti-Exploit Measures**: Rate limiting, server validation, burst protection
- **Comprehensive Logging**: Structured logging with different severity levels
- **Error Recovery**: Graceful failure handling with user feedback
- **Data Integrity**: Transaction validation and rollback capabilities

### 🎯 **Developer Experience**
- **Hot Reloading**: Rojo integration for instant code updates
- **Type Safety**: Structured data validation and error reporting
- **Debug Tools**: Comprehensive test GUIs and logging systems
- **Extensible Design**: Easy to add new features and game modes

## 🚀 Quick Start

### Prerequisites
- [Rojo CLI](https://rojo.space/) for file syncing
- [mise](https://mise.jdx.dev/) for dependency management (recommended)
- Roblox Studio

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/sploithunter/RBX-Template.git
   cd RBX-Template
   ```

2. **Start Rojo server:**
   ```bash
   rojo serve --port 34872
   ```

3. **In Roblox Studio:**
   - Install the [Rojo plugin](https://rojo.space/docs/v7/getting-started/installation/)
   - Connect to `localhost:34872`
   - Start testing!

## 📁 Project Structure

```
├── src/
│   ├── Client/           # Client-side code
│   │   ├── UI/          # User interface components
│   │   └── init.client.lua
│   ├── Server/          # Server-side services
│   │   ├── Services/    # Core game services
│   │   └── init.server.lua
│   └── Shared/          # Shared utilities
│       └── Utils/       # Common utilities
├── configs/             # Configuration files
│   ├── items.lua        # Item definitions
│   ├── ratelimits.lua   # Effects and rate limits
│   └── game.lua         # Game settings
└── default.project.json # Rojo configuration
```

## 🎮 Core Systems

### Player Effects System

The effects system uses a folder-based architecture for reliable real-time updates:

```lua
-- Apply a speed boost effect
PlayerEffectsService:ApplyEffect(player, "speed_boost", 300) -- 5 minutes

-- Effects appear in Player/TimedBoosts/speed_boost/
-- Aggregated stats in Player/Aggregates/speedMultiplier
```

**Key Features:**
- ✅ Real-time client updates via native replication
- ✅ Persistent across server restarts
- ✅ Configurable stacking rules (extend, reset, or stack)
- ✅ Automatic stat aggregation

### Configuration-Driven Development

Add new items and effects without touching code:

```lua
-- configs/items.lua
speed_potion = {
    displayName = "⚡ Speed Potion",
    price = {currency = "gems", amount = 5},
    effects = {"speed_boost"},
    description = "Increases movement speed by 50% for 5 minutes"
}

-- configs/ratelimits.lua
speed_boost = {
    actions = {"CollectResource", "DealDamage"},
    multiplier = 1.5,
    duration = 300,
    stacking = "extend_duration",
    statModifiers = {
        speedMultiplier = 0.5,  -- +50% speed
        luckBoost = 0.1         -- +10% luck
    }
}
```

### Economy & Data Persistence

Built on ProfileStore for enterprise-grade data management:

```lua
-- Multi-currency transactions
EconomyService:PurchaseItem(player, "speed_potion")

-- Automatic data persistence
-- Player data survives server crashes and restarts
```

## 🛠️ Development

### Adding New Effects

1. **Define the effect in `configs/ratelimits.lua`:**
   ```lua
   my_new_effect = {
       actions = {"PurchaseItem"},
       multiplier = 2.0,
       duration = 600,
       statModifiers = {
           luckBoost = 0.25
       }
   }
   ```

2. **Create an item that applies it in `configs/items.lua`:**
   ```lua
   luck_potion = {
       displayName = "🍀 Luck Potion",
       price = {currency = "coins", amount = 100},
       effects = {"my_new_effect"}
   }
   ```

3. **That's it!** The system automatically handles:
   - Effect application and removal
   - Client GUI updates
   - Data persistence
   - Stat aggregation

### Testing & Debugging

The template includes comprehensive testing tools:

- **Economy Test GUI**: Test purchases and transactions
- **Effects Status GUI**: Monitor active effects in real-time
- **Debug Logging**: Structured logging with multiple severity levels
- **Rate Limit Testing**: Verify anti-exploit measures

## 🏆 Production Ready

This template follows enterprise development practices:

- **🛡️ Security First**: Server-authoritative with anti-exploit measures
- **📊 Observability**: Comprehensive logging and error tracking
- **⚡ Performance**: Optimized for low latency and high throughput
- **🔧 Maintainable**: Clean architecture with separation of concerns
- **📈 Scalable**: Designed to handle thousands of concurrent players

## 📝 License

MIT License - see [LICENSE](LICENSE) for details.

## 🤝 Contributing

This template is designed to be a solid foundation for Roblox games. Feel free to:

- Fork and customize for your game
- Submit issues for bugs or feature requests
- Share improvements and optimizations

## 🎯 Game Types Supported

This template works great for:

- **Simulator Games**: Resource collection with rate limiting
- **RPG Games**: Player progression with persistent effects
- **Tycoon Games**: Economy systems with complex transactions
- **Combat Games**: Buff/debuff systems with stat modifiers
- **Social Games**: Trading systems with secure transactions

---

**Built with ❤️ for the Roblox development community**

*Ready to build the next great Roblox game? This template gives you everything you need to start strong and scale fast!* 