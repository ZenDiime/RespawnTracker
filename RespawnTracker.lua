addon.name = 'RespawnTracker';
addon.author = 'Zendiime';
addon.version = '1.5';
addon.desc = 'Per-kill enemy respawn timers for Ashita v4.';
require('common');
local imgui = require('imgui');

local config = { visible = true, timers = {}, max_entries = 100, due_grace_seconds = 30 };
local config_path = AshitaCore:GetInstallPath() .. '\\addons\\RespawnTracker\\enemies.lua';

local function load_configured_enemies()
    local chunk = loadfile(config_path)
    if chunk then
        local ok, saved = pcall(chunk)
        if ok and type(saved) == 'table' then
            for name, seconds in pairs(saved) do
                if type(name) == 'string' and tonumber(seconds) and tonumber(seconds) > 0 then
                    config.timers[name] = tonumber(seconds)
                end
            end
        end
    end
end
local function save_configured_enemies()
    local file = io.open(config_path, 'w')
    if not file then
        print('[RespawnTracker] Could not save enemies.lua. Check folder permissions.')
        return
    end
    file:write('return {\n')
    for name, seconds in pairs(config.timers) do
        local safe = name:gsub('\\', '\\\\'):gsub("'", "\\'"):gsub('[\r\n]', ' ')
        file:write(("    ['%s'] = %d,\n"):format(safe, tonumber(seconds) or 0))
    end
    file:write('}\n')
    file:close()
end
load_configured_enemies()

local timers, window_open = {}, { true }
local kill_count, first_kill_at = 0, nil
local manual_name, manual_seconds = { '' }, { '300' }
local config_name, config_seconds = { '' }, { '300' }

local function clean_name(s)
    if not s then return '' end
    return (s:gsub('^%s+', ''):gsub('%s+$', ''):gsub('[%.!]+$', ''))
end
local function format_time(seconds)
    seconds = math.max(0, math.floor(seconds))
    local h, m, s = math.floor(seconds / 3600), math.floor((seconds % 3600) / 60), seconds % 60
    if h > 0 then return ('%d:%02d:%02d'):format(h,m,s) end
    return ('%02d:%02d'):format(m,s)
end
local function get_duration(name)
    for configured, seconds in pairs(config.timers) do
        if configured:lower() == name:lower() and tonumber(seconds) and tonumber(seconds) > 0 then return tonumber(seconds) end
    end
    return nil
end
local function add_timer(name, seconds)
    name = clean_name(name); seconds = tonumber(seconds) or get_duration(name)
    if name == '' or not seconds or seconds <= 0 then return end
    local used, id = {}, 1
    for _, entry in ipairs(timers) do used[entry.id] = true end
    while used[id] do id = id + 1 end
    table.insert(timers, { id=id, name=name, killed_at=os.time(), respawn_at=os.time()+seconds, seconds=seconds })
    while #timers > config.max_entries do table.remove(timers,1) end
end
local function reset_kill_stats()
    kill_count, first_kill_at = 0, nil
end
local function get_kills_per_hour()
    if kill_count == 0 or not first_kill_at then return 0 end
    local elapsed = math.max(1, os.time() - first_kill_at)
    return kill_count * 3600 / elapsed
end
local function args_seconds_name(args, start)
    local seconds = tonumber(args[start])
    if not seconds then return nil,nil end
    return seconds, clean_name(table.concat(args,' ',start+1))
end

ashita.events.register('command','respawntracker_command',function(e)
    local args=e.command:args()
    if #args==0 or (args[1]~='/rt' and args[1]~='/respawntracker') then return end
    e.blocked=true
    local sub=(args[2] or 'help'):lower()
    if sub=='help' then
        print('[RespawnTracker] /rt show|hide|toggle|clear|list; /rt add <seconds> <name>; /rt set <seconds> <name>')
    elseif sub=='show' then window_open[1]=true
    elseif sub=='hide' then window_open[1]=false
    elseif sub=='toggle' then window_open[1]=not window_open[1]
    elseif sub=='clear' then timers={}
    elseif sub=='add' then
        local seconds,name=args_seconds_name(args,3)
        if seconds and name~='' then add_timer(name,seconds) else print('[RespawnTracker] Usage: /rt add <seconds> <enemy name>') end
    elseif sub=='set' then
        local seconds,name=args_seconds_name(args,3)
        if seconds and seconds>0 and name~='' then config.timers[name]=seconds; save_configured_enemies()
        else print('[RespawnTracker] Usage: /rt set <seconds> <enemy name>') end
    elseif sub=='list' then
        for name,seconds in pairs(config.timers) do print(('[RespawnTracker] %s - %s'):format(name,format_time(seconds))) end
    else print('[RespawnTracker] Unknown command. Use /rt help') end
end)

