dofile("common.inc")
dofile("settings.inc")
dofile("screen_reader_common.inc")
local json = dofile("json.lua")
local http = require("socket.http");


TEST = false

NEARBY_TEXT = "nearby"
UNRECOGNIZE_TEXT = "recognize"

NEARBY_DISITANCE = 10
ONTOP_DISTANCE = 1

MIN_ORE_ID = -1
ORES = {
    [-1] = {
        name = "sand",
        unrecognized = -1,
        recognized = -1,
    },
    [0] = {
        name = "Copper",
        unrecognized = -1,
        recognized = 0,
    },
    {
        name = "Iron",
        unrecognized = 1,
        recognized = 2,
    },
    {
        name = "Tin",
        unrecognized = 3,
        recognized = 4,
    },
    {
        name = "Aluminum",
        unrecognized = 2,
        recognized = 5,
    },
    {
        name = "Lead",
        unrecognized = 3,
        recognized = 5,
    },
    {
        name = "Zinc",
        unrecognized = 3,
        recognized = 6,
    },
    {
        name = "Titanium",
        unrecognized = 6,
        recognized = 10,
    },
    {
        name = "Tungsten",
        unrecognized = 4,
        recognized = 8,
    },
    {
        name = "Antimony",
        unrecognized = 7,
        recognized = 13,
    },
    {
        name = "Lithium",
        unrecognized = 7,
        recognized = 13,
    },
    {
        name = "Silver",
        unrecognized = 7,
        recognized = 15,
    },
    {
        name = "Strontium",
        unrecognized = 7,
        recognized = 14,
    },
    {
        name = "Magnesium",
        unrecognized = 8,
        recognized = 16,
    },
    {
        name = "Platinum",
        unrecognized = 13,
        recognized = 24,
    },
    {
        name = "Gold",
        unrecognized = 15,
        recognized = 24,
    },

}

RED = 0xFF2020ff
BLACK = 0x000000ff
WHITE = 0xFFFFFFff

DOWSING_TABLE_FILENAME = "dowse_table.txt"
DOWSING_CSV_FILENAME = "dowse_csv.txt"
DOWSING_JSON_FILENAME = "dowse_json.txt"
SOUND_FILENAME = "cheer.wav"

UPDATE_URL_FORMAT_STRING = "http://atitd.unsanctioned.net/dowser_test/changecell?x=%d&y=%d&val=%d&perception=%d"

MIN_PERCEPTION=0
MAX_PERCEPTION=25


askText = [[If you are using automove make sure the chat is minimized / not selected.
Make sure that the main chat tab is open as the macro logs dowses by reading the main chat tab.
Because of this however you can use other chat tabs and occasionally go back to the main chat tab, scroll through all the missed results and the macro should see and log them all.
Find the outputted data in C:\Games\Automato\games\ATITD\scripts in the files dowse_csv.txt and dowse_table.txt]]

NUM_STEPS = 5

added_this_run = 0
latest_found = "Nothing found so far."

dowsing_table = {}

-- Script start
function doit()
    config = getUserParams()
    askForWindow(askText)
    runMacro()
end

function setupTables()
    _, dowsing_table = deserialize(DOWSING_TABLE_FILENAME)
    dowsing_table = dowsing_table or {}

    unrecognized_table = {}
    for p=MIN_PERCEPTION, MAX_PERCEPTION do
        local max_unrecognized = MIN_PERCEPTION-1
        local ore_id = MIN_ORE_ID
        for i=MIN_ORE_ID, #ORES do
            local unrecognized = ORES[i].unrecognized
            if unrecognized <= p and unrecognized > max_unrecognized then
                max_unrecognized = unrecognized
                ore_id = i
            end
        end
        unrecognized_table[p] = ore_id
        if TEST then
            lsPrintln(p .. " = " .. ORES[ore_id].name)
        end
    end
end

function runMacro()
    setupTables()

    local timer = lsGetTimer()

    local is_done = false
    while not is_done do
        checkBreak()

        -- Slow the number of updates to reduce client lag whilst leaving the Automato UI responsive
        local now = lsGetTimer()
        if TEST or now - timer > 500 then
            timer = now
            srReadScreen()
            tryDowse()
            updateLog()
        end

        if lsButtonText(lsScreenX - 110, lsScreenY - 30, z, 100, 0xFFFFFFff, "End script") then
            error "Clicked End Script button";
        end

        lsPrintWrapped(10, 10, z, lsScreenX - 10, 1.0, 1.0, 0xFFFFFFff,
            added_this_run .. " entries logged this run.\n" .. latest_found)

        lsDoFrame()
        lsSleep(50)
        if TEST then
            is_done = true
        end
    end
