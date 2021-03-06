-- ======= Copyright (c) 2003-2011, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\GUIInsight_Overhead.lua
--
-- Created by: Jon 'Huze' Hughes (jon@jhuze.com)
--
-- Spectator Overhead: Displays mouse over text and loads healthbars
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

--[[
@ailmanki
Was simpler to replace the whole file,
its only a small change, so we keep spectating a "dead" player
]]
class 'GUIInsight_Overhead' (GUIScript)

local mouseoverBackground
local mouseoverText
local mouseoverTextBack

local kFontName = Fonts.kAgencyFB_Medium
local kFontScale

local showHints, playerFollowAttempts, playerFollowNextAttempt, lastPlayerId

local kPlayerFollowMaxAttempts = 20
local kPlayerFollowCheckInterval = 0.05

function GUIInsight_Overhead:Initialize()
    kFontScale = GUIScale(Vector(1, 0.8, 0))

    mouseoverBackground = GUIManager:CreateGraphicItem()
    mouseoverBackground:SetAnchor(GUIItem.Left, GUIItem.Top)
    mouseoverBackground:SetLayer(kGUILayerPlayerHUD)
    mouseoverBackground:SetColor(Color(1, 1, 1, 0))
    mouseoverBackground:SetIsVisible(false)

    mouseoverText = GUIManager:CreateTextItem()
    mouseoverText:SetFontName(kFontName)
    mouseoverText:SetScale(kFontScale)
    mouseoverText:SetColor(Color(1, 1, 1, 1))
    mouseoverText:SetFontIsBold(true)
    GUIMakeFontScale(mouseoverText)

    mouseoverTextBack = GUIManager:CreateTextItem()
    mouseoverTextBack:SetFontName(kFontName)
    mouseoverTextBack:SetScale(kFontScale)
    mouseoverTextBack:SetColor(Color(0, 0, 0, 0.8))
    mouseoverTextBack:SetFontIsBold(true)
    mouseoverTextBack:SetPosition(GUIScale(Vector(3,3,0)))
    GUIMakeFontScale(mouseoverTextBack)

    mouseoverBackground:AddChild(mouseoverTextBack)
    mouseoverBackground:AddChild(mouseoverText)

    showHints = Client.GetOptionBoolean("showHints", true) == true

    playerFollowAttempts = 0
    playerFollowNextAttempt = 0
    lastPlayerId = Entity.invalidId

    if showHints then
        GetGUIManager():CreateGUIScriptSingle("GUIInsight_Logout")
    end
    --GetGUIManager():CreateGUIScriptSingle("GUIMarqueeSelection")

    -- [@ailmanki] copypasta from function function Commander:OnInitLocalClient()
    self.ghostGuides = { }
    self.reuseGhostGuides = { }
end

function GUIInsight_Overhead:Uninitialize()

    GUI.DestroyItem(mouseoverBackground)

    if self.playerHealthbars then
        GetGUIManager():DestroyGUIScriptSingle("GUIInsight_PlayerHealthbars")
        self.playerHealthbars = nil
    end
    if self.otherHealthbars then
        GetGUIManager():DestroyGUIScriptSingle("GUIInsight_OtherHealthbars")
        self.otherHealthbars = nil
    end
    if showHints then
        GetGUIManager():DestroyGUIScriptSingle("GUIInsight_Logout")
    end
    --GetGUIManager():DestroyGUIScriptSingle("GUIMarqueeSelection")

    -- [@ailmanki] copypasta from function Commander:OnDestroy()
    self:DestroyGhostGuides()
end

