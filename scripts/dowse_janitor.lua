dofile("common.inc")
dofile("settings.inc")
dofile("screen_reader_common.inc")

METAL_NAMES = {
    "nothing",
    "Copper",
    "Iron",
    "Tin",
    "Aluminum",
    "Zinc",
    "Lead",
    "Tungsten",
    "Titanium",
    "Lithium",
    "Antimony",
    "Strontium",
    "Silver",
    "Magnesiun",
    "Platinum",
    "Gold",
    "recognize",
}

RED = 0xFF2020ff
BLACK = 0x000000ff
WHITE = 0xFFFFFFff

DOWSING_TABLE_FILENAME = "dowsing_table.txt"
DOWSING_CSV_FILENAME = "dowsing_csv.txt"

NEARBY_TEXT = "nearby"

askText = [[If you are using automove make sure the chat is minimized / not selected.
Make sure that the main chat tab is open! You can scroll through the main tab and the macro will load and save all the data it sees inside.
Find the outputted data in C:\Games\Automato\games\ATITD\scripts in the files dowse_csv.txt and dowse_table.txt]]

NUM_STEPS = 5

function doit()
    local config = getUserParams()
    askForWindow(askText)
    runMacro(config)
end


latest_found = "Nothing found so far."
function runMacro(config)
    result, dowsing_table = deserialize(DOWSING_TABLE_FILENAME)
    dowsing_table = dowsing_table or {}

    if not result then
        for i=1,#METAL_NAMES do
            dowsing_table[METAL_NAMES[i]] = {}
        end
    end

    local timer = lsGetTimer()

    while true do
        checkBreak()

        local now = lsGetTimer()
        if now - timer > 500 then
            timer = now
            srReadScreen()
            tryDowse(config)
            updateLog()
        end

        if lsButtonText(lsScreenX - 110, lsScreenY - 30, z, 100, 0xFFFFFFff, "End script") then
            error "Clicked End Script button";
        end

        lsPrintWrapped(10, 10, z, lsScreenX - 10, 1.0, 1.0, 0xFFFFFFff,
            latest_found)

        lsDoFrame()
        lsSleep(50)
    end
end

function tryDowse(config)
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

function updateLog(config)
    local chat = getChatText()
    local changed = false
    for line=1, #chat do
        local line_text = chat[line][2]
        local match = ""
        for i=1,#METAL_NAMES do
            match = string.match(line_text, METAL_NAMES[i])
            if match then
                break
            end
        end
        local nearby = string.match(line_text, NEARBY_TEXT)
        local nothing = match == "nothing" and "nothing" or false
        local x,y = string.match(line_text, "(%-?[%d ]+) (%-?[%d ]+).")
        if match and x and y then
            y = y:gsub(" ", "")
            x = x:gsub(" ", "")
            local index = x .. "," .. y
            if not dowsing_table[match][index] then
                if not nothing then
                    if config.play_sound then
                        lsPlaySound("cheer.wav");
                    end
                    latest_found = latest_found .. "\n Found " .. match .. " at " .. index .. "!"
                end
                dowsing_table[match][index] = nearby and "nearby" or nothing or "ontop"
                changed = true
            end
        end
    end
    if changed then
        writeLog()
    end
end

function writeLog()
    local csv = createCSV()
    serialize(csv, DOWSING_CSV_FILENAME)
    serialize(dowsing_table, DOWSING_TABLE_FILENAME)
end


function createCSV()
    local csv = ""
    for i=1, #METAL_NAMES do
        local metal_name = METAL_NAMES[i]
        csv = csv .. "\n" .. metal_name .. ":\n ---------------------------- \n"
        for key,value in pairs(dowsing_table[metal_name]) do
            csv = csv .. key .. "\n"
        end
    end
    return csv
end



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
        auto_move=readSetting("auto_move",true)}
    while not is_done do
        current_y = 10

        config.auto_move = lsCheckBox(X_PADDING, current_y, 10, WHITE, "Auto move using the arrow keys?", config.auto_move)
        current_y = 40
        config.walk_distance = drawNumberEditBox("walk_distance", "Distance to walk after each dowse?", config.walk_distance)
        config.play_sound = lsCheckBox(X_PADDING, current_y, 10, WHITE, "Play sound on metal find?", config.play_sound)
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

    writeSetting("play_sound",config.play_sound)
    writeSetting("walk_distance",config.walk_distance)
    writeSetting("auto_move",config.auto_move)
    return config
end

function drawNumberEditBox(key, text, default)
    return drawEditBox(key, text, default, true)
end

function drawEditBox(key, text, default, validateNumber)
    drawTextUsingCurrent(text, WHITE)
    local width = validateNumber and 50 or 200
    local height = 30
    local done, result = lsEditBox(key, X_PADDING, current_y, 0, width, height, 1.0, 1.0, BLACK, default)
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