end

function tryDowse()
    local dowse_icon = srFindImage("dowse.png");
    if dowse_icon then
        safeClick(dowse_icon[0]+5,dowse_icon[1],1);
        lsSleep(100);
        if config.auto_move then
            for _=1,config.walk_distance do
                srUpArrow()
                lsSleep(100);
            end
        end
    end
end

function updateLog()
    local chat = TEST and testChat() or getChatText()
    local changed = false
    for line=1, #chat do
        local line_text = chat[line][2]
        local result = parseChatLine(line_text)
        if result then
            if updateTableEntry(result) then
                if result.ore_id >= 0 then
                    if config.play_sound then
                        lsPlaySound(SOUND_FILENAME);
                    end
                    latest_found = "\n Found " .. result.match .. " at " .. result.index .. "! \n" .. latest_found
                end
                dowsing_table[result.index] = result
                updateServer(result)
                added_this_run = added_this_run + 1
                changed = true
            end
        end
    end
    if changed then
        writeLog()
    end
end

function testChat()
    local test_chat = {
        {[2]=UNRECOGNIZE_TEXT .. " -2 -2."}
    }
    for i=MIN_ORE_ID, #ORES do
        table.insert(test_chat, {[2]=ORES[i].name .. " " .. i .. " " .. i .. "."})
    end
    return test_chat
end

function updateTableEntry(result)
    local ore = ORES[result.ore_id]
    if not result.unrecognized and ore.recognized > result.perception then
        lsPrintln("ERROR:" .. ore.name .. " recognized at a lower perception than required! " .. ore.recognized .. " > " .. result.perception)
        return false
    end
    return not dowsing_table[result.index]
end

function updateServer(result)
    local request_url = UPDATE_URL_FORMAT_STRING:format(result.x,result.y,result.ore_id,result.perception)
    local res = http.request(request_url);
    lsPrintln("request_url = " .. request_url .. " = " .. res)
end

function parseChatLine(line_text)
    local ore_id
    local match
    for i=MIN_ORE_ID, #ORES do
        match = string.match(line_text, ORES[i].name)
        if match then
            ore_id = i
            break
        end
    end
    local nearby = string.match(line_text, NEARBY_TEXT)
    local unrecognized = string.match(line_text, UNRECOGNIZE_TEXT)

    local result
    local x,y = string.match(line_text, "(%-?[%d ]+) (%-?[%d ]+).")
    if (match or unrecognized) and x and y  then
        y = y:gsub(" ", "")
        x = x:gsub(" ", "")
        y = tonumber(y)
        x = tonumber(x)
        if x and y then
            -- Sometimes the x and y coords have a space between the - symbol and the rest of the number. Strip it out.
            if unrecognized then
                if config.perception > 0 then
                    ore_id = unrecognized_table[config.perception]
                else
                    lsPrintln("ERROR: unrecognized vein with 0 perception!")
                    return nil
                end
            end
            result = {index=x .. "," .. y, x=x, y=y, ore_id=ore_id, nearby=nearby, unrecognized=unrecognized, perception=config.perception, match=ORES[ore_id].name }
        end
    end
    return result
end

function writeLog()
    local csv = createCSV()
    if not TEST then
        serialize(csv, DOWSING_CSV_FILENAME)
        serialize(dowsing_table, DOWSING_TABLE_FILENAME)
        serialize(json.encode(dowsing_table), DOWSING_JSON_FILENAME)
    end
end


function createCSV()
    local csv = ""
    for index,result in pairs(dowsing_table) do
        csv = csv .. index .. "," .. result.perception .. "," .. result.ore_id .. "\n"
    end
    return csv
end

-- Hacky modified serialize.lua
function serialize(o, filename)
    local outputFile = io.open("scripts/" .. filename,"w");
    if type(o) == "table" then outputFile:write("return\n"); end
    serializeInternal(o,outputFile);
    outputFile:close();
end

function deserialize(filename)
    filename = "scripts/" .. filename

    if(pcall(dofile,filename)) then
        return true, dofile(filename);
    else
        return false, nil;
    end
end


