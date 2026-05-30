--[[
    FollowBox.server.lua — RETIRED (issue #4).

    The legacy control-box chain (each pet AlignPosition-linked to the box in
    front of it) is replaced by PetFollowService, which positions pets directly
    from the pure PetFormation core. The box-chaining code that used to live here
    was removed.

    Kept only as an inert stub because PetHandler still clones it onto each control
    box. The control boxes themselves are now vestigial (harmless); fully removing
    PetHandler's box machinery is a separate cleanup (see docs/wiki/CURRENT_STATUS.md).
]]

return
