bc.formatting = {}
local f = bc.formatting

function f.formatMessage( ply, text, dead, defaultColor, dontRecolorColon, data )

    local text = table.concat( string.Explode( "\t[\t]+", text, true ), "\t" )

    local tab = {}
    defaultColor = defaultColor or bc.defines.colors.white
    data = data or { ply, text, false, dead }

    local preTab, lastCol = hook.Run( "BC_getPreTab", unpack( data ) )
    if preTab then
        table.Add( preTab, f.formatText( text, lastCol, ply ) )
        tab = preTab
        if data[3] then -- Teamchat
            table.insert( preTab, 1, { controller = true, type = "noPrefix" } )
        end
    else
        if dead then
            table.insert( tab, bc.defines.theme.dead )
            table.insert( tab, "*DEAD* " )
        end

        table.insert( tab, { formatter = true, type = "prefix" } )

        if not ply:IsValid() then
            table.insert( tab, bc.defines.theme.server )
            table.insert( tab, "Server" )
        else
            table.insert( tab, { formatter = true, type = "escape" } ) --escape pop from ply name
            table.insert( tab, ply )
        end
        table.insert( tab, dontRecolorColon and defaultColor or bc.defines.colors.white )
        table.insert( tab, ": " )
        table.insert( tab, defaultColor )

        local messageTab = f.formatText( text, nil, ply )
        table.Add( tab, messageTab )
    end

    return tab
end

function f.formatText( text, defaultColor, ply )
    local tab = {}

    defaultColor = defaultColor or bc.defines.colors.white

    -- Make ulx commands grey
    if text[1] == "!" and text[2] ~= "!" and bc.settings.getValue( "colorCmds" ) then
        local s, e = string.find( text, " ", nil, true )
        if not e then e = #text + 1 end
        if e ~= 2 then
            table.insert( tab, bc.defines.theme.commands )
            table.insert( tab, string.sub( text, 0, e - 1 ) )
            table.insert( tab, defaultColor )
            text = string.sub( text, e, -1 )
        end
    end

    tab = f.formatSpecialWords( text, tab )

    tab = f.formatCustomColor( tab, defaultColor, ply )

    -- format links
    if bc.settings.getValue( "clickableLinks" ) then
        tab = f.formatLinks( tab )
    end

    tab = f.formatEmotes( tab )

    tab = f.formatModifiers( tab, ply )

    return tab
end

function f.formatCustomColor( tab, currentColor, ply )
    local out = {}
    local canUse = bc.settings.isAllowed( ply, "bc_color" )
    for k, v in ipairs( tab ) do
        if type( v ) == "table" and v.defaultColor then
            table.insert( out, currentColor )
        elseif type( v ) == "string" and canUse then
            local ret
            ret, currentColor = f.formatCustomColorSingle( v, currentColor )
            table.Add( out, ret )
        else
            table.insert( out, v )
        end
    end
    return out
end

local function firstMatch( text, ... )
    local out = {}
    local firstPos = 100000
    local firstIdx = -1
    for k, v in pairs{ ... } do
        local data = { string.find( text, v ) }
        if not data[1] then continue end
        if data[1] < firstPos then
            firstPos = data[1]
            out = data
            firstIdx = k
        end
    end
    return firstIdx, table.remove( out, 1 ), table.remove( out, 1 ), out
end

function f.formatCustomColorSingle( text, currentColor )
    local out = {}
    while true do
        local i, s, e, data = firstMatch( text, "%[#(%x%x)(%x%x)(%x%x)%]", "%[#%]", "%[@([^%]]+)%]" )
        if i == -1 then
            break
        end
        local col
        if i == 1 then
            local r = tonumber( data[1], 16 )
            local g = tonumber( data[2], 16 )
            local b = tonumber( data[3], 16 )
            col = Color( r, g, b )
        elseif i == 2 then
            col = bc.defines.colors.white
        else
            local colName = string.lower( data[1] )
            colName = chatHelper.spaceToCamel( colName )
            col = bc.defines.colors[colName]
            if not col then
                table.insert( out, string.sub( text, 1, e ) )
                text = string.sub( text, e + 1 )
                continue
            end
        end
        currentColor = col
        local preText = string.sub( text, 1, s - 1 )
        text = string.sub( text, e + 1 )
        if #preText > 0 then
            table.insert( out, preText )
        end
        table.insert( out, col )
    end
    if #text > 0 then
        table.insert( out, text )
    end
    return out, currentColor
end