ashita.events.register('text_in','respawntracker_text_in',function(e)
    if e.injected or not e.message then return end
    local message=e.message
    if string.strip_colors then message=string.strip_colors(message) end
    local lower=message:lower()
    local name=lower:match('again defeats the (.-)[%.!]') or lower:match('you defeat the (.-)[%.!]') or lower:match('you have defeated the (.-)[%.!]') or lower:match('you defeated the (.-)[%.!]') or lower:match('defeats the (.-)[%.!]')
    if name then
        name=clean_name(name)
        if name ~= '' then
            kill_count = kill_count + 1
            if not first_kill_at then first_kill_at = os.time() end
            local duration=get_duration(name)
            if duration then add_timer(name,duration) end
        end
    end
end)

ashita.events.register('d3d_present','respawntracker_present',function()
    if not window_open[1] then return end
    local visible=imgui.Begin('Respawn Tracker')
    if visible then
        imgui.Text(('Active timers: %d'):format(#timers))
        imgui.Text(('Enemies killed: %d'):format(kill_count))
        imgui.SameLine()
        imgui.Text(('Kills per hour: %.1f'):format(get_kills_per_hour()))
        if imgui.Button('Clear all') then timers={} end
        imgui.SameLine()
        if imgui.Button('Reset kill stats') then reset_kill_stats() end
        imgui.SameLine()
        if imgui.Button('Hide') then window_open[1]=false end
        imgui.Separator()
        if #timers==0 then imgui.TextWrapped('No active timers. Configure an enemy duration below, or add one manually.')
        else
            imgui.Columns(4,'respawn_timer_columns',true)
            imgui.Text('Enemy'); imgui.NextColumn(); imgui.Text('Remaining'); imgui.NextColumn(); imgui.Text('Due at'); imgui.NextColumn(); imgui.Text('ID'); imgui.NextColumn()
            imgui.Separator()
            local t=os.time()
            for i=#timers,1,-1 do
                local entry=timers[i]; local remaining=entry.respawn_at-t
                if remaining < -config.due_grace_seconds then
                    table.remove(timers,i)
                else
                    imgui.Text(entry.name); imgui.NextColumn()
                    imgui.Text(remaining<=0 and 'DUE' or format_time(remaining)); imgui.NextColumn()
                    imgui.Text(os.date('%H:%M:%S',entry.respawn_at)); imgui.NextColumn()
                    imgui.Text(tostring(entry.id)); imgui.NextColumn()
                end
            end
            imgui.Columns(1)
        end
        imgui.Separator()
        imgui.Text('Add manual timer')
        imgui.InputText('Enemy name##manual',manual_name,128)
        imgui.InputText('Seconds##manual',manual_seconds,16)
        if imgui.Button('Start timer') then local n=tonumber(manual_seconds[1]); if n and n>0 and manual_name[1]~='' then add_timer(manual_name[1],n) end end
        imgui.Separator()
        imgui.Text('Configure automatic kill timer')
        imgui.InputText('Enemy name##config',config_name,128)
        imgui.InputText('Respawn seconds##config',config_seconds,16)
        if imgui.Button('Save enemy duration') then
            local n=tonumber(config_seconds[1]); local name=clean_name(config_name[1])
            if n and n>0 and name~='' then config.timers[name]=n; save_configured_enemies() end
        end
        imgui.TextWrapped('Kill statistics count recognized enemy defeat messages for this session, including enemies without configured respawn timers. Stats reset when the addon reloads or when Reset kill stats is clicked.')
        imgui.TextWrapped('Configured enemy durations are saved to enemies.lua. Each configured kill gets a separate timer.')
    end
    imgui.End()
end)