function serializeInternal(o,outputFile,indentStr,format_string)
    if(not indentStr) then
        indentStr = "";
    end
    if type(o) == "number" then
        outputFile:write(o);
    elseif type(o) == "string" then
        if format_string then
            o = string.format("%q", o)
        end
        outputFile:write(o);
    elseif type(o) == "boolean" then
        if(o) then
            outputFile:write("true");
        else
            outputFile:write("false");
        end
    elseif type(o) == "table" then
        outputFile:write(indentStr .. "{\n");
        for k,v in pairs(o) do
            if(type(k) == "number") then
                outputFile:write(indentStr .. "\t[" .. k .. "] = ");
            else
                outputFile:write(indentStr .. "\t[" .. string.format("%q", k) .. "] = ");
            end
            if(type(v) == "table") then
                outputFile:write("\n");
            end
            serializeInternal(v,outputFile,indentStr .. "\t",true);
            if(type(v) == "table") then
                outputFile:write(indentStr .. "\t,\n");
            else
                outputFile:write(",\n");
            end
        end
        outputFile:write(indentStr .. "}\n");
    else
        error("cannot serialize a " .. type(o));
    end
end


-- Used to place gui elements sucessively.
current_y = 0
-- How far off the left hand side to place gui elements.
X_PADDING = 5

function getUserParams()
    local is_done = false
    local config = {play_sound=readSetting("play_sound",true), walk_distance=readSetting("walk_distance",10),
        auto_move=readSetting("auto_move",true), perception=readSetting("perception",0), distance_column=readSetting("distance_column",false)}
    while not is_done do
        current_y = 10

        config.auto_move = drawCheckBox("Auto move using the arrow keys?", config.auto_move)
        config.walk_distance = drawNumberEditBox("walk_distance", "Distance to walk after each dowse?", config.walk_distance)
        config.perception = drawNumberEditBox("perception", "What is your perception?", config.perception)
        config.play_sound = drawCheckBox("Play sound on metal find?", config.play_sound)
        config.distance_column = drawCheckBox("Generate distance column?", config.distance_column)
        drawTextUsingCurrent("Distance = 10 for a dowse which is nearby the vein, 1 for a dowse ontop of vein.", WHITE)
        got_user_params = true
        is_done = true
        for k,v in pairs(config) do
            is_done = is_done and v
        end
        is_done = is_done and drawBottomButton(lsScreenX - 5, "Next step")

        if drawBottomButton(110, "Exit Script") then
            error "Script exited by user"
        end

        lsDoFrame()
        lsSleep(10)
    end

    config.perception = config.perception < MIN_PERCEPTION and MIN_PERCEPTION or config.perception
    config.perception = config.perception > MAX_PERCEPTION and MAX_PERCEPTION or config.perception
    writeSetting("play_sound",config.play_sound)
    writeSetting("walk_distance",config.walk_distance)
    writeSetting("auto_move",config.auto_move)
    writeSetting("distance_column",config.distance_column)
    writeSetting("perception",config.perception)
    return config
end

function drawCheckBox(text, default)
    local result = lsCheckBox(X_PADDING, current_y, 10, WHITE, text, default)
    current_y = current_y + 30
    return result
end

function drawNumberEditBox(key, text, default)
    return drawEditBox(key, text, default, true)
end

function drawEditBox(key, text, default, validateNumber)
    drawTextUsingCurrent(text, WHITE)
    local width = validateNumber and 50 or 200
    local height = 30
    local _, result = lsEditBox(key, X_PADDING, current_y, 0, width, height, 1.0, 1.0, BLACK, default)
    if validateNumber then
        result = tonumber(result)
    elseif result == "" then
        result = false
    end
    if not result then
        local error = validateNumber and "Please enter a valid number!" or "Enter text!"
        drawText(error, RED, X_PADDING + width + 5, current_y + 5)
        result = false
    end
    current_y = current_y + 35
    return result
end

function drawTextUsingCurrent(text, colour)
    drawText(text, colour, X_PADDING, current_y)
    current_y = current_y + 20
end
function drawText(text, colour, x, y)
    lsPrint(x, y, 10, 0.7, 0.7, colour, text)
end

function drawWrappedText(text, colour, x, y)
    lsPrintWrapped(x, y, 10, lsScreenX-10, 0.6, 0.6, colour, text)
end

function drawBottomButton(xOffset, text)
    return lsButtonText(lsScreenX - xOffset, lsScreenY - 30, z, 100, WHITE, text)
end


