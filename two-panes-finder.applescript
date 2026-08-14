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

	tell application "Finder"
		-- ??????2?????Desktop??????
		repeat while (count of Finder windows) < 2
			set newWindow to make new Finder window
			set target of newWindow to (path to desktop folder)
		end repeat

		-- ???2??????????????
		repeat while (count of Finder windows) > 2
			close Finder window 3
		end repeat

		set leftWindow to Finder window 1
		set rightWindow to Finder window 2

		-- ?????????????
		set bounds of leftWindow to {screenLeft, screenTop, middleX, screenBottom}
		set bounds of rightWindow to {middleX, screenTop, screenRight, screenBottom}

		activate
	end tell
end run
