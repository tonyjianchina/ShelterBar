-- Drives the installed app's real refresh command. Requires automation access
-- to System Events. A native move failure must fail this check, even if the
-- process remains healthy and unit tests pass.
tell application "System Events"
    tell process "ShelterBar"
        if not (exists window "ShelterBar 收纳栏") then
            click menu bar item 1 of menu bar 1
            delay 0.3
        end if
        if exists button "授予权限" of group 1 of window "ShelterBar 收纳栏" then
            error "BLOCKED: installed ShelterBar requires Accessibility authorization" number 1
        end if
        click menu button "更多" of group 1 of window "ShelterBar 收纳栏"
        click menu item "刷新并恢复收纳" of menu "更多" of menu button "更多" of group 1 of window "ShelterBar 收纳栏"
        delay 2
        if exists button "授予权限" of group 1 of window "ShelterBar 收纳栏" then
            error "BLOCKED: installed ShelterBar requires Accessibility authorization" number 1
        end if
        set messages to value of every static text of group 1 of window "ShelterBar 收纳栏"
        repeat with message in messages
            if message contains "无法安全整理" or message contains "未接受" or message contains "未能移动" or message contains "没有完成" or message contains "被刘海遮挡" or message contains "请允许辅助功能" then
                error "FAIL: " & message number 1
            end if
        end repeat
        return "PASS: " & messages
    end tell
end tell
