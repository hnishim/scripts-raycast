#!/usr/bin/osascript

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Two-panes Finder
# @raycast.mode silent

# Optional parameters:
# @raycast.icon ??

# Documentation:
# @raycast.author hnishim
# @raycast.authorURL https://raycast.com/hnishim


use framework "AppKit"
use scripting additions

on run argv
	-- ???????Dock????????????????
	set mainScreen to current application's NSScreen's mainScreen()
	set mainFrame to (mainScreen's frame()) as list
	set visibleFrame to (mainScreen's visibleFrame()) as list

	set {visibleLeft, visibleBottom} to item 1 of visibleFrame
	set {visibleWidth, visibleHeight} to item 2 of visibleFrame
	set mainHeight to item 2 of item 2 of mainFrame

	-- AppKit?????????Finder???????????
	set screenLeft to visibleLeft
	set screenTop to mainHeight - (visibleBottom + visibleHeight)
	set screenRight to visibleLeft + visibleWidth
	set screenBottom to mainHeight - visibleBottom
	set middleX to screenLeft + (visibleWidth div 2)
	set desktopFolder to POSIX file ((current application's NSHomeDirectory() as text) & "/Desktop")

	tell application "Finder"
		-- ??????2?????Desktop??????
		repeat while (count of windows) < 2
			set newWindow to make new window
			set target of newWindow to desktopFolder
		end repeat

		-- ???2??????????????
		repeat while (count of windows) > 2
			close window 3
		end repeat

		set leftWindow to window 1
		set rightWindow to window 2

		-- ?????????????
		set bounds of leftWindow to {screenLeft, screenTop, middleX, screenBottom}
		set bounds of rightWindow to {middleX, screenTop, screenRight, screenBottom}

		activate
	end tell
end run
