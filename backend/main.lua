local logger = require("logger")
local millennium = require("millennium")
local utils = require("utils")
local fs = require("fs")

local LOG = "/tmp/steam-linux-transparency.log"

local function log(msg)
    utils.append_file(LOG, tostring(msg) .. "\n")
end

---@ffi
---@param msg string
---@return boolean
function log_from_frontend(msg)
    log(tostring(msg))
    return true
end

local function sp_path()
    local steam = millennium.steam_path()
    return fs.join(steam, "steamui", "sp.js")
end

local function backup_path()
    return sp_path() .. ".millennium-original"
end

local ORIGINAL = "let gr=g.Wf.None;((0,c.td)()||ye)&&(gr|=g.Wf.Composited);const jr=p.Ij|gr|"
local PATCHED = "let gr=g.Wf.Composited|g.Wf.TransparentParentWindow;const jr=p.Ij|gr|"
local POPUP_ORIGINAL = 'G.push("createflags="+B.eCreationFlags)'
local POPUP_PATCHED = 'G.push("createflags="+((v&&v.indexOf("contextmenu_")===0)?4194576:(B.eCreationFlags|4194304|256)))'
local MODAL_ORIGINAL = 'let M=0;g.resizable&&(M|=r.Wf.Resizable),(g.minWidth||g.minHeight)&&(M|=r.Wf.ApplyBrowserScaleToDimensions),g.fullscreen&&(M|=r.Wf.FullScreen);'
local MODAL_PATCHED = 'let M=0;M|=r.Wf.Composited|r.Wf.TransparentParentWindow;g.resizable&&(M|=r.Wf.Resizable),(g.minWidth||g.minHeight)&&(M|=r.Wf.ApplyBrowserScaleToDimensions),g.fullscreen&&(M|=r.Wf.FullScreen);'
local FRIENDS_ORIGINAL = 'let Wt=Be.Wf.Resizable;ge&&!(0,x.Pr)()&&(Wt|=Be.Wf.Minimized);'
local FRIENDS_PATCHED = 'let Wt=Be.Wf.Resizable|Be.Wf.Composited|Be.Wf.TransparentParentWindow;ge&&!(0,x.Pr)()&&(Wt|=Be.Wf.Minimized);'
local NATIVE_ORIGINAL = 'static CreatePopup(v,B){let k=B.dimensions||{},'
local NATIVE_PATCHED = 'static CreatePopup(v,B){const _n=v||"";const _isMenu=_n.indexOf("contextmenu_")===0;const _isOverlay=_n.indexOf("notificationtoasts_")===0||_n.indexOf("desktopoverlay_")===0||(B.target_browser&&B.target_browser.m_unPID);if(_isMenu)B.eCreationFlags=4194576;else if(!_isOverlay)B.eCreationFlags=B.eCreationFlags|4194304|256;let k=B.dimensions||{},'
local DESKTOP_ORIGINAL = ",[ce,me,Pt,et,F,ve,At]),(0,p.yu)($t)"
local DESKTOP_PATCHED = ",[ce,me,Pt,et,F,ve,At]),l.useEffect(()=>{if(!et)return;const _bp=(()=>{try{return localStorage.getItem('sl-transparency-in-bigpicture')==='1'}catch{return false}})();const _save=()=>{try{if(!_bp){const _v=et.SteamClient.Window.GetWindowRestoreDetails();if(_v&&typeof _v.then==='function'){_v.then(d=>{try{if(d)localStorage.setItem('sl-transparency-desktop-details',d)}catch{}})}else if(_v){localStorage.setItem('sl-transparency-desktop-details',_v)}}}catch{}};const _fix=()=>{try{et.SteamClient.Window.SetMinSize(ve,At);if(_bp){const _d=(()=>{try{return localStorage.getItem('sl-transparency-desktop-details')}catch{return null}})();if(_d)et.SteamClient.Window.RestoreWindowSizeAndPosition(_d);try{localStorage.removeItem('sl-transparency-in-bigpicture')}catch{}}}catch{}};_save();_fix();et.addEventListener('resize',_save);const _t1=setTimeout(_fix,300),_t2=setTimeout(_fix,1200),_t3=setTimeout(_fix,3000);return()=>{et.removeEventListener('resize',_save);clearTimeout(_t1);clearTimeout(_t2);clearTimeout(_t3)}},[et,ve,At]),(0,p.yu)($t)"

local function replace_plain(content, needle, replacement)
    local first, last = content:find(needle, 1, true)
    if not first then
        return nil
    end
    return content:sub(1, first - 1) .. replacement .. content:sub(last + 1)
