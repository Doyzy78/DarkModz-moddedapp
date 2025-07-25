-- Set Your Libname here
local libNameSo = "libil2cpp.so"  -- Define the library name
local info = gg.getTargetInfo() -- Get information about the target app
local APK = info.label    -- Get APK name

-- Define tables and flags for memory handling
X_X = {}  -- Store memory range start addresses
UwU = 0    -- Counter for memory ranges
LibraryStatus = 0  -- Flag for library status (0 = not found)
MemoryRanges = gg.getRangesList()  -- Get the memory ranges list

-- Check if no memory ranges are found, exit if true
if #MemoryRanges == 0 then
    print("No libraries found. Check environment.")
    gg.setVisible(true)
    os.exit()
end

-- Try to fetch memory ranges for the specified library
MemoryRanges = gg.getRangesList(libNameSo)
if #MemoryRanges == 0 then
    LibraryStatus = 2  -- Mark as split library search
    goto LIBRARY_SPLIT  -- Jump to the split library check
end

-- Loop through memory ranges to find valid range (state == "Xa")
for i, range in ipairs(MemoryRanges) do
    if range.state == "Xa" then
        UwU = UwU + 1
        X_X[UwU] = range.start  -- Store the start address of valid range
        LibrarySize = range["end"] - range.start  -- Get library size
        LibraryStatus = 1  -- Mark library as found
    end
end

-- Check if no valid library was found
if LibraryStatus == 0 then
    print(libNameSo .. " not found in Xa region.")
    gg.setVisible(true)
    os.exit()
end

-- Split library detection and handling
::LIBRARY_SPLIT::
if LibraryStatus == 2 then
    SplitApkFound = false  -- Flag for split APK detection
    MemoryRanges = gg.getRangesList()  -- Get all memory ranges again

    -- Check for "split_config" in the memory range names
    for i, range in ipairs(MemoryRanges) do
        if range.state == "Xa" and string.match(range.name, "split_config") then
            SplitApkFound = true
        end
    end

    -- Handle split APK if found
    if SplitApkFound then
        SplitSizes = {}
        SplitCount = 0
        for i, range in ipairs(MemoryRanges) do
            if range.state == "Xa" then
                SplitCount = SplitCount + 1
                SplitSizes[SplitCount] = range["end"] - range.start  -- Store size of each split
            end
        end

        -- Find the largest split
        if SplitCount > 0 then
            MaxSplitSize = math.max(table.unpack(SplitSizes))
            -- Iterate to find the largest split size
            for i, range in ipairs(MemoryRanges) do
                if range.state == "Xa" and (range["end"] - range.start) == MaxSplitSize then
                    UwU = UwU + 1
                    X_X[UwU] = range.start  -- Store start address of largest split
                    LibrarySize = range["end"] - range.start
                    LibraryStatus = 1
                end
            end
        end
    else
        print("No split_config lib found.")
        gg.setVisible(true)
        os.exit()
    end
end

-- Final library check
if LibraryStatus ~= 1 then
    print("Correct lib not found.")
    gg.setVisible(true)
    os.exit()
end

-- Arm Patch
-- Table to store original values for specific offsets
local Original = {}

