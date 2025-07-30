-- Admin Configuration
-- Define who has admin privileges in the game
-- This file should be SERVER-SIDE ONLY to prevent client injection

return {
    -- Admin User IDs - only these users can use admin functions
    authorizedUsers = {
        -- Add your Roblox User IDs here
        -- You can find your User ID by going to your profile URL
        -- Example: https://www.roblox.com/users/12345/profile -> User ID is 12345
        
        -- TO SET UP ADMIN ACCESS:
        -- 1. Go to https://www.roblox.com/users/12345/profile (replace 12345 with your user ID)
        -- 2. Copy the number from your profile URL 
        -- 3. Add it to this list (uncomment and replace the example)
        
        3200870803,  -- jason (coloradoplays) - Primary admin
        -- 987654321,  -- Add more admin User IDs here
    },
    
    -- Admin permissions - what admins can do
    permissions = {
        setCurrency = true,          -- Can set arbitrary currency amounts
        adjustCurrency = true,       -- Can add/remove currency amounts  
        giveItems = true,            -- Can give items to players
        resetData = true,            -- Can reset player data
        manageEffects = true,        -- Can start/stop effects
        viewDebugInfo = true,        -- Can view debug information
        testRateLimit = true,        -- Can test rate limiting
    },
    
    -- Security settings
    security = {
        logAllAdminActions = true,           -- Log all admin actions for auditing
        requireStudioForSensitiveOps = true, -- Require Studio for dangerous operations
        blockClientRequests = false,        -- Block all client-originated admin requests (use true for maximum security)
    }
}