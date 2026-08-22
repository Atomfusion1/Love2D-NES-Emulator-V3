local cartridge  = {}
cartridge.ROM    = {}
cartridge.header = {}
cartridge.Mirror = 1
cartridge.mapper = nil
--# Save Header
for i = 0x00, 0x10 do
    cartridge.header[i] = 0x00
end
--# Save Starting ROM
for i = 0x0000, 0xFFFF do
    cartridge.ROM[i] = 0x00
end

--# Open File
local function OpenFile(filepath)
    local file = assert(io.open(filepath, 'rb'))
    return file
end

--# Close File
local function CloseFile(file)
    file:close()
end

-- Read enough of an iNES header to decide whether this emulator can load the
-- cartridge.  This is deliberately non-mutating so a rejected ROM cannot
-- replace the cartridge that is currently running.
function cartridge.ParseHeader(headerData)
    if not headerData or #headerData < 16 then
        return nil, "The file is too small to contain an iNES header."
    end
    if headerData:sub(1, 4) ~= "NES\26" then
        return nil, "The file does not contain a valid iNES header."
    end

    local flags6 = headerData:byte(7)
    local flags7 = headerData:byte(8)
    return {
        mapper = bit.band(flags7, 0xF0) + bit.rshift(bit.band(flags6, 0xF0), 4),
        mirror = bit.band(flags6, 0x01),
        battery = bit.band(flags6, 0x02) ~= 0,
    }
end

function cartridge.Inspect(filepath)
    if not filepath or filepath == "" then
        return nil, "No ROM file was selected."
    end

    local file, openError = io.open(filepath, "rb")
    if not file then
        return nil, "Unable to open ROM: " .. tostring(openError)
    end

    local headerData = file:read(16)
    CloseFile(file)
    return cartridge.ParseHeader(headerData)
end

--# Check for NES Header
function IsFileHeader(filepath)
    local IsHeaderFound = false
    local file          = OpenFile(filepath) -- Open File
    local fileData      = file:read('line') -- Read In File
    CloseFile(file) -- Close File
    if string.find(fileData, "NES") then -- Check For Header
        IsHeaderFound = true
    else
        love.window.showMessageBox("WARNING NOT A NES CART", "NES Header Not Found")
        love.event.quit()
    end
    return IsHeaderFound
end

--# Load File into Memory
function cartridge.LoadFile(filepath)
    local fileData   = {}
    local header     = {}
    local file       = OpenFile(filepath) -- Open File
    local fileString = file:read("*all") -- Read File
    CloseFile(file) -- Close File

    -- Convert String into Byte and Shift Array into 0-endoffile
    for i = 0, #fileString - 1 do
        fileData[i] = string.byte(fileString, i + 1)
        if i < 0x10 then
            header[i] = string.byte(fileString, i + 1)
        end
    end
    cartridge.Mirror = bit.band(header[0x06], 0x01) -- Set Mirror off Flag 6 bit 0 , 1 = vertical 
    cartridge.mapper = bit.band(header[0x07], 0xF0) + bit.rshift(bit.band(header[0x06], 0xF0),4)
    print("mapper "..cartridge.mapper.." Mirror "..cartridge.Mirror)
    return fileData, header
end

--# Cartrige Initialization NES Emulator Starts Here
function cartridge.Initialize(filepath)
    IsFileHeader(filepath)
    cartridge.FileName = filepath
    cartridge.ROM, cartridge.header = cartridge.LoadFile(filepath)
    print("Cartridge Loaded with header", table.concat(cartridge.header, ", "))
    return cartridge.ROM
end


return cartridge
