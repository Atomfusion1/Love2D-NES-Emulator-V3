local cart = require("NES.Cartridge.Cartridge")

local cheats = {
    entries = {},
    ramEntries = {},
    romEntries = {},
    romPatches = {},
    romReference = nil,
    romOriginals = {},
    romOverridesActive = false,
    enabled = true,
    rapidA = false,
    rapidB = false,
    rapidRate = 1,
    filePath = nil,
    lastError = nil
}
local gameGenieValues = { A=0, P=1, Z=2, L=3, G=4, I=5, T=6, Y=7, E=8, O=9, X=10, U=11, K=12, S=13, V=14, N=15 }

local function decodeGameGenie(code)
    code = string.upper(tostring(code or "")):gsub("[%-%s]", "")
    if #code ~= 6 and #code ~= 8 then return nil, "Game Genie codes must have 6 or 8 letters." end
    local n = {}
    for i = 1, #code do
        n[i - 1] = gameGenieValues[code:sub(i, i)]
        if n[i - 1] == nil then return nil, "Invalid Game Genie letter: " .. code:sub(i, i) end
    end
    local address = 0x8000 + bit.lshift(bit.band(n[3], 7), 12)
        + bit.lshift(bit.band(n[5], 7), 8) + bit.lshift(bit.band(n[4], 8), 8)
        + bit.lshift(bit.band(n[2], 7), 4) + bit.lshift(bit.band(n[1], 8), 4)
        + bit.band(n[4], 7) + bit.band(n[3], 8)
    local value = bit.bor(bit.lshift(bit.band(n[1], 7), 4), bit.lshift(bit.band(n[0], 8), 4),
        bit.band(n[0], 7), bit.rshift(bit.band(n[#code == 8 and 7 or 5], 8), 3))
    local entry = { address = address, value = value, code = code }
    if #code == 8 then
        entry.compare = bit.bor(bit.lshift(bit.band(n[7], 7), 4), bit.lshift(bit.band(n[6], 8), 4),
            bit.band(n[6], 7), bit.rshift(bit.band(n[5], 8), 3))
    end
    return entry
end

local function parseAddressValue(line)
    local address, value = line:match("^%s*([%x]+)%s*:%s*([%x]+)")
    if not address then return nil end
    address, value = tonumber(address, 16), tonumber(value, 16)
    if address and value and address <= 0xFFFF and value <= 0xFF then return { address = address, value = value } end
end

local function parseRomPatch(line)
    local address, value = line:match("^%s*ROM%s*:%s*([%x]+)%s*:%s*([%x]+)")
    if not address then return nil end
    address, value = tonumber(address, 16), tonumber(value, 16)
    if address and value and value <= 0xFF then
        return { offset = address, value = value, physical = true }
    end
end

local function addEntry(entry)
    entry.enabled = entry.enabled ~= false
    cheats.entries[#cheats.entries + 1] = entry
    if entry.physical then
        cheats.romPatches[#cheats.romPatches + 1] = entry
        return
    end
    if entry.address < 0x8000 then
        cheats.ramEntries[#cheats.ramEntries + 1] = entry
    else
        local entriesAtAddress = cheats.romEntries[entry.address]
        if not entriesAtAddress then
            entriesAtAddress = {}
            cheats.romEntries[entry.address] = entriesAtAddress
        end
        entriesAtAddress[#entriesAtAddress + 1] = entry
        cheats.romOverridesActive = true
    end
end

local function cartridgeCheatPath()
    local name = string.match(tostring(cart.FileName or ""), "[^/\\]+$") or "default.nes"
    return "Cheats/" .. name:gsub("%.[^%.]+$", "") .. ".txt"
end

local function saveEntries()
    if not love.filesystem.write or not cheats.filePath then return end
    if love.filesystem.createDirectory then love.filesystem.createDirectory("Cheats") end
    local lines = {
        string.format("@master:%d", cheats.enabled and 1 or 0),
        string.format("@rapidA:%d", cheats.rapidA and 1 or 0),
        string.format("@rapidB:%d", cheats.rapidB and 1 or 0),
        string.format("@rapidRate:%d", cheats.rapidRate)
    }
    for _, entry in ipairs(cheats.entries) do
        local prefix = entry.enabled and "" or "!"
        if entry.physical then
            lines[#lines + 1] = prefix .. string.format("ROM:%06X:%02X", entry.offset, entry.value)
        else
            lines[#lines + 1] = prefix .. string.format("%04X:%02X", entry.address, entry.value)
        end
    end
    love.filesystem.write(cheats.filePath, table.concat(lines, "\n") .. "\n")
end

function cheats.LoadForCartridge()
    cheats.entries, cheats.ramEntries, cheats.romEntries, cheats.romPatches = {}, {}, {}, {}
    cheats.romOverridesActive = false
    cheats.enabled = true
    cheats.rapidA = false
    cheats.rapidB = false
    cheats.rapidRate = 1
    cheats.lastError = nil
    cheats.filePath = cartridgeCheatPath()
    local contents = love.filesystem.read(cheats.filePath)
    if not contents then
        local file = io.open(cheats.filePath, "rb")
        if file then contents = file:read("*all"); file:close() end
    end
    if not contents then return 0 end
    for line in contents:gmatch("[^\r\n]+") do
        line = line:gsub(";.*$", ""):gsub("#.*$", "")
        local setting, settingValue = line:match("^%s*@([%w]+)%s*:%s*([01-8]+)")
        if setting then
            settingValue = tonumber(settingValue)
            if setting == "master" then cheats.enabled = settingValue ~= 0 end
            if setting == "rapidA" then cheats.rapidA = settingValue ~= 0 end
            if setting == "rapidB" then cheats.rapidB = settingValue ~= 0 end
            if setting == "rapidRate" then cheats.rapidRate = math.max(1, math.min(8, settingValue)) end
        end
        local disabled = line:match("^%s*!" ) ~= nil
        line = line:gsub("^%s*!", "")
        local entry = parseRomPatch(line) or parseAddressValue(line) or decodeGameGenie(line)
        if entry then entry.enabled = not disabled; addEntry(entry) end
    end
    return #cheats.entries
end

function cheats.AddGameGenie(code)
    local entry, errorMessage = cheats.AddCode(code)
    return entry, errorMessage
end

function cheats.AddCode(code)
    local line = tostring(code or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local entry = parseRomPatch(line) or parseAddressValue(line)
    local errorMessage
    if not entry then entry, errorMessage = decodeGameGenie(line) end
    if not entry then return nil, errorMessage end
    addEntry(entry)
    saveEntries()
    return entry
end
function cheats.DecodeGameGenie(code) return decodeGameGenie(code) end
function cheats.ApplyRAM(cpuMemory)
    if not cheats.enabled then return end
    for _, entry in ipairs(cheats.ramEntries) do
        if entry.enabled then cpuMemory[entry.address] = entry.value end
    end
end
function cheats.ApplyROM(rom)
    cheats.romReference = rom
    cheats.romOriginals = {}
    for _, entry in ipairs(cheats.romPatches) do
        if rom[entry.offset] ~= nil then
            cheats.romOriginals[entry.offset] = rom[entry.offset]
        end
    end
    local function refreshROM()
        for offset, value in pairs(cheats.romOriginals) do rom[offset] = value end
        if cheats.enabled then
            for _, entry in ipairs(cheats.romPatches) do
                if entry.enabled and rom[entry.offset] ~= nil then rom[entry.offset] = entry.value end
            end
        end
    end
    cheats.refreshROM = refreshROM
    refreshROM()
end
function cheats.OverrideROMRead(address, actual)
    if not cheats.enabled then return actual end
    local entriesAtAddress = cheats.romEntries[address]
    if not entriesAtAddress then return actual end
    for _, entry in ipairs(entriesAtAddress) do
        if entry.enabled and (not entry.compare or entry.compare == actual) then return entry.value end
    end
    return actual
end
function cheats.GetEntries() return cheats.entries end
function cheats.GetFilePath() return cheats.filePath end
function cheats.SetEnabled(enabled)
    cheats.enabled = enabled and true or false
    if cheats.refreshROM then cheats.refreshROM() end
    saveEntries()
end
function cheats.SetRapidButton(button, enabled)
    if button == "a" then cheats.rapidA = enabled and true or false end
    if button == "b" then cheats.rapidB = enabled and true or false end
    saveEntries()
end
function cheats.IsRapidButtonEnabled(button)
    if not cheats.enabled then return false end
    return button == "a" and cheats.rapidA or button == "b" and cheats.rapidB or false
end
function cheats.SetRapidRate(rate)
    cheats.rapidRate = math.max(1, math.min(8, math.floor(rate or 1)))
    saveEntries()
end
function cheats.GetRapidRate() return cheats.rapidRate end
function cheats.ToggleEntry(index)
    if cheats.entries[index] then
        cheats.entries[index].enabled = not cheats.entries[index].enabled
        if cheats.refreshROM then cheats.refreshROM() end
        saveEntries()
    end
end
function cheats.RemoveEntry(index)
    if not cheats.entries[index] then return end
    table.remove(cheats.entries, index)
    local remainingEntries = cheats.entries
    cheats.entries = {}
    cheats.ramEntries, cheats.romEntries, cheats.romPatches = {}, {}, {}
    cheats.romOverridesActive = false
    for _, entry in ipairs(remainingEntries) do addEntry(entry) end
    if cheats.refreshROM then cheats.refreshROM() end
    saveEntries()
end

return cheats
