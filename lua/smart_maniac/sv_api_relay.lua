--[[
    Smart Maniac NPC - Server-side API Relay (SSL FIX)
    
    GMod's built-in HTTP() function uses outdated SSL certificates,
    causing "SSL connect error" with modern HTTPS endpoints like OpenRouter.
    
    This module provides SmartManiac.API.Request() which:
    1. First tries server-side HTTP() directly
    2. On SSL failure, falls back to routing the request through a client's
       DHTML panel (Chromium/CEF) which has up-to-date SSL certificates
    
    All other modules should use SmartManiac.API.Request() instead of HTTP().
]]

SmartManiac = SmartManiac or {}
SmartManiac.API = SmartManiac.API or {}

local pendingCallbacks = {}
local requestCounter = 0
local useRelayMode = true  -- Default ON: GMod's HTTP() has known SSL issues with modern endpoints

--- Pick the best client to relay through (prefer listen server host).
local function GetRelayClient()
    -- In singleplayer / listen server, the host is always the best choice
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:IsListenServerHost() then
            return ply
        end
    end
    -- Fallback: any connected admin
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:IsAdmin() then
            return ply
        end
    end
    -- Last resort: any player
    local players = player.GetAll()
    if #players > 0 and IsValid(players[1]) then
        return players[1]
    end
    return nil
end

--- Send an API request through the client-side DHTML relay.
local function RelayRequest(requestId, url, method, headers, body, callback)
    local client = GetRelayClient()
    if not IsValid(client) then
        print("[Smart Maniac] API relay: no client available for relay!")
        if callback then callback(nil, "no relay client") end
        return
    end

    pendingCallbacks[requestId] = callback

    local headersJson = util.TableToJSON(headers or {})

    print("[Smart Maniac] API relay: sending request #" .. requestId .. " via " .. client:Nick())

    net.Start("SmartManiac_APIRequest")
        net.WriteString(requestId)
        net.WriteString(url)
        net.WriteString(method or "POST")
        net.WriteString(headersJson)
        net.WriteString(body or "")
    net.Send(client)

    -- Timeout: if no response in 30 seconds, clean up
    timer.Create("SmartManiac_APITimeout_" .. requestId, 30, 1, function()
        if pendingCallbacks[requestId] then
            print("[Smart Maniac] API relay: request #" .. requestId .. " timed out")
            local cb = pendingCallbacks[requestId]
            pendingCallbacks[requestId] = nil
            if cb then cb(nil, "relay timeout") end
        end
    end)
end

--- Receive response from client relay.
net.Receive("SmartManiac_APIResponse", function(len, ply)
    local requestId = net.ReadString()
    local statusCode = net.ReadUInt(16)
    local responseBody = net.ReadString()

    timer.Remove("SmartManiac_APITimeout_" .. requestId)

    local callback = pendingCallbacks[requestId]
    pendingCallbacks[requestId] = nil

    if not callback then
        print("[Smart Maniac] API relay: received response for unknown request #" .. requestId)
        return
    end

    print("[Smart Maniac] API relay: got response #" .. requestId .. " (HTTP " .. statusCode .. ")")

    if statusCode >= 200 and statusCode < 300 then
        callback(responseBody, nil, statusCode)
    else
        callback(responseBody, "HTTP " .. statusCode, statusCode)
    end
end)

--- Main API request function. Replaces direct HTTP() calls.
--- @param url string  The API endpoint URL
--- @param method string  HTTP method (GET, POST, etc.)
--- @param headers table  HTTP headers
--- @param body string  Request body (JSON string)
--- @param onSuccess function(responseBody, statusCode)  Success callback
--- @param onFail function(errorMsg)  Failure callback
function SmartManiac.API.Request(url, method, headers, body, onSuccess, onFail)
    requestCounter = requestCounter + 1
    local requestId = tostring(requestCounter)

    -- If we already know SSL fails, go straight to relay
    if useRelayMode then
        RelayRequest(requestId, url, method, headers, body, function(responseBody, err, code)
            if err and not responseBody then
                if onFail then onFail(err) end
            elseif code and code >= 200 and code < 300 then
                if onSuccess then onSuccess(code, responseBody) end
            else
                -- Got a response but not 2xx - still call onSuccess with the code
                -- so the caller can handle specific HTTP error codes
                if onSuccess then onSuccess(code or 0, responseBody or "") end
            end
        end)
        return
    end

    -- Try server-side HTTP() first
    HTTP({
        url     = url,
        method  = method or "POST",
        headers = headers or {},
        body    = body,
        type    = "application/json",
        success = function(code, responseBody)
            if onSuccess then onSuccess(code, responseBody) end
        end,
        failed  = function(err)
            local errStr = tostring(err)
            print("[Smart Maniac] HTTP() failed: " .. errStr)

            -- If SSL error, switch to relay mode permanently for this session
            if string.find(errStr, "SSL") or string.find(errStr, "ssl") 
               or string.find(errStr, "certificate") or string.find(errStr, "CERTIFICATE") then
                print("[Smart Maniac] SSL error detected! Switching to DHTML relay mode for all future requests.")
                useRelayMode = true

                -- Retry this request via relay
                RelayRequest(requestId, url, method, headers, body, function(responseBody, relayErr, code)
                    if relayErr and not responseBody then
                        if onFail then onFail(relayErr) end
                    elseif code and code >= 200 and code < 300 then
                        if onSuccess then onSuccess(code, responseBody) end
                    else
                        if onSuccess then onSuccess(code or 0, responseBody or "") end
                    end
                end)
            else
                if onFail then onFail(errStr) end
            end
        end,
    })
end

--- Force relay mode on (useful for testing or manual override).
function SmartManiac.API.ForceRelay(enabled)
    useRelayMode = enabled
    print("[Smart Maniac] API relay mode: " .. (enabled and "FORCED ON" or "auto-detect"))
end

--- Check if relay mode is active.
function SmartManiac.API.IsRelayMode()
    return useRelayMode
end

--- Console command to force relay mode
concommand.Add("sm_maniac_force_relay", function(ply, cmd, args)
    if IsValid(ply) and not ply:IsAdmin() then return end
    local enabled = not args or #args == 0 or args[1] == "1"
    SmartManiac.API.ForceRelay(enabled)
    local msg = "[Smart Maniac] API relay mode: " .. (enabled and "ON" or "OFF")
    print(msg)
    if IsValid(ply) then ply:ChatPrint(msg) end
end)

print("[Smart Maniac] API relay module loaded (SSL fix: auto-fallback to DHTML fetch).")
