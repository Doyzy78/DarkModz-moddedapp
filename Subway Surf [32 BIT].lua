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
        class = "ScoreMultiplierManager",  -- public class ScoreMultiplierManager
        method = "get_BaseMultiplierSum"   -- public int get_BaseMultiplierSum()
    },
    [2] = {
        class = "AssemblyIngredientPickup",  -- public class AssemblyIngredientPickup
        method = "OnPickedUp"                -- public void OnPickedUp()
    },
    [3] = {
        class = "CharacterCollision",
        method = "OnControllerColliderHit"
    },
    [4] = {
        class = "CharacterMotorAbilities",
        method = "get_MaxSpeedAbilities"
    },
    [5] = {
        class = "MainPowerSystem",
        method = "UpdatePowers"
    },
    [6] = {
        class = "CharacterController",
        method = "get_detectCollisions"
    },
    [7] = {
        class = "CharacterCollision",
        method = "get_ColliderEnable"
    },
    [8] = {
        class = "CharacterGraphicsController",
        method = "HandleOnFlightStarted"
    },
    [9] = {
        class = "WalletModel",
        method = "GetCurrency"
    },
    [10] = {
        class = "WalletModel",
        method = "CanAfford"
    },
    [11] = {
        class = "Currency",
        method = "get_IsIAP"
    },
    [12] = {
        class = "Achievement",
        method = "get_IsTierCompleted"
    },
    [13] = {
        class = "EndRunCoinWidget",
        method = "get_OwnsCoinDoubler"
    },
    [14] = {
        class = "CameraGroundedModifier",
        method = "Apply"
    },
    [15] = {
        class = "CharacterMotor",
        method = "NotifySideImpact"
    },
    [16] = {
        class = "CharacterMotor",
        method = "CheckSideImpact"
    },
    [17] = {
        class = "CharacterStumble",
        method = "Stumble"
    },
    [18] = {
        class = "CharacterMotor",
        method = "CheckFrontalImpact"
    },
    [19] = {
        class = "CharacterStumble",
        method = "Kill"
    },
    [20] = {
        class = "CharacterMotor",
        method = "ApplyGravity"
    },
    [21] = {
        class = "CharacterMotor",
        method = "UpdateMovement"
    },
    [22] = {
        class = "CharacterMotor",
        method = "get_CanJump"
    },
    [23] = {
        class = "CharacterMotorAbilities",
        method = "get_LaneChangeDuration"
    },
    [24] = {
        class = "AvailableCharacter",
        method = "IsOutfitLocked"
    },
    [25] = {
        class = "AvailableCharacter",
        method = "get_IsOwned"
    },
    [26] = {
        class = "AvailableCharacter",
        method = "IsSkinOwned"
    },
    [27] = {
        class = "AvailableCharacter",
        method = "IsOutfitOwned"
    },
    [28] = {
        class = "CharacterMotor",
        method = "Teleport"
    },
    [29] = {
        class = "CharacterPropsController",
        method = "ShowSneakers"
    },
    [30] = {
        class = "CharacterPropsController",
        method = "ShowFlight"
    },
    [31] = {
        class = "CharacterPropsController",
        method = "ShowPogostick"
    },
    [32] = {
        class = "CharacterPropsController",
        method = "ShowMagnet"
    },
    [33] = {
        class = "CharacterPropsController",
        method = "ShowHoverboard"
    },
    [34] = {
        class = "CharacterMotorAbilities",
        method = "get_MinSpeedAbilities"
    },
    [35] = {
        class = "CharacterMotorAbilities",
        method = "get_JumpHeight"
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


-- Hack 1: Infinite Stars
function A_ON()
   RecordOriginalValue(get_BaseMultiplierSum)
   injectAssembly(get_BaseMultiplierSum, 999999999)
   return true
end
function A_OFF()
   RevertValue(get_BaseMultiplierSum)
   return nil
end

-- Hack 2: Remove Coin Pickup
function B_ON()
   RecordOriginalValue(OnPickedUp)
   injectAssembly(OnPickedUp, false)
   return true
end
function B_OFF()
   RevertValue(OnPickedUp)
   return nil
end

-- Hack 3: Fly Mode
function C_ON()
   RecordOriginalValue(OnControllerColliderHit)
   injectAssembly(OnControllerColliderHit, false)
   return true
end
function C_OFF()
   RevertValue(OnControllerColliderHit)
   return nil
end

-- Hack 4: Run Fast
function D_ON()
   RecordOriginalValue(get_MaxSpeedAbilities)
   injectAssembly(get_MaxSpeedAbilities, 7000)
   return true
end
function D_OFF()
   RevertValue(get_MaxSpeedAbilities)
   return nil
end

-- Hack 5: Unlimited Power
function E_ON()
   RecordOriginalValue(UpdatePowers)
   injectAssembly(UpdatePowers, false)
   return true
end
function E_OFF()
   RevertValue(UpdatePowers)
   return nil
end

-- Hack 6: Pass Through Trains
function F_ON()
   RecordOriginalValue(get_detectCollisions)
   injectAssembly(get_detectCollisions, false)
   return true
end
function F_OFF()
   RevertValue(get_detectCollisions)
   return nil
end

-- Hack 7: Pass Through Trains (2)
function G_ON()
   RecordOriginalValue(get_ColliderEnable)
   injectAssembly(get_ColliderEnable, false)
   return true
end
function G_OFF()
   RevertValue(get_ColliderEnable)
   return nil
end

-- Hack 8: Walk While Flying
function H_ON()
   RecordOriginalValue(HandleOnFlightStarted)
   injectAssembly(HandleOnFlightStarted, false)
   return true
end
function H_OFF()
   RevertValue(HandleOnFlightStarted)
   return nil
end

-- Hack 9: Everything Unlimited
function I_ON()
   RecordOriginalValue(GetCurrency)
   injectAssembly(GetCurrency, 999999999)
   return true
end
function I_OFF()
   RevertValue(GetCurrency)
   return nil
end

-- Hack 10: Internal Purchases
function J_ON()
   RecordOriginalValue(CanAfford)
   injectAssembly(CanAfford, true)
   return true
end
function J_OFF()
   RevertValue(CanAfford)
   return nil
end

-- Hack 11: Free Purchases
function K_ON()
   RecordOriginalValue(get_IsIAP)
   injectAssembly(get_IsIAP, false)
   return true
end
function K_OFF()
   RevertValue(get_IsIAP)
   return nil
end

-- Hack 12: Unlock Achievements
function L_ON()
   RecordOriginalValue(get_IsTierCompleted)
   injectAssembly(get_IsTierCompleted, true)
   return true
end
function L_OFF()
   RevertValue(get_IsTierCompleted)
   return nil
end

-- Hack 13: Double Coins
function M_ON()
   RecordOriginalValue(get_OwnsCoinDoubler)
   injectAssembly(get_OwnsCoinDoubler, true)
   return true
end
function M_OFF()
   RevertValue(get_OwnsCoinDoubler)
   return nil
end

-- Hack 14: Follow Camera
function N_ON()
   RecordOriginalValue(Apply)
   injectAssembly(Apply, false)
   return true
end
function N_OFF()
   RevertValue(Apply)
   return nil
end

-- Hack 15: No Impact
function O_ON()
   RecordOriginalValue(NotifySideImpact)
   injectAssembly(NotifySideImpact, false)
   return true
end
function O_OFF()
   RevertValue(NotifySideImpact)
   return nil
end

-- Hack 16: No Impact (2)
function P_ON()
   RecordOriginalValue(CheckSideImpact)
   injectAssembly(CheckSideImpact, false)
   return true
end
function P_OFF()
   RevertValue(CheckSideImpact)
   return nil
end

-- Hack 17: No Impact (3)
function Q_ON()
   RecordOriginalValue(Stumble)
   injectAssembly(Stumble, false)
   return true
end
function Q_OFF()
   RevertValue(Stumble)
   return nil
end

-- Hack 18: Immortal Mode
function R_ON()
   RecordOriginalValue(CheckFrontalImpact)
   injectAssembly(CheckFrontalImpact, false)
   return true
end
function R_OFF()
   RevertValue(CheckFrontalImpact)
   return nil
end

-- Hack 19: Immortal Mode (2)
function S_ON()
   RecordOriginalValue(Kill)
   injectAssembly(Kill, false)
   return true
end
function S_OFF()
   RevertValue(Kill)
   return nil
end

-- Hack 20: Gravity Off
function T_ON()
   RecordOriginalValue(ApplyGravity)
   injectAssembly(ApplyGravity, false)
   return true
end
function T_OFF()
   RevertValue(ApplyGravity)
   return nil
end

-- Hack 21: Freeze Screen
function U_ON()
   RecordOriginalValue(UpdateMovement)
   injectAssembly(UpdateMovement, false)
   return true
end
function U_OFF()
   RevertValue(UpdateMovement)
   return nil
end

-- Hack 22: Infinite Jump
function V_ON()
   RecordOriginalValue(get_CanJump)
   injectAssembly(get_CanJump, true)
   return true
end
function V_OFF()
   RevertValue(get_CanJump)
   return nil
end

-- Hack 23: Fast Lane Change
function W_ON()
   RecordOriginalValue(get_LaneChangeDuration)
   injectAssembly(get_LaneChangeDuration, 1)
   return true
end
function W_OFF()
   RevertValue(get_LaneChangeDuration)
   return nil
end

-- Hack 24: Unlock Characters
function X_ON()
   RecordOriginalValue(IsOutfitLocked)
   injectAssembly(IsOutfitLocked, false)
   return true
end
function X_OFF()
   RevertValue(IsOutfitLocked)
   return nil
end

-- Hack 25: Unlock Characters (2)
function Y_ON()
   RecordOriginalValue(get_IsOwned)
   injectAssembly(get_IsOwned, true)
   return true
end
function Y_OFF()
   RevertValue(get_IsOwned)
   return nil
end

-- Hack 26: Unlock Characters (3)
function Z_ON()
   RecordOriginalValue(IsSkinOwned)
   injectAssembly(IsSkinOwned, true)
   return true
end
function Z_OFF()
   RevertValue(IsSkinOwned)
   return nil
end

-- Hack 27: Unlock Characters (4)
function AA_ON()
   RecordOriginalValue(IsOutfitOwned)
   injectAssembly(IsOutfitOwned, true)
   return true
end
function AA_OFF()
   RevertValue(IsOutfitOwned)
   return nil
end

-- Hack 28: Teleport
function AB_ON()
   RecordOriginalValue(Teleport)
   injectAssembly(Teleport, false)
   return true
end
function AB_OFF()
   RevertValue(Teleport)
   return nil
end

-- Hack 29: Invisible Super Sneakers
function AC_ON()
   RecordOriginalValue(ShowSneakers)
   injectAssembly(ShowSneakers, false)
   return true
end
function AC_OFF()
   RevertValue(ShowSneakers)
   return nil
end

-- Hack 30: Invisible Jetpack
function AD_ON()
   RecordOriginalValue(ShowFlight)
   injectAssembly(ShowFlight, false)
   return true
end
function AD_OFF()
   RevertValue(ShowFlight)
   return nil
end

-- Hack 31: Invisible Pogo Stick
function AE_ON()
   RecordOriginalValue(ShowPogostick)
   injectAssembly(ShowPogostick, false)
   return true
end
function AE_OFF()
   RevertValue(ShowPogostick)
   return nil
end

-- Hack 32: Invisible Magnet
function AF_ON()
   RecordOriginalValue(ShowMagnet)
   injectAssembly(ShowMagnet, false)
   return true
end
function AF_OFF()
   RevertValue(ShowMagnet)
   return nil
end

-- Hack 33: Invisible Hoverboard
function AG_ON()
   RecordOriginalValue(ShowHoverboard)
   injectAssembly(ShowHoverboard, false)
   return true
end
function AG_OFF()
   RevertValue(ShowHoverboard)
   return nil
end

-- Hack 34: Min Lane Change Speed
function AH_ON()
   RecordOriginalValue(get_MinSpeedAbilities)
   injectAssembly(get_MinSpeedAbilities, 1000)
   return true
end
function AH_OFF()
   RevertValue(get_MinSpeedAbilities)
   return nil
end

-- Hack 35: High Jump Boost
function AI_ON()
   RecordOriginalValue(get_JumpHeight)
   injectAssembly(get_JumpHeight, 200)
   return true
end
function AI_OFF()
   RevertValue(get_JumpHeight)
   return nil
end



-- Main Menu --
menuList = {
    "Infinite Stars",                  -- 1
    "Remove Coin Pickup",             -- 2
    "Fly Mode",                       -- 3
    "Run Fast",                       -- 4
    "Unlimited Power",               -- 5
    "Pass Through Trains",           -- 6
    "Pass Through Trains (2)",       -- 7
    "Walk While Flying",             -- 8
    "Everything Unlimited",          -- 9
    "Internal Purchases",            -- 10
    "Free Purchases",                -- 11
    "Unlock Achievements",           -- 12
    "Double Coins",                  -- 13
    "Follow Camera",                 -- 14
    "No Impact",                     -- 15
    "No Impact (2)",                 -- 16
    "No Impact (3)",                 -- 17
    "Immortal Mode",                 -- 18
    "Immortal Mode (2)",             -- 19
    "Gravity Off",                   -- 20
    "Freeze Screen",                 -- 21
    "Infinite Jump",                 -- 22
    "Fast Lane Change",              -- 23
    "Unlock Characters",             -- 24
    "Unlock Characters (2)",         -- 25
    "Unlock Characters (3)",         -- 26
    "Unlock Characters (4)",         -- 27
    "Teleport",                      -- 28
    "Invisible Super Sneakers",      -- 29
    "Invisible Jetpack",             -- 30
    "Invisible Pogo Stick",          -- 31
    "Invisible Magnet",              -- 32
    "Invisible Hoverboard",          -- 33
    "Min Lane Change Speed",         -- 34
    "High Jump Boost",               -- 35
    "EXIT",                          -- 36
}

checkList = {
    nil,  -- 1
    nil,  -- 2
    nil,  -- 3
    nil,  -- 4
    nil,  -- 5
    nil,  -- 6
    nil,  -- 7
    nil,  -- 8
    nil,  -- 9
    nil,  -- 10
    nil,  -- 11
    nil,  -- 12
    nil,  -- 13
    nil,  -- 14
    nil,  -- 15
    nil,  -- 16
    nil,  -- 17
    nil,  -- 18
    nil,  -- 19
    nil,  -- 20
    nil,  -- 21
    nil,  -- 22
    nil,  -- 23
    nil,  -- 24
    nil,  -- 25
    nil,  -- 26
    nil,  -- 27
    nil,  -- 28
    nil,  -- 29
    nil,  -- 30
    nil,  -- 31
    nil,  -- 32
    nil,  -- 33
    nil,  -- 34
    nil,  -- 35
    nil,  -- 36 (EXIT)
}

-- Done 😉
-- Menu Function
function menu()
    tsu = gg.multiChoice(menuList, checkList, "━━━━[ " .. APK .. " ]━━━━")
    if tsu == nil then return end

    if tsu[1] ~= checkList[1] then
        if tsu[1] == true then
            if check("get_BaseMultiplierSum") then
                checkList[1] = A_ON()
            else gg.toast("$ ( X_X ) $") end
        else checkList[1] = A_OFF() end
    end

    if tsu[2] ~= checkList[2] then
        if tsu[2] == true then
            if check("OnPickedUp") then
                checkList[2] = B_ON()
            else gg.toast("$ ( X_X ) $") end
        else checkList[2] = B_OFF() end
    end

    if tsu[3] ~= checkList[3] then
        if tsu[3] == true then
            if check("OnControllerColliderHit") then
                checkList[3] = C_ON()
            else gg.toast("$ ( X_X ) $") end
        else checkList[3] = C_OFF() end
    end

    if tsu[4] ~= checkList[4] then
        if tsu[4] == true then
            if check("get_MaxSpeedAbilities") then
                checkList[4] = D_ON()
            else gg.toast("$ ( X_X ) $") end
        else checkList[4] = D_OFF() end
    end

    if tsu[5] ~= checkList[5] then
        if tsu[5] == true then
            if check("UpdatePowers") then
                checkList[5] = E_ON()
            else gg.toast("$ ( X_X ) $") end
        else checkList[5] = E_OFF() end
    end

    if tsu[6] ~= checkList[6] then
        if tsu[6] == true then
            if check("get_detectCollisions") then
                checkList[6] = F_ON()
            else gg.toast("$ ( X_X ) $") end
        else checkList[6] = F_OFF() end
    end

    if tsu[7] ~= checkList[7] then
        if tsu[7] == true then
            if check("get_ColliderEnable") then
                checkList[7] = G_ON()
            else gg.toast("$ ( X_X ) $") end
        else checkList[7] = G_OFF() end
    end

    if tsu[8] ~= checkList[8] then
        if tsu[8] == true then
            if check("HandleOnFlightStarted") then
                checkList[8] = H_ON()
            else gg.toast("$ ( X_X ) $") end
        else checkList[8] = H_OFF() end
    end

    if tsu[9] ~= checkList[9] then
        if tsu[9] == true then
            if check("GetCurrency") then
                checkList[9] = I_ON()
            else gg.toast("$ ( X_X ) $") end
        else checkList[9] = I_OFF() end
    end

    if tsu[10] ~= checkList[10] then
        if tsu[10] == true then
            if check("CanAfford") then
                checkList[10] = J_ON()
            else gg.toast("$ ( X_X ) $") end
        else checkList[10] = J_OFF() end
    end

    if tsu[11] ~= checkList[11] then
        if tsu[11] == true then
            if check("get_IsIAP") then
                checkList[11] = K_ON()
            else gg.toast("$ ( X_X ) $") end
        else checkList[11] = K_OFF() end
    end

    if tsu[12] ~= checkList[12] then
        if tsu[12] == true then
            if check("get_IsTierCompleted") then
                checkList[12] = L_ON()
            else gg.toast("$ ( X_X ) $") end
        else checkList[12] = L_OFF() end
    end

    if tsu[13] ~= checkList[13] then
        if tsu[13] == true then
            if check("get_OwnsCoinDoubler") then
                checkList[13] = M_ON()
            else gg.toast("$ ( X_X ) $") end
        else checkList[13] = M_OFF() end
    end

    if tsu[14] ~= checkList[14] then
        if tsu[14] == true then
            if check("Apply") then
                checkList[14] = N_ON()
            else gg.toast("$ ( X_X ) $") end
        else checkList[14] = N_OFF() end
    end

    if tsu[15] ~= checkList[15] then
        if tsu[15] == true then
            if check("NotifySideImpact") then
                checkList[15] = O_ON()
            else gg.toast("$ ( X_X ) $") end
        else checkList[15] = O_OFF() end
    end

    if tsu[16] ~= checkList[16] then
        if tsu[16] == true then
            if check("CheckSideImpact") then
                checkList[16] = P_ON()
            else gg.toast("$ ( X_X ) $") end
        else checkList[16] = P_OFF() end
    end

    if tsu[17] ~= checkList[17] then
        if tsu[17] == true then
            if check("Stumble") then
                checkList[17] = Q_ON()
            else gg.toast("$ ( X_X ) $") end
        else checkList[17] = Q_OFF() end
    end

    if tsu[18] ~= checkList[18] then
        if tsu[18] == true then
            if check("CheckFrontalImpact") then
                checkList[18] = R_ON()
            else gg.toast("$ ( X_X ) $") end
        else checkList[18] = R_OFF() end
    end

    if tsu[19] ~= checkList[19] then
        if tsu[19] == true then
            if check("Kill") then
                checkList[19] = S_ON()
            else gg.toast("$ ( X_X ) $") end
        else checkList[19] = S_OFF() end
    end

    if tsu[20] ~= checkList[20] then
        if tsu[20] == true then
            if check("ApplyGravity") then
                checkList[20] = T_ON()
            else gg.toast("$ ( X_X ) $") end
        else checkList[20] = T_OFF() end
    end

    if tsu[21] ~= checkList[21] then
        if tsu[21] == true then
            if check("UpdateMovement") then
                checkList[21] = U_ON()
            else gg.toast("$ ( X_X ) $") end
        else checkList[21] = U_OFF() end
    end

    if tsu[22] ~= checkList[22] then
        if tsu[22] == true then
            if check("get_CanJump") then
                checkList[22] = V_ON()
            else gg.toast("$ ( X_X ) $") end
        else checkList[22] = V_OFF() end
    end

    if tsu[23] ~= checkList[23] then
        if tsu[23] == true then
            if check("get_LaneChangeDuration") then
                checkList[23] = W_ON()
            else gg.toast("$ ( X_X ) $") end
        else checkList[23] = W_OFF() end
    end

    if tsu[24] ~= checkList[24] then
        if tsu[24] == true then
            if check("IsOutfitLocked") then
                checkList[24] = X_ON()
            else gg.toast("$ ( X_X ) $") end
        else checkList[24] = X_OFF() end
    end

    if tsu[25] ~= checkList[25] then
        if tsu[25] == true then
            if check("get_IsOwned") then
                checkList[25] = Y_ON()
            else gg.toast("$ ( X_X ) $") end
        else checkList[25] = Y_OFF() end
    end

    if tsu[26] ~= checkList[26] then
        if tsu[26] == true then
            if check("IsSkinOwned") then
                checkList[26] = Z_ON()
            else gg.toast("$ ( X_X ) $") end
        else checkList[26] = Z_OFF() end
    end

    if tsu[27] ~= checkList[27] then
        if tsu[27] == true then
            if check("IsOutfitOwned") then
                checkList[27] = AA_ON()
            else gg.toast("$ ( X_X ) $") end
        else checkList[27] = AA_OFF() end
    end

    if tsu[28] ~= checkList[28] then
        if tsu[28] == true then
            if check("Teleport") then
                checkList[28] = AB_ON()
            else gg.toast("$ ( X_X ) $") end
        else checkList[28] = AB_OFF() end
    end

    if tsu[29] ~= checkList[29] then
        if tsu[29] == true then
            if check("ShowSneakers") then
                checkList[29] = AC_ON()
            else gg.toast("$ ( X_X ) $") end
        else checkList[29] = AC_OFF() end
    end

    if tsu[30] ~= checkList[30] then
        if tsu[30] == true then
            if check("ShowFlight") then
                checkList[30] = AD_ON()
            else gg.toast("$ ( X_X ) $") end
        else checkList[30] = AD_OFF() end
    end

    if tsu[31] ~= checkList[31] then
        if tsu[31] == true then
            if check("ShowPogostick") then
                checkList[31] = AE_ON()
            else gg.toast("$ ( X_X ) $") end
        else checkList[31] = AE_OFF() end
    end

    if tsu[32] ~= checkList[32] then
        if tsu[32] == true then
            if check("ShowMagnet") then
                checkList[32] = AF_ON()
            else gg.toast("$ ( X_X ) $") end
        else checkList[32] = AF_OFF() end
    end

    if tsu[33] ~= checkList[33] then
        if tsu[33] == true then
            if check("ShowHoverboard") then
                checkList[33] = AG_ON()
            else gg.toast("$ ( X_X ) $") end
        else checkList[33] = AG_OFF() end
    end

    if tsu[34] ~= checkList[34] then
        if tsu[34] == true then
            if check("get_MinSpeedAbilities") then
                checkList[34] = AH_ON()
            else gg.toast("$ ( X_X ) $") end
        else checkList[34] = AH_OFF() end
    end

    if tsu[35] ~= checkList[35] then
        if tsu[35] == true then
            if check("get_JumpHeight") then
                checkList[35] = AI_ON()
            else gg.toast("$ ( X_X ) $") end
        else checkList[35] = AI_OFF() end
    end

    -- EXIT
    if tsu[36] == true then
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