end

-- All native popups (Settings, Friends List, menus and dialogs) are created
-- through this URL builder. OR the two flags in so every popup gets an ARGB
-- surface as well. The main desktop window also goes through it.
local function patch_popup_flags(content)
    local replaced = replace_plain(content, POPUP_ORIGINAL, POPUP_PATCHED)
    if replaced then
        return replaced
    end
    -- Fallback if Steam renames the minified locals.
    local out, count = content:gsub(
        '("createflags=")%+([%w_]+)%.eCreationFlags',
        '%1+(%2.eCreationFlags|4194304|256)',
        1
    )
    if count > 0 then
        return out
    end
    return nil
end

---@ffi
---@return string
function ensure_sp_patch()
    local path = sp_path()
    local original, err = utils.read_file(path)
    if not original then
        log("read sp.js failed: " .. tostring(err))
        return "read_failed"
    end

    local content = original
    local main_patched = content:find(PATCHED, 1, true) ~= nil
    local popup_patched = content:find(POPUP_PATCHED, 1, true) ~= nil
    local desktop_patched = content:find(DESKTOP_PATCHED, 1, true) ~= nil
    local native_patched = content:find(NATIVE_PATCHED, 1, true) ~= nil
    local modal_patched = content:find(MODAL_PATCHED, 1, true) ~= nil
    local friends_patched = content:find(FRIENDS_PATCHED, 1, true) ~= nil

    if main_patched and popup_patched and desktop_patched and native_patched and modal_patched and friends_patched then
        log("sp.js already patched")
        return "already"
    end

    local changed = false

    if not main_patched then
        local replaced = replace_plain(content, ORIGINAL, PATCHED)
        if not replaced then
            -- Fallback for Steam builds with renamed minified locals.
            replaced = replace_plain(
                content,
                "eCreationFlags:jr",
                "eCreationFlags:(jr|g.Wf.Composited|g.Wf.TransparentParentWindow)"
            )
        end
        if replaced then
            content = replaced
            changed = true
        else
            log("main window pattern not found")
        end
    end

    if not popup_patched then
        local replaced = patch_popup_flags(content)
        if replaced then
            content = replaced
            changed = true
        else
            log("popup createflags pattern not found")
        end
    end

    if not native_patched then
        local replaced = replace_plain(content, NATIVE_ORIGINAL, NATIVE_PATCHED)
        if replaced then
            content = replaced
            changed = true
        else
            log("native popup flags pattern not found")
        end
    end

    if not modal_patched then
        local replaced = replace_plain(content, MODAL_ORIGINAL, MODAL_PATCHED)
        if replaced then
            content = replaced
            changed = true
        else
            log("modal popup flags pattern not found")
        end
    end

    if not friends_patched then
        local replaced = replace_plain(content, FRIENDS_ORIGINAL, FRIENDS_PATCHED)
        if replaced then
            content = replaced
            changed = true
        else
            log("friends popup flags pattern not found")
        end
    end

    if not desktop_patched then
        local replaced = replace_plain(content, DESKTOP_ORIGINAL, DESKTOP_PATCHED)
        if replaced then
            content = replaced
            changed = true
        else
            log("desktop min-size pattern not found")
        end
    end

    if not changed then
        log("sp.js patterns not found")
        return "pattern_not_found"
    end

    -- Only back up a completely unpatched file. If it was already partially
    -- patched, the existing backup is still the original.
    if not main_patched and not popup_patched and not desktop_patched and not native_patched and not modal_patched and not friends_patched then
        local ok, write_err = utils.write_file(backup_path(), original)
        if not ok then
            log("backup failed: " .. tostring(write_err))
        end
    end

    local ok, write_err = utils.write_file(path, content)
    if not ok then
        log("write sp.js failed: " .. tostring(write_err))
        return "write_failed"
    end

    log("sp.js patched main=" .. tostring(not main_patched) .. " popup=" .. tostring(not popup_patched) .. " desktop=" .. tostring(not desktop_patched) .. " native=" .. tostring(not native_patched) .. " modal=" .. tostring(not modal_patched) .. " friends=" .. tostring(not friends_patched))
    return "patched"
end

---@ffi
---@return string
function restore_sp_patch()
    local backup = backup_path()
    if not fs.exists(backup) then
        log("no sp.js backup")
        return "no_backup"
    end
    local content, err = utils.read_file(backup)
    if not content then
        log("read backup failed: " .. tostring(err))
        return "read_failed"
    end
    local ok, write_err = utils.write_file(sp_path(), content)
    if not ok then
        log("restore sp.js failed: " .. tostring(write_err))
        return "write_failed"
    end
    log("sp.js restored")
    return "restored"