local function GetEntityUnderCursor(player)

    local xScalar, yScalar = Client.GetCursorPos()
    local x = xScalar * Client.GetScreenWidth()
    local y = yScalar * Client.GetScreenHeight()
    local pickVec = CreatePickRay(player, x, y)

    local origin = player:GetOrigin()
    local trace = Shared.TraceRay(origin, origin + pickVec*1000, CollisionRep.Select, PhysicsMask.CommanderSelect, EntityFilterOne(self))
    local recastCount = 0
    while trace.entity == nil and trace.fraction < 1 and trace.normal:DotProduct(Vector(0, 1, 0)) < 0 and recastCount < 3 do
        -- We've hit static geometry with the normal pointing down (ceiling). Re-cast from the point of impact.
        local recastFrom = 1000 * trace.fraction + 0.1
        trace = Shared.TraceRay(origin + pickVec*recastFrom, origin + pickVec*1000, CollisionRep.Select, PhysicsMask.CommanderSelect, EntityFilterOne(self))
        recastCount = recastCount + 1
    end

    return trace.entity

end

function GUIInsight_Overhead:Update(deltaTime)

    PROFILE("GUIInsight_Overhead:Update")

    local player = Client.GetLocalPlayer()
    if player == nil then
        return
    end

    -- [@ailmanki] copypasta from function Commander:UpdateGhostGuides(
    self:DestroyGhostGuides(true)

    local entityId = player.followId
    -- Only initialize healthbars after the camera has finished animating
    -- Should help smooth transition to overhead
    if not PlayerUI_IsCameraAnimated() then

        if self.playerHealthbars == nil then
            self.playerHealthbars = GetGUIManager():CreateGUIScriptSingle("GUIInsight_PlayerHealthbars")
        end
        if self.otherHealthbars == nil then
            self.otherHealthbars = GetGUIManager():CreateGUIScriptSingle("GUIInsight_OtherHealthbars")
        end

        -- If we have high ping it will take a while for entities to be relevant to us again, so we retry a few times before we give up and deselect
        if entityId and entityId ~= Entity.invalidId and (playerFollowNextAttempt < Shared.GetTime() or playerFollowNextAttempt == 0) then
            local entity = Shared.GetEntity(entityId)

            -- If we're not in relevancy range, get the position from the mapblips
            if not entity then
                for _, blip in ientitylist(Shared.GetEntitiesWithClassname("MapBlip")) do

                    if blip.ownerEntityId == entityId then

                        local blipOrig = blip:GetOrigin()
                        player:SetWorldScrollPosition(blipOrig.x, blipOrig.z)

                    end
                end
                -- Try to get the player again
                entity = Shared.GetEntity(entityId)
            end

            if entity and entity:isa("Player") and entity:GetIsAlive() then
                local origin = entity:GetOrigin()
                player:SetWorldScrollPosition(origin.x, origin.z)
                playerFollowAttempts = 0
                playerFollowNextAttempt = 0
            elseif not entity then
                if playerFollowAttempts < kPlayerFollowMaxAttempts then
                    playerFollowAttempts = playerFollowAttempts + 1
                    playerFollowNextAttempt = Shared.GetTime() + kPlayerFollowCheckInterval
                end
                -- If the player is dead, or the entity is not a player, deselect
            else
                --[[
                @ailmanki
                if its a player, dont deselect it
                ]]
                if entity and entity:isa("Player") then
                else
                    entityId = Entity.invalidId
                end
            end

            if lastPlayerId ~= entityId then
                Client.SendNetworkMessage("SpectatePlayer", {entityId = entityId}, true)
                player.followId = entityId
                lastPlayerId = entityId
                playerFollowAttempts = 0
                playerFollowNextAttempt = 0
            end
        end

    end

    -- Store entity under cursor
    local entity = GetEntityUnderCursor(player)
    player.entityIdUnderCursor = entity and entity:GetId() or Entity.invalidId

    if entity ~= nil and HasMixin(entity, "Live") and entity:GetIsAlive() then

        local text = ToString(math.ceil(entity:GetHealthScalar() * 100)) .. "%"

        if HasMixin(entity, "Construct") then
            if not entity:GetIsBuilt() then

                local builtStr
                if entity:GetTeamNumber() == kTeam1Index then
                    builtStr = Locale.ResolveString("TECHPOINT_BUILT")
                else
                    builtStr = Locale.ResolveString("GROWN")
                end
                local constructionStr = string.format(" (%d%% %s)", math.ceil(entity:GetBuiltFraction()*100), builtStr)
                text = text .. constructionStr

            end
        end



        local xScalar, yScalar = Client.GetCursorPos()
        local x = xScalar * Client.GetScreenWidth()
        local y = yScalar * Client.GetScreenHeight()
        mouseoverBackground:SetPosition(Vector(x + GUIScale(18), y + GUIScale(18), 0))
        mouseoverBackground:SetIsVisible(true)

        mouseoverText:SetText(text)
        mouseoverTextBack:SetText(text)

        -- [@ailmanki] copypasta from function Commander:UpdateGhostGuides()
        -- visual range for selected units if they are specified.
        -- Draw visual range on structures that specify it (no building effects)
        -- if GetVisualRadius() returns an array of radiuses, draw them all
        local visualRadius = entity.GetVisualRadius and entity:GetVisualRadius()
        if visualRadius ~= nil then
            local teamtype = entity:GetTeamType()
            local entityorigin = Vector(entity:GetOrigin())
            local isShift = (entity:GetTechId() == kTechId.Shift)

            if type(visualRadius) == "table" then
                for i,r in ipairs(visualRadius) do
                    self:AddGhostGuide(entityorigin, r, teamtype)
                    if isShift then
                        self:AddGhostGuide(entityorigin, kEnergizeRange, teamtype)
                    end
                end
            else
                self:AddGhostGuide(entityorigin, visualRadius, teamtype)
                if isShift then
                    self:AddGhostGuide(entityorigin, kEnergizeRange, teamtype)
                end
            end
        end

    else

        mouseoverBackground:SetIsVisible(false)

    end

end

function GUIInsight_Overhead:OnResolutionChanged(oldX, oldY, newX, newY)
    self:Uninitialize()
    self:Initialize()
end

-- [@ailmanki] copypasta from Commander.lua
GUIInsight_Overhead.kMarineCircleDecalName = PrecacheAsset("models/misc/circle/circle.material")
GUIInsight_Overhead.kAlienCircleDecalName = PrecacheAsset("models/misc/circle/circle_alien.material")

-- [@ailmanki] copypasta from function Commander:AddGhostGuide(origin, radius)
function GUIInsight_Overhead:AddGhostGuide(origin, radius, teamtype)

    local guide

    if #self.reuseGhostGuides > 0 then
        guide = self.reuseGhostGuides[#self.reuseGhostGuides]
        table.remove(self.reuseGhostGuides, #self.reuseGhostGuides)
    end

    -- Insert point, circle

    if not guide then
        guide = Client.CreateRenderDecal()
        guide.material = Client.CreateRenderMaterial()
    end

    local materialName = ConditionalValue(teamtype == kAlienTeamType, GUIInsight_Overhead.kAlienCircleDecalName, GUIInsight_Overhead.kMarineCircleDecalName)
    guide.material:SetMaterial(materialName)
    guide:SetMaterial(guide.material)
    local coords = Coords.GetTranslation(origin)
    guide:SetCoords( coords )
    guide:SetExtents(Vector(1,1,1)*radius)

    table.insert(self.ghostGuides, {origin, guide})

end

-- [@ailmanki] copypasta from function Commander:DestroyGhostGuides(reuse)
function GUIInsight_Overhead:DestroyGhostGuides(reuse)

    for index, guide in ipairs(self.ghostGuides) do
        if not reuse then
            Client.DestroyRenderDecal(guide[2])

        else
            guide[2]:SetExtents(Vector(0,0,0))
            table.insert(self.reuseGhostGuides, guide[2])
        end
    end

    if not reuse then

        for index, guide in ipairs(self.reuseGhostGuides) do
            Client.DestroyRenderMaterial(guide.material)
            Client.DestroyRenderDecal(guide)
            guide = nil
        end

        self.reuseGhostGuides = {}

    end

    self.ghostGuides = {}

end