function f.formatEmotes( tab )
    local madeChange = true
    local loopCounter = 1
    -- i hate this whole section, surely can be written better
    -- cleaned up a bit, still needs rewriting, cba
    if not bc.images.emoteLookup then
        return tab
    end

    while madeChange do
        madeChange = false
        loopCounter = loopCounter + 1
        if loopCounter > 30 then
            MsgC( bc.defines.colors.red, "[BetterChat] A message with too many images has been prevented from rendering fully to prevent lag" )
            break
        end
        local newTab = {}
        for k, v in pairs( tab ) do
            if type( v ) ~= "string" then
                table.insert( newTab, v )
                continue
            end

            local inpStr = v

            local found = true
            while found do
                found = false
                for l = 1, #bc.images.emoteLookup.list do
                    local str = bc.images.emoteLookup.list[l]

                    local s, e = string.find( inpStr, str, 1, true )
                    if not s then continue end

                    local isShort = str[1] ~= ":" or str[#str] ~= ":"

                    if isShort then
                        if not bc.settings.getValue( "convertEmotes" ) then continue end
                        if s > 1 then
                            if s > 2 then
                                if inpStr[s - 1] ~= " " then
                                    if not ( inpStr[s - 1] == "\\" and inpStr[s - 2] == " " ) then continue end
                                end
                            else
                                if inpStr[s - 1] ~= " " and inpStr[s - 1] ~= "\\" then continue end
                            end
                        end
                        if e < #inpStr and inpStr[e + 1] ~= " " then continue end
                    end

                    found = true

                    -- push string start to s
                    -- push image table
                    -- set string to e to end

                    if s > 1 and inpStr[s - 1] == "\\" then
                        table.insert( newTab, string.sub( inpStr, 1, s - 2 ) )
                        table.insert( newTab, { formatter = true, type = "text", text = string.sub( inpStr, s, e ) } )
                    else
                        table.insert( newTab, string.sub( inpStr, 1, s - 1 ) )
                        local data = bc.images.emoteLookup.lookup[str]
                        table.insert( newTab, { formatter = true, type = "image", sheet = data.sheet, idx = data.idx, text = str } )
                    end
                    inpStr = string.sub( inpStr, e + 1, #inpStr )

                    madeChange = true
                    break
                end

            end

            if #inpStr > 0 then
                table.insert( newTab, inpStr )
            end
        end
        tab = newTab
    end
    return tab
end

local function backTrackModifier( tab, state, key )
    if not state[key] then return end
    for k = #tab, 1, -1 do
        local v = tab[k]
        -- Is it a matching modifier
        if not ( istable( v ) and v.formatter and v.type == "decoration" and v.modifierType == key ) then
            continue
        end
        tab[k] = {
            formatter = true,
            type = "text",
            text = v.text
        }
        break
    end
end

local function getPlyModifiers( ply )
    local out = {}
    out.italic = bc.settings.isAllowed( ply, "bc_italics" )
    out.bold = bc.settings.isAllowed( ply, "bc_bold" )
    out.strike = bc.settings.isAllowed( ply, "bc_strike" )
    out.underline = bc.settings.isAllowed( ply, "bc_underline" )
    return out
end


function f.formatModifiers( tab, ply )
    local newTab = {}
    local state = {
        bold = false,
        underline = false,
        strike = false,
        italic = false
    }
    for k, v in pairs( tab ) do
        if type( v ) == "string" then
            local tab = f.formatModifiersSingle( v, state, getPlyModifiers( ply ) )
            table.Add( newTab, tab )
        else
            table.insert( newTab, v )
        end
    end

    for k, v in pairs( state ) do
        backTrackModifier( newTab, state, k )
    end

    table.insert( newTab, {
        formatter = true,
        type = "decoration"
    } )
    return newTab
end


--[[
*italics*
**bold**
__underline__
~~strike~~
]]

local modifierKeyMap = {
    ["~~"] = "strike",
    ["**"] = "bold",
    ["__"] = "underline",
    ["*"] = "italic"
}

function f.formatModifiersSingle( txt, state, allowed )
    if #table.GetKeys( allowed ) == 0 then return { txt } end
    local out = {}
    local s, e, escape, c1, c2
    local lastTxt = ""
    while true do
        s, e, escape, c1, c2 = string.find( " " .. txt, "([\\]?)([%*_~])(.?)" )
        if not s or lastTxt == txt then break end -- Prevent inf loop if something goes wrong
        lastTxt = txt

        if c2 == "" then -- If no second character (end of line), act as if there is
            e = e + 1
        end

        -- To account for added space at start
        s = s - 1
        e = e - 1
        -- Combine characters into a modifier, adjust e accordingly
        local c = c1
        if c1 == c2 then
            c = c .. c2
            e = e + 1
        end

        local key = modifierKeyMap[c]
        -- Do nothing (but separate out text so it doesn't get parsed twice/infinitely)
        if escape ~= "" or not key or not allowed[key] then
            table.insert( out, string.sub( txt, 1, s - 1 ) .. c )
            txt = string.sub( txt, e )
            continue
        end

        -- Get before and after text
        local preText = string.sub( txt, 1, s - 1 )
        txt = string.sub( txt, e )
        -- Make the decoration modifier
        state[key] = not state[key]
        local elem = {
            formatter = true,
            type = "decoration",
            modifierType = key,
            text = c
        }
        table.Merge( elem, state )
        -- Add everything to out
        if #preText > 0 then
            table.insert( out, preText )
        end
        table.insert( out, elem )
    end
    if #txt > 0 then
        table.insert( out, txt )
    end
    return out
end

local function getSpecialWord( text, start )
    local minS = #text + 1, #text + 1
    local col, name = nil, nil
    for k, v in pairs( player.GetAll() ) do
        s, e = string.find( string.lower( text ), string.lower( v:GetName() ), start, true )
        if s and s <= minS then
            if s == minS then
                if e < minE then continue end
            end
            minS = s
            minE = e
            col = team.GetColor( v:Team() )
            name = v
        end
    end
    if bc.settings.getValue( "formatColors" ) then
        for k, v in pairs( bc.defines.colors ) do
            k = chatHelper.camelToSpace( k )
            s, e = string.find( string.lower( text ), string.lower( k ), start, true )
            if s and s <= minS then
                if s == minS then
                    if e <= minE then continue end
                end
                minS = s
                minE = e
                col = v
                name = string.sub( text, s, e )
            end
        end
    end
    if minS == #text + 1 then
        return nil, nil
    end
    return minS, minE, col, name
end

-- for player names, colours and colourModifiers ([#ff0000])
function f.formatSpecialWords( text, tab )
    tab = table.Copy( tab )
    local s, e, v, n = getSpecialWord( text )
    while e do
        if s > 1 then
            local prevChar = text[s - 1]
            if not table.HasValue( { " ", "'", "\"", "*", "_", "~" }, prevChar ) then
                s, e, v, n = getSpecialWord( text, e + 1 )
                continue
            end
        end
        if e < #text then
            local nextChar = text[e + 1]
            if not table.HasValue( { " ", "'", "!", "?", "*", "_", "~" }, nextChar ) then
                if text[e + 1] ~= "s" and text[s - 1] ~= "\"" and text[e + 1] ~= ":" then
                    s, e, v, n = getSpecialWord( text, e + 1 )
                    continue
                elseif e < #text - 1 and bc.util.isLetter( text[e + 2] ) then
                    s, e, v, n = getSpecialWord( text, e + 1 )
                    continue
                end
            end

        end
        table.insert( tab, string.sub( text, 0, s - 1 ) )
        if type( n ) == "string" then
            table.insert( tab, v )
        end
        if n == LocalPlayer() and ply == LocalPlayer() then
            table.insert( tab, { formatter = true, type = "escape" } ) --escape pop from ply name
        end
        table.insert( tab, n )

        table.insert( tab, { defaultColor = true } )
        text = string.sub( text, e + 1, -1 )
        s, e, v, n = getSpecialWord( text )
    end

    if #text > 0 then
        table.insert( tab, text )
    end

    return tab
end

function f.formatLinks( tab )
    local newTab = {}
    for k, v in pairs( tab ) do
        if type( v ) == "string" then
            local tab = f.convertLinks( v )
            table.Add( newTab, tab )
        else
            table.insert( newTab, v )
        end
    end
    return newTab
end

function f.convertLinks( v )
    if type( v ) ~= "string" then return { v } end
    local tab = {}
    local lStart, lEnd, url = 0, 0, ""
    while true do
        lStart, lEnd, url = bc.util.getNextUrl( v )
        if not lStart then break end
        local preText = string.sub( v, 0, lStart - 1 )
        local postText = string.sub( v, lEnd + 1 )
        if #preText > 0 then
            table.insert( tab, preText )
        end
        table.insert( tab, {
            formatter = true,
            type = "clickable",
            signal = "Link-" .. url,
            text = url,
            color = bc.defines.theme.links
        } )
        v = postText
    end
    if #v > 0 then
        table.insert( tab, v )
    end
    return tab
end

function f.defaultFormatMessage( ply, text, teamChat, dead, col1, col2, data )
    local tab, madeChange = hook.Run( "BC_getDefaultTab", unpack( data ) )
    if tab and madeChange then
        return tab
    else
        tab = {}
        if dead then
            table.insert( tab, bc.defines.colors.red )
            table.insert( tab, "*DEAD* " )
        end

        if teamChat then
            table.insert( tab, bc.defines.colors.teamGreen )
            table.insert( tab, "(TEAM) " )
        end

        if type( ply ) == "Player" and ply:IsValid() then
            table.insert( tab, GAMEMODE:GetTeamColor( ply ) )
            table.insert( tab, ply )
            table.insert( tab, bc.defines.colors.white )
        elseif type( ply ) == "Entity" and not ply:IsValid() then
            table.insert( tab, bc.defines.colors.printBlue )
            table.insert( tab, "Console" )
            table.insert( tab, bc.defines.colors.white )
        else
            table.insert( tab, col1 )
            table.insert( tab, ply )
            table.insert( tab, col2 )
        end
        table.insert( tab, ": " .. text )

        return tab
    end
end

net.Receive( "BC_sayOverload", function()
    local ply = net.ReadEntity()
    local isTeam = net.ReadBool()
    local isDead = net.ReadBool()
    local msg = net.ReadString()
    if not hook.Run( "OnPlayerChat", ply, msg, isTeam, isDead ) then return end
    if not bc.base.enabled then
        chat.AddText( unpack( f.defaultFormatMessage( ply, msg, isTeam, isDead ) ) )
    end
end )

function f.onPlayerSayHook( ... )
    for priority = -2, 2 do
        for k, v in pairs( bc.overload.hooks.OnPlayerChat ) do
            if type( v ) == "function" then
                v = {
                    [0] = { fn = v }
                }
            end
            if not v[priority] then continue end
            local success, ret = xpcall( v[priority].fn, function( e )
                print( "Error in OnPlayerChat hook: " .. k )
                print( e )
            end, ... )
            if success and ret ~= nil then
                return ret
            end
        end
    end

    ply, text, teamChat, dead, pre, col1, col2 = ... -- pre, col1 and col2 are supplied by DarkRP

    local maxLen = bc.settings.getServerValue( "maxLength" )
    if #text > maxLen then
        text = string.sub( text, 1, maxLen )
    end

    local plyValid = ply and ply:IsValid()
    if plyValid and bc.sidePanel.players.settings[ply:SteamID()] and bc.sidePanel.players.settings[ply:SteamID()].ignore ~= 0 then return true end

    local tab
    if pre then
        tab = f.formatMessage( ply, text, false, col2, true, { ... } )
        tab[2] = { formatter = true, type = "escape" }
        tab[3] = {
            formatter = true,
            type = ( plyValid and "clickable" or "text" ),
            signal = "Player-" .. ( plyValid and ply:SteamID() or "" ),
            text = pre,
            color = col1
        }
    else
        tab = f.formatMessage( ply, text, dead )
    end

    bc.channels.message( { ( teamChat and not DarkRP ) and "Team" or "Players" }, unpack( tab ) )

    if bc.overload.old.AddText then
        bc.overload.old.AddText( unpack( f.defaultFormatMessage( pre or ply, text, teamChat, pre and false or dead, col1, col2, { ... } ) ) ) --Keep old chat up to date
    end
    return true
end

function f.print( ... )
    local data = { ... }
    local col = bc.defines.colors.white
    for k, v in pairs( data ) do
        if type( v ) == "table" then
            col = v
        elseif ( v == "You" or v == "Yourself" ) and col == bc.defines.colors.ulxYou then
            data[k] = { formatter = true, type = "clickable", signal = "Player-" .. LocalPlayer():SteamID(), text = v }
        else
            local isPly = false
            for i, ply in pairs( player.GetAll() ) do
                if ply:GetName() == v and col == team.GetColor( ply:Team() ) then
                    data[k] = ply
                    isPly = true
                end
            end
            if not isPly then
                local tab = f.convertLinks( v )
                if #tab ~= 1 or tab[1] ~= v then
                    table.remove( data, k )
                    for l = #tab, 1, -1 do
                        table.insert( data, k, tab[l] )
                    end
                end
            end
        end
    end
    if not bc.base.enabled then return end
    for k, v in pairs( bc.channels.channels or {} ) do
        if v.doPrints and not v.replicateAll then
            bc.channels.messageDirect( v.name, unpack( data ) )
        end
    end
end

function f.triggerTick()
    if not bc.settings.getValue( "doTick" ) then return end
    if timer.Exists( "BC_triggerTick" ) then timer.Destroy( "BC_triggerTick" ) end
    timer.Create( "BC_triggerTick", 0.05, 1, function()
        chat.PlaySound()
    end )
end

function f.triggerPop()
    if not bc.settings.getValue( "doPop" ) then return end
    if timer.Exists( "BC_triggerTick" ) then timer.Destroy( "BC_triggerTick" ) end
    if timer.Exists( "BC_triggerPop" ) then timer.Destroy( "BC_triggerPop" ) end
    timer.Create( "BC_triggerPop", 0.05, 1, function()
        f.playPop()
    end )
end

function f.playPop()
    surface.PlaySound( "garrysmod/balloon_pop_cute.wav" )
end