end


local function wrapper_path()
    return fs.join(millennium.steam_path(), "ubuntu12_64", "steamwebhelper_sniper_wrap.sh")
end

local WRAPPER_ORIGINAL = 'exec ./steamwebhelper "$@"'
local WRAPPER_PATCHED = 'exec ./steamwebhelper "$@" --disable-features=CalculateNativeWinOcclusion'

---@ffi
---@return string
function ensure_wrapper_patch()
    local path = wrapper_path()
    local content, err = utils.read_file(path)
    if not content then
        log("read steamwebhelper wrapper failed: " .. tostring(err))
        return "read_failed"
    end
    if content:find("--disable-features=CalculateNativeWinOcclusion", 1, true) then
        return "already"
    end
    local backup = path .. ".millennium-original"
    local patched = replace_plain(content, WRAPPER_ORIGINAL, WRAPPER_PATCHED)
    if not patched and fs.exists(backup) then
        local backup_content = utils.read_file(backup)
        if backup_content then
            patched = replace_plain(backup_content, WRAPPER_ORIGINAL, WRAPPER_PATCHED)
            if patched then
                content = backup_content
                log("steamwebhelper wrapper upgraded from backup")
            end
        end
    end
    if not patched then
        log("steamwebhelper wrapper pattern not found")
        return "pattern_not_found"
    end
    if not fs.exists(backup) then
        local ok, write_err = utils.write_file(backup, content)
        if not ok then
            log("wrapper backup failed: " .. tostring(write_err))
        end
    end
    local ok, write_err = utils.write_file(path, patched)
    if not ok then
        log("write steamwebhelper wrapper failed: " .. tostring(write_err))
        return "write_failed"
    end
    log("steamwebhelper wrapper patched")
    return "patched"
end

---@ffi
---@return string
function restore_wrapper_patch()
    local path = wrapper_path()
    local backup = path .. ".millennium-original"
    if not fs.exists(backup) then
        log("no steamwebhelper wrapper backup")
        return "no_backup"
    end
    local content, err = utils.read_file(backup)
    if not content then
        log("read wrapper backup failed: " .. tostring(err))
        return "read_failed"
    end
    local ok, write_err = utils.write_file(path, content)
    if not ok then
        log("restore steamwebhelper wrapper failed: " .. tostring(write_err))
        return "write_failed"
    end
    log("steamwebhelper wrapper restored")
    return "restored"
end

---@ffi
---@return boolean
function webhelper_has_legacy_flag()
    local p = io.popen("ps -eo cmd | grep '[.]\\/steamwebhelper' | grep -v -- '--type=' | head -1")
    if not p then
        return false
    end
    local s = p:read("*a") or ""
    p:close()
    return s:find("-use_xcomposite_workaround", 1, true) ~= nil
end

---@ffi
---@return boolean
function webhelper_has_throttle_flags()
    local p = io.popen("ps -eo cmd | grep '[.]\\/steamwebhelper' | grep -v -- '--type=' | head -1")
    if not p then
        return false
    end
    local s = p:read("*a") or ""
    p:close()
    return s:find("--disable-features=CalculateNativeWinOcclusion", 1, true) ~= nil
end

---@ffi
---@return boolean
function restart_webhelper()
    local script = [[
for p in $(pgrep -f '^[.]/steamwebhelper '); do
    if ! tr '\0' ' ' < /proc/$p/cmdline | grep -q -- '--type='; then
        kill "$p"
        exit 0
    fi
done
]]
    local path = "/tmp/stlt-restart-webhelper.sh"
    local ok, err = utils.write_file(path, script)
    if not ok then
        log("write webhelper restart script failed: " .. tostring(err))
        return false
    end
    os.execute("setsid sh " .. path .. " >/dev/null 2>&1 &")
    log("webhelper restart requested")
    return true
end

---@ffi
---@return boolean
function schedule_steam_restart()
    -- Detached shell survives Steam shutdown and relaunches the client.
    local ok = os.execute("setsid sh -c 'sleep 8; nohup /usr/bin/steam >/dev/null 2>&1 &' >/dev/null 2>&1 &")
    return ok == true or ok == 0
end

local function on_load()
    log("backend loaded")
    local wrapper = ensure_wrapper_patch()
    log("wrapper on load: " .. tostring(wrapper))
    millennium.ready()
end

local function on_unload()
    log("backend unloaded")
end

return {
    on_load = on_load,
    on_unload = on_unload,
}
