#!/usr/bin/osascript
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Open Hide My Email
# @raycast.mode silent
# Optional parameters:
# @raycast.icon ✉️

use scripting additions
property settings_process : "System Settings"
property icloud_url : "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings?iCloud"
property hide_email_id : "six-pack-card-Hide My Email"
property poll_interval : 0.1

on run argv
	resetSystemSettings()
	open location (get icloud_url)
	waitForSettingsWindow()

	set hide_email_button to waitForHideMyEmailButton()
	tell application "System Events" to perform action "AXPress" of hide_email_button
end run

on resetSystemSettings()
	tell application "System Events"
		set is_running to exists process settings_process
	end tell
	if is_running then tell application "System Settings" to quit
	repeat 80 times
		tell application "System Events"
			if not (exists process settings_process) then return
		end tell
		delay poll_interval
	end repeat
	error "System Settings could not be closed."
end resetSystemSettings

on waitForSettingsWindow()
	repeat 120 times
		tell application "System Events"
			if exists process settings_process then
				tell process settings_process
					if (count of windows) > 0 then
						set frontmost to true
						return
					end if
				end tell
			end if
		end tell
		delay poll_interval
	end repeat
	error "System Settings did not open."
end waitForSettingsWindow

on waitForHideMyEmailButton()
	set target_id to hide_email_id
	repeat 120 times
		tell application "System Events"
			tell process settings_process
				set candidates to entire contents of window 1
			end tell
			repeat with candidate in candidates
				try
					if role of candidate is "AXButton" and value of attribute "AXIdentifier" of candidate is target_id then return contents of candidate
				end try
			end repeat
		end tell
		delay poll_interval
	end repeat
	error "The Hide My Email button was not found."
end waitForHideMyEmailButton
