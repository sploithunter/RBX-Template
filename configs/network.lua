-- Network Bridge Configuration
-- Single source of truth for all client-server communication
return {
    bridges = {
        Economy = {
            description = "Economy system for purchases, sales, and shop operations",
            packets = {
                PurchaseItem = {
                    rateLimit = 30,
                    direction = "client_to_server",
                    validation = {
                        itemId = "string",
                        cost = "number",
                        currency = "string"
                    },
                    handler = "EconomyService.PurchaseItem"
                },
                
                SellItem = {
                    rateLimit = 60,
                    direction = "client_to_server",
                    validation = {
                        itemId = "string",
                        quantity = "number"
                    },
                    handler = "EconomyService.SellItem"
                },
                
                GetShopItems = {
                    rateLimit = 10,
                    direction = "client_to_server",
                    validation = {},
                    handler = "EconomyService.GetShopItems"
                },
                
                GetPlayerDebugInfo = {
                    rateLimit = 5,
                    direction = "client_to_server",
                    validation = {},
                    handler = "EconomyService.GetPlayerDebugInfo"
                },
                
                GiveTestItem = {
                    rateLimit = 5,
                    direction = "client_to_server",
                    validation = {},
                    handler = "EconomyService.GiveTestItem"
                },
                
                UseItem = {
                    rateLimit = 60,
                    direction = "client_to_server",
                    validation = {
                        itemId = "string"
                    },
                    handler = "EconomyService.UseItem"
                },
                
                GetActiveEffects = {
                    rateLimit = 10,
                    direction = "client_to_server",
                    validation = {},
                    handler = "EconomyService.GetActiveEffects"
                },
                
                EconomyError = {
                    rateLimit = 5,
                    direction = "server_to_client",
                    validation = {
                        error = "string",
                        code = "string"
                    },
                    handler = "client.showError"
                },
                
                PlayerDebugInfo = {
                    rateLimit = 5,
                    direction = "server_to_client",
                    validation = {
                        inventory = "table",
                        currencies = "table"
                    },
                    handler = "client.showDebugInfo"
                },
                
                ShopItems = {
                    rateLimit = 5,
                    direction = "server_to_client",
                    validation = {
                        items = "table"
                    },
                    handler = "client.showShopItems"
                },
                
                CurrencyUpdate = {
                    rateLimit = 20,
                    direction = "server_to_client",
                    validation = {
                        currency = "string",
                        amount = "number",
                        change = "number"
                    },
                    handler = "client.updateCurrency"
                },
                
                PurchaseSuccess = {
                    rateLimit = 20,
                    direction = "server_to_client",
                    validation = {
                        itemId = "string",
                        quantity = "number",
                        price = "table"
                    },
                    handler = "client.showPurchaseSuccess"
                },
                
                SellSuccess = {
                    rateLimit = 20,
                    direction = "server_to_client",
                    validation = {
                        itemId = "string",
                        quantity = "number",
                        sellPrice = "table"
                    },
                    handler = "client.showSellSuccess"
                },
                
                ActiveEffects = {
                    rateLimit = 10,
                    direction = "server_to_client",
                    validation = {
                        effects = "table"
                    }
                },
                
                EconomyUpdate = {
                    rateLimit = 20,
                    direction = "server_to_client",
                    validation = {
                        currency = "string",
                        amount = "number",
                        reason = "string"
                    },
                    handler = "client.updateCurrency"
                }
            }
        },

        PlayerData = {
            description = "Player data synchronization",
            packets = {
                DataLoaded = {
                    rateLimit = 5,
                    direction = "server_to_client",
                    validation = {
                        playerData = "table"
                    },
                    handler = "client.loadPlayerData"
                },
                
                DataUpdate = {
                    rateLimit = 10,
                    direction = "server_to_client",
                    validation = {
                        field = "string",
                        value = "any"
                    },
                    handler = "client.updatePlayerData"
                }
            }
        },

        Combat = {
            description = "Combat system for PvP and PvE",
            packets = {
                DealDamage = {
                    rateLimit = 20,
                    direction = "client_to_server",
                    validation = {
                        targetId = "string",
                        damage = "number",
                        weaponId = "string"
                    },
                    handler = "CombatService.DealDamage"
                }
            }
        }
    }
} 