-- Function to record the original values at a specific offset range
local function RecordOriginalValue(offset)
    local REV = gg.getValues((function(R)
        for _, x in ipairs({offset}) do -- Set Offset 
            for i = 0, 16, 4 do
                R[#R + 1] = {address = X_X[UwU] + x + i, flags = 4}
            end
        end
        return R
    end)({}))

    -- Store the original values in the Original table using the same offset key
    Original[offset] = REV
end

-- Function to revert the values back to the original state for a specific offset
local function RevertValue(offset)
    local originalValues = Original[offset]
    if originalValues then
        gg.setValues(originalValues)  -- Revert to the original values
        gg.toast("Hack [OFF]")
        gg.sleep(1000)
        gg.toast("--( X_X )--")
    else
        gg.alert("⛔ ERROR : ORIGINAL VALUE NOT FOUND ⛔")
    end
end

-- Inject assembly values
local function injectAssembly(offset, value)
    local addr = X_X[UwU] + offset

    if value == true then
        -- R0 = 1
        gg.setValues({
            {address = addr, flags = 4, value = "~A MOV R0, #1"},
            {address = addr + 0x4, flags = 4, value = "~A BX LR"}
        })

    elseif value == false then
        -- R0 = 0
        gg.setValues({
            {address = addr, flags = 4, value = "~A MOV R0, #0"},
            {address = addr + 0x4, flags = 4, value = "~A BX LR"}
        })

    elseif type(value) == "number" and value >= 0 and value <= 999999999 then
        if value <= 0xFF then
            -- Fits in MOV #imm8
            gg.setValues({
                {address = addr, flags = 4, value = string.format("~A MOV R0, #%d", value)},
                {address = addr + 0x4, flags = 4, value = "~A BX LR"}
            })
        elseif value <= 0xFFFF then
            -- Fits in MOVW
            gg.setValues({
                {address = addr, flags = 4, value = string.format("~A MOVW R0, #%d", value)},
                {address = addr + 0x4, flags = 4, value = "~A BX LR"}
            })
        else
            -- Requires MOVW + MOVT
            local lower16 = value & 0xFFFF
            local upper16 = (value >> 16) & 0xFFFF
            gg.setValues({
                {address = addr, flags = 4, value = string.format("~A MOVW R0, #%d", lower16)},
                {address = addr + 0x4, flags = 4, value = string.format("~A MOVT R0, #%d", upper16)},
                {address = addr + 0x8, flags = 4, value = "~A BX LR"}
            })
        end
    else
        gg.alert("❌ Invalid value.\nMust be a number from 0 to 999,999,999")
    end
end


-- Set up target game environment for memory patching
::GET_READY::
gg.setVisible(false)  -- Hide the GameGuardian UI
for i = 20, 100, 20 do
    gg.sleep(300)
    gg.toast(i .. "%")
end
local ti = gg.getTargetInfo()  -- Get target info (for 64-bit vs 32-bit detection)
local p_size = ti.x64 and 0x8 or 0x4  -- Determine pointer size

-- Define path to save offsets
local offsetFilePath = gg.EXT_FILES_DIR .. "/" .. APK .. "_Offsets.lua"

-- Functions to retrieve and manipulate memory values
local function getvalue(address, ggType)  -- Get memory value from a specified address
    return gg.getValues({{address = address, flags = ggType}})[1].value
end

local function ptr(address)  -- Get pointer value (32-bit or 64-bit)
    return getvalue(address, ti.x64 and gg.TYPE_QWORD or gg.TYPE_DWORD)
end

local function CString(address, str)  -- Compare string at address with the target string
    local bytes = gg.bytes(str)
    for i = 1, #bytes do
        if getvalue(address + i - 1, gg.TYPE_BYTE) & 0xFF ~= bytes[i] then
            return false
        end
    end
    return getvalue(address + #bytes, gg.TYPE_BYTE) == 0
end

-- Function to get a method from Il2Cpp by class and method name
local function GetIl2CppMethod(clazz, method)
    local result = {}
    gg.clearResults()
    gg.setRanges(gg.REGION_C_ALLOC | gg.REGION_ANONYMOUS | gg.REGION_OTHER | gg.REGION_CODE_APP | gg.REGION_C_BSS | gg.REGION_C_DATA)
    gg.searchNumber(string.format("Q 00 '%s' 00", method), gg.TYPE_BYTE)
    local count = gg.getResultsCount()

    if count > 0 then
        gg.refineNumber(method:byte(), gg.TYPE_BYTE)
        local t = gg.getResults(count)
        gg.searchPointer(0)
        t = gg.getResults(count)
        for _, v in ipairs(t) do
            if CString(ptr(ptr(v.address + p_size) + p_size * 2), clazz) then
                table.insert(result, {
                    address = ptr(v.address - p_size * 2),
                    name = string.format("%s :: %s", clazz, method),
                    flags = v.flags
                })
            end
        end
        gg.clearResults()
    end

    return result
end

-- Save and load offsets for methods
local function saveOffsetsToFile(offsets)
    local file = io.open(offsetFilePath, "w")
    file:write("-- "..APK.."\n-- Version : "..info.versionName.."\n")
    file:write("-- Script By : DarkWolf\n")
    file:write("-- "..string.rep("═─═", 5).."\n")
    for method, offset in pairs(offsets) do
        file:write(string.format("%s = %s\n", method, offset))
    end
    file:close()
end

local function loadOffsetsFromFile()
    local offsets = {}
    local file = io.open(offsetFilePath, "r")
    if file then
        for line in file:lines() do
            local method, offset = line:match("^(.-) = (.-)$")
            if method and offset then
                offsets[method] = offset
            end
        end
        file:close()
    end
    return offsets
end

-- Search for methods and save offsets if not already saved
local offsets = loadOffsetsFromFile()
if not next(offsets) then
local Search = {
    [1] = {
        class = "PlayfabDataManager",  -- public int get_XP()
        method = "get_XP"
    },
    [2] = {
        class = "PlayfabDataManager",  -- public int get_Nitros()
        method = "get_Nitros"
    },
    [3] = {
        class = "PlayfabDataManager",  -- public void set_Gems(int value)
        method = "set_Gems"
    },
    [4] = {
        class = "PlayfabDataManager",  -- public void set_Coins(int value)
        method = "set_Coins"
    },
    [5] = {
        class = "PlayfabDataManager",  -- public void set_Tickets(int value)
        method = "set_Tickets"
    },
    [6] = {
        class = "CarDataManager",  -- public bool GetPartOpen(Car car, CarPart part, int index)
        method = "GetPartOpen"
    },
    [7] = {
        class = "CarDataManager",  -- public bool GetIsCarOpen(Car car)
        method = "GetIsCarOpen"
    },
    [8] = {
        class = "BuyButton",  -- private bool HasEnoughMoney()
        method = "HasEnoughMoney"
    }
}

    -- Search for each method in the search table
    for i, v in ipairs(Search) do
        gg.toast(string.format("Searching [%s :: %s] (%d/%d)", v.class, v.method, i, #Search))
        gg.sleep(1000)

        local results = GetIl2CppMethod(v.class, v.method)

        if #results > 0 then
            local offset = results[1].address - X_X[UwU]
            offsets[v.method] = string.format("0x%X", offset)
            _G[v.method] = offsets[v.method]
            gg.toast("✅ ["..v.method .. "] ✅")
        else
            offsets[v.method] = "nil"
            _G[v.method] = nil
            gg.toast("🚫 ["..v.method .. "] 🚫")
        end
        gg.sleep(1000)
    end

    saveOffsetsToFile(offsets)
else
-- If offsets are already saved, show them
local offsetDetails = {}
for method, offset in pairs(offsets) do
    table.insert(offsetDetails, string.format("%s: %s", method, offset))
    _G[method] = offset ~= "nil" and offset or nil
end

-- Generate the visual file structure
local relativePath = offsetFilePath:match("([^/]+/.+)")
local filePathStructure = "├─ 📁 " .. relativePath:gsub("/", "\n│ ├─ 📁 ")

local xXx = gg.alert(
    "🎲 Game : " .. APK ..
    "\n🪩 Offsets Saved File Found..!!" ..
    "\n" .. filePathStructure ..
    "\n" .. string.rep("─ ─", 7) ..  -- Adds a line 
    "\nOffsets : 📝\n" .. table.concat(offsetDetails, "\n"),
    "[ Start ]", nil, "[ Update ]"
)

if xXx == 3 then
    os.remove(offsetFilePath)
    goto GET_READY
end
end

-- Function to check if method offset is found, otherwise stop execution
function check(method)
    if not _G[method] then
        gg.alert("ERROR : [ "..method .. " ] Offset not found..!")
        gg.toast("⛔ This Hack Will Not Work ⛔")
        return nil
    end
    gg.toast("Hack [ON]")
    gg.sleep(1000)
    gg.toast("--( O_O )--")
    return true
end
gg.setVisible(true) -- Show Menu
-- ⬜⬜⬜⏪⬜⬜⬜⏩⬜⬜⬜
-- ⬜⬜⬜⏪⬜⬜⬜⏩⬜⬜⬜
-- O = offset (use Capital O)
-- X = value (use Capital X)
-- Arm() = Patch (Patch offset Value)
-- ============================
-- RecordOriginalValue(0x523368)  -- Record the original value
-- injectAssembly(0x522A24, false) -- false value
-- injectAssembly(0x2EB4F0, 999999999) -- Int Value
-- RevertValue(0x523368)  -- Revert the values
-- ⬜⬜⬜⏪⬜⬜⬜⏩⬜⬜⬜
-- ⬜⬜⬜⏪⬜⬜⬜⏩⬜⬜⬜

-- Hack A: Max XP
function A_ON()
   RecordOriginalValue(get_XP)
   injectAssembly(get_XP, 999999999)
   return true
end
function A_OFF()
   RevertValue(get_XP)
   return nil
end

-- Hack B: Infinite Nitro
function B_ON()
   RecordOriginalValue(get_Nitros)
   injectAssembly(get_Nitros, 999)
   return true
end
function B_OFF()
   RevertValue(get_Nitros)
   return nil
end

-- Hack C: Don't Spend Gems
function C_ON()
   RecordOriginalValue(set_Gems)
   injectAssembly(set_Gems, 1)
   return true
end
function C_OFF()
   RevertValue(set_Gems)
   return nil
end

-- Hack D: Don't Spend Coins
function D_ON()
   RecordOriginalValue(set_Coins)
   injectAssembly(set_Coins, 1)
   return true
end
function D_OFF()
   RevertValue(set_Coins)
   return nil
end

-- Hack E: Don't Spend Tickets
function E_ON()
   RecordOriginalValue(set_Tickets)
   injectAssembly(set_Tickets, 1)
   return true
end
function E_OFF()
   RevertValue(set_Tickets)
   return nil
end

-- Hack F: Unlock All Car Parts
function F_ON()
   RecordOriginalValue(GetPartOpen)
   injectAssembly(GetPartOpen, true)
   return true
end
function F_OFF()
   RevertValue(GetPartOpen)
   return nil
end

-- Hack G: Unlock All Cars
function G_ON()
   RecordOriginalValue(GetIsCarOpen)
   injectAssembly(GetIsCarOpen, true)
   return true
end
function G_OFF()
   RevertValue(GetIsCarOpen)
   return nil
end

-- Hack H: Unlimited Purchases
function H_ON()
   RecordOriginalValue(HasEnoughMoney)
   injectAssembly(HasEnoughMoney, true)
   return true
end
function H_OFF()
   RevertValue(HasEnoughMoney)
   return nil
end




-- Main Menu --
menuList = {
    "✅ Max XP",                -- 1
    "✅ Infinite Nitro",        -- 2
    "✅ Don't Spend Gems",     -- 3
    "✅ Don't Spend Coins",    -- 4
    "✅ Don't Spend Tickets",  -- 5
    "✅ Unlock All Car Parts", -- 6
    "✅ Unlock All Cars",      -- 7
    "✅ Unlimited Purchases",  -- 8
    "🚪 EXIT"                  -- 9
}

checkList = {
    nil, -- 1
    nil, -- 2
    nil, -- 3
    nil, -- 4
    nil, -- 5
    nil, -- 6
    nil, -- 7
    nil, -- 8
    nil  -- 9 (EXIT)
}
-- Done 😉
-- Menu Function
function menu()
    tsu = gg.multiChoice(menuList, checkList, "━━━━[ " .. APK .. " ]━━━━")
    if tsu == nil then return end

-- Main toggle logic
if tsu[1] ~= checkList[1] then
    if tsu[1] == true then
        if check("get_XP") then
            checkList[1] = A_ON()
        else gg.toast("$ ( X_X ) $") end
    else checkList[1] = A_OFF() end
end

if tsu[2] ~= checkList[2] then
    if tsu[2] == true then
        if check("get_Nitros") then
            checkList[2] = B_ON()
        else gg.toast("$ ( X_X ) $") end
    else checkList[2] = B_OFF() end
end

if tsu[3] ~= checkList[3] then
    if tsu[3] == true then
        if check("set_Gems") then
            checkList[3] = C_ON()
        else gg.toast("$ ( X_X ) $") end
    else checkList[3] = C_OFF() end
end

if tsu[4] ~= checkList[4] then
    if tsu[4] == true then
        if check("set_Coins") then
            checkList[4] = D_ON()
        else gg.toast("$ ( X_X ) $") end
    else checkList[4] = D_OFF() end
end

if tsu[5] ~= checkList[5] then
    if tsu[5] == true then
        if check("set_Tickets") then
            checkList[5] = E_ON()
        else gg.toast("$ ( X_X ) $") end
    else checkList[5] = E_OFF() end
end

if tsu[6] ~= checkList[6] then
    if tsu[6] == true then
        if check("GetPartOpen") then
            checkList[6] = F_ON()
        else gg.toast("$ ( X_X ) $") end
    else checkList[6] = F_OFF() end
end

if tsu[7] ~= checkList[7] then
    if tsu[7] == true then
        if check("GetIsCarOpen") then
            checkList[7] = G_ON()
        else gg.toast("$ ( X_X ) $") end
    else checkList[7] = G_OFF() end
end

if tsu[8] ~= checkList[8] then
    if tsu[8] == true then
        if check("HasEnoughMoney") then
            checkList[8] = H_ON()
        else gg.toast("$ ( X_X ) $") end
    else checkList[8] = H_OFF() end
end

-- Optional EXIT for 9th slot
if tsu[9] == true then
    Exit()
end
end
-- Function to apply ARM patches
function Arm()
    O = tonumber(O)
    if O == nil then 
       return
    end
    for UwU = 1, #(X_X) do
        Dick = nil
        Dick = {}

        if type(X) ~= "table" then
            Dick[1] = {}
            Dick[2] = {}
            Dick[1].address = X_X[UwU] + O
            Dick[1].flags = 4
            if X == 0 then
                Dick[1].value = 'h000080D2'
            elseif X == 1 then
                Dick[1].value = 'h200080D2'
            else
                Dick[1].value = X
            end
            Dick[2].address = X_X[UwU] + (O + 4)
            Dick[2].flags = 4
            Dick[2].value = 'D65F03C0h'
        else
            Fuck = 0
            for Bitch = 1, #(X) do
                Dick[Bitch] = {}
                Dick[Bitch].address = X_X[UwU] + O + Fuck
                Dick[Bitch].flags = 4
                Dick[Bitch].value = tostring(X[Bitch])
                Fuck = Fuck + 4
            end
        end

        gg.setValues(Dick)
    end
end
-- ⬜⬜⬜⏪⬜⬜⬜⏩⬜⬜⬜
-- ⬜⬜⬜⏪⬜⬜⬜⏩⬜⬜⬜
-- Exit function
function Exit()
  print("🔳🔳🔳🔳🔳🔳🔳🔳🔳🔳🔳🔳🔳🔳🔳")
  print("🔳⬛⬛⬛⬛⬛⬛⬛⬛⬛⬛⬛⬛⬛🔳")
  print("🔳⬛⬛⬛⬛⬛🟥🟥🟥⬛⬛⬛⬛⬛🔳")
  print("🔳⬛⬛⬛⬛🟥🟥🟥🟥🟥⬛⬛⬛⬛🔳")
  print("🔳⬛⬛⬛🟥🟥🟥🟦🟦🟦⬛⬛⬛⬛🔳")
  print("🔳⬛⬛⬛🟥🟥🟥🟦🟦🟦⬛⬛⬛⬛🔳")
  print("🔳⬛⬛⬛🟥🟥🟥🟥🟥🟥⬛⬛⬛⬛🔳")
  print("🔳⬛⬛⬛TG:@PainHub02⬛⬛⬛⬛🔳")
  print("🔳⬛⬛⬛⬛🟥🟥🟥🟥🟥⬛⬛⬛⬛🔳")
  print("🔳⬛⬛⬛⬛🟥🟥⬛🟥🟥⬛⬛⬛⬛🔳")
  print("🔳⬛⬛⬛⬛🟥🟥⬛🟥🟥⬛⬛⬛⬛🔳")
  print("🔳⬛⬛⬛Script By DarkWolf⬛⬛⬛🔳")
  print("🔳🔳🔳🔳🔳🔳🔳🔳🔳🔳🔳🔳🔳🔳🔳")
  os.exit()
end

-- Menu loop function
while true do
    if gg.isVisible(true) then
        gg.setVisible(false)
        menu()
    end
end