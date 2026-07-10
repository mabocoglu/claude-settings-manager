set homePath to POSIX path of (path to home folder)
set claudeDir to homePath & ".claude/"
set fileList to do shell script "cd " & quoted form of claudeDir & " && ls -1 settings.json settings.json.* 2>/dev/null | grep -v '~$' || true"
if fileList is "" then
	display dialog "No Claude settings profiles found in ~/.claude" buttons {"OK"} default button "OK"
	return
end if
set profileFiles to paragraphs of fileList
set profileLabels to {}
repeat with profileFile in profileFiles
	set fileName to contents of profileFile
	if fileName is "settings.json" then
		set end of profileLabels to "active"
	else
		set end of profileLabels to text ((length of "settings.json.") + 1) thru -1 of fileName
	end if
end repeat
set pickedProfile to choose from list profileLabels with title "Claude Settings Manager" with prompt "Choose a Claude Code settings profile" OK button name "Select" cancel button name "Cancel"
if pickedProfile is false then return
set profileName to item 1 of pickedProfile
if profileName is "active" then
	set sourceFile to "settings.json"
else
	set sourceFile to "settings.json." & profileName
end if
set sourcePath to claudeDir & sourceFile
set pickedAction to choose from list {"View/Edit content", "Activate profile", "Open profile in TextEdit", "Launch Claude Code"} with title "Claude Settings Manager" with prompt "Action for profile: " & profileName OK button name "Run" cancel button name "Cancel"
if pickedAction is false then return
set actionName to item 1 of pickedAction
if actionName is "View/Edit content" then
	set currentContent to do shell script "cat " & quoted form of sourcePath
	set editResult to display dialog currentContent default answer currentContent buttons {"Cancel", "Save Changes"} default button "Save Changes" cancel button "Cancel" with title "Edit: " & profileName
	set editedContent to text returned of editResult
	set tmpPath to do shell script "mktemp /tmp/claude-settings.XXXXXX.json"
	do shell script "cat > " & quoted form of tmpPath & " <<'JSON_EOF'" & linefeed & editedContent & linefeed & "JSON_EOF"
	try
		do shell script "python3 -m json.tool " & quoted form of tmpPath & " >/dev/null"
	on error errMsg
		display dialog "Invalid JSON. Changes were not saved." & return & return & errMsg buttons {"OK"} default button "OK" with title "Claude Settings Manager"
		do shell script "rm -f " & quoted form of tmpPath
		return
	end try
	set stamp to do shell script "date +%Y%m%d-%H%M%S"
	do shell script "mkdir -p " & quoted form of (claudeDir & "backups") & " && cp " & quoted form of sourcePath & " " & quoted form of (claudeDir & "backups/" & sourceFile & "." & stamp & ".bak") & " 2>/dev/null || true"
	do shell script "cp " & quoted form of tmpPath & " " & quoted form of sourcePath & " && rm -f " & quoted form of tmpPath
	display notification profileName & " saved" with title "Claude Settings Manager"
else if actionName is "Activate profile" then
	set stamp to do shell script "date +%Y%m%d-%H%M%S"
	do shell script "mkdir -p " & quoted form of (claudeDir & "backups") & " && cp " & quoted form of (claudeDir & "settings.json") & " " & quoted form of (claudeDir & "backups/settings.json." & stamp & ".bak") & " 2>/dev/null || true"
	do shell script "python3 -m json.tool " & quoted form of sourcePath & " >/dev/null"
	do shell script "cp " & quoted form of sourcePath & " " & quoted form of (claudeDir & "settings.json")
	display notification profileName & " activated" with title "Claude Settings Manager"
else if actionName is "Open profile in TextEdit" then
	do shell script "open -a TextEdit " & quoted form of sourcePath
else if actionName is "Launch Claude Code" then
	do shell script "tmp=$(mktemp /tmp/claude-code.XXXXXX.command); printf '%s\n' 'cd ~ && claude' > \"$tmp\"; chmod +x \"$tmp\"; open -a Terminal \"$tmp\""
end if
