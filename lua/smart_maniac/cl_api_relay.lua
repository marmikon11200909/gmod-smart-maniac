--[[
    Smart Maniac NPC - Client-side API Relay (SSL FIX)
    
    GMod's server-side HTTP() uses outdated SSL certificates that fail
    with "SSL connect error" on many endpoints (OpenRouter, OpenAI, etc).
    
    This module relays API requests through a DHTML panel (Chromium/CEF)
    which has up-to-date SSL certificates. The server sends the request
    data to a client, the client makes the HTTP call via fetch(), and
    sends the response back to the server.
    
    Flow:
    Server -> net "SmartManiac_APIRequest" -> Client DHTML fetch() ->
    -> net "SmartManiac_APIResponse" -> Server callback
]]

SmartManiac = SmartManiac or {}
SmartManiac.APIRelay = SmartManiac.APIRelay or {}

local relayPanel = nil
local pendingRequests = {}
local isReady = false
local initAttempts = 0

--- Initialize the DHTML relay panel.
function SmartManiac.APIRelay.Init()
    if IsValid(relayPanel) then
        relayPanel:Remove()
    end

    initAttempts = initAttempts + 1
    print("[Smart Maniac] Initializing API relay panel (attempt " .. initAttempts .. ")")

    relayPanel = vgui.Create("DHTML")
    relayPanel:SetSize(1, 1)
    relayPanel:SetPos(0, 0)
    relayPanel:SetVisible(false)
    relayPanel:SetAlpha(0)

    relayPanel:AddFunction("gmod", "relayReady", function()
        isReady = true
        print("[Smart Maniac] API relay panel ready (DHTML fetch available)")
    end)

    relayPanel:AddFunction("gmod", "relayResponse", function(requestId, statusCode, responseBody)
        requestId = tostring(requestId)
        statusCode = tonumber(statusCode) or 0

        print("[Smart Maniac] API relay response for #" .. requestId .. " (HTTP " .. statusCode .. ")")

        -- Send response back to server
        net.Start("SmartManiac_APIResponse")
            net.WriteString(requestId)
            net.WriteUInt(statusCode, 16)
            net.WriteString(responseBody or "")
        net.SendToServer()

        pendingRequests[requestId] = nil
    end)

    relayPanel:AddFunction("gmod", "relayError", function(requestId, errorMsg)
        requestId = tostring(requestId)
        print("[Smart Maniac] API relay error for #" .. requestId .. ": " .. tostring(errorMsg))

        net.Start("SmartManiac_APIResponse")
            net.WriteString(requestId)
            net.WriteUInt(0, 16)
            net.WriteString("")
        net.SendToServer()

        pendingRequests[requestId] = nil
    end)

    local html = [[<!DOCTYPE html>
<html><head><meta charset="utf-8"></head><body><script>
var ready = false;

function doFetch(requestId, url, method, headersJson, body) {
    var headers = {};
    try { headers = JSON.parse(headersJson); } catch(e) {}

    var opts = {
        method: method || 'POST',
        headers: headers,
        body: body || null
    };

    fetch(url, opts)
        .then(function(response) {
            return response.text().then(function(text) {
                gmod.relayResponse(requestId, response.status, text);
            });
        })
        .catch(function(err) {
            gmod.relayError(requestId, err.message || 'fetch_failed');
        });
}

gmod.relayReady();
ready = true;
</script></body></html>]]

    relayPanel:SetHTML(html)

    -- Retry if not ready after 5 seconds
    timer.Simple(5, function()
        if not isReady and initAttempts < 3 then
            print("[Smart Maniac] API relay not ready, retrying...")
            SmartManiac.APIRelay.Init()
        end
    end)
end

--- Execute a fetch request via the DHTML panel.
local function ExecuteFetch(requestId, url, method, headersJson, body)
    if not IsValid(relayPanel) or not isReady then
        print("[Smart Maniac] API relay panel not ready, reinitializing...")
        SmartManiac.APIRelay.Init()
        -- Queue the request for after init
        timer.Simple(2, function()
            if IsValid(relayPanel) and isReady then
                ExecuteFetch(requestId, url, method, headersJson, body)
            else
                print("[Smart Maniac] API relay still not ready, request #" .. requestId .. " dropped")
                net.Start("SmartManiac_APIResponse")
                    net.WriteString(requestId)
                    net.WriteUInt(0, 16)
                    net.WriteString("")
                net.SendToServer()
            end
        end)
        return
    end

    -- Escape strings for JavaScript
    local safeUrl = string.gsub(url, "'", "\\'")
    local safeMethod = string.gsub(method, "'", "\\'")
    local safeHeaders = string.gsub(headersJson, "'", "\\'")
    local safeBody = string.gsub(body, "'", "\\'")
    safeBody = string.gsub(safeBody, "\n", "\\n")
    safeBody = string.gsub(safeBody, "\r", "")

    local js = string.format(
        "doFetch('%s', '%s', '%s', '%s', '%s');",
        requestId, safeUrl, safeMethod, safeHeaders, safeBody
    )

    relayPanel:RunJavascript(js)
    pendingRequests[requestId] = CurTime()
end

-- Receive API request from server
net.Receive("SmartManiac_APIRequest", function()
    local requestId = net.ReadString()
    local url = net.ReadString()
    local method = net.ReadString()
    local headersJson = net.ReadString()
    local body = net.ReadString()

    print("[Smart Maniac] API relay request #" .. requestId .. " -> " .. string.sub(url, 1, 60))
    ExecuteFetch(requestId, url, method, headersJson, body)
end)

-- Cleanup stale pending requests
timer.Create("SmartManiac_APIRelay_Cleanup", 30, 0, function()
    local now = CurTime()
    for id, startTime in pairs(pendingRequests) do
        if now - startTime > 30 then
            pendingRequests[id] = nil
        end
    end
end)

-- Initialize on game load
hook.Add("InitPostEntity", "SmartManiac_APIRelayInit", function()
    timer.Simple(0.5, function()
        SmartManiac.APIRelay.Init()
    end)
end)

function SmartManiac.APIRelay.IsReady()
    return isReady and IsValid(relayPanel)
end

print("[Smart Maniac] API relay module loaded (SSL fix via DHTML fetch).")
