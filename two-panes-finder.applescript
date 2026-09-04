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

on selectScreenIndexForWindowBounds(windowBounds, screenFrames, desktopHeight, fallbackIndex)
	try
		set {windowLeft, windowTop, windowRight, windowBottom} to windowBounds
		set centerX to (windowLeft + windowRight) / 2
		set centerFinderY to (windowTop + windowBottom) / 2
		set centerY to desktopHeight - centerFinderY
		set screenIndex to 0
		repeat with screenFrame in screenFrames
			set screenIndex to screenIndex + 1
			set frameValue to contents of screenFrame
			set frameOrigin to item 1 of frameValue
			set frameSize to item 2 of frameValue
			set {frameX, frameY} to frameOrigin
			set {frameWidth, frameHeight} to frameSize
			if centerX ≥ frameX and centerX < (frameX + frameWidth) and centerY ≥ frameY and centerY < (frameY + frameHeight) then return screenIndex
		end repeat
	end try
	return fallbackIndex
end selectScreenIndexForWindowBounds

on twoPaneFinderWindowBoundsFromArguments(argv)
	try
		if (count of argv) is not 4 then return missing value
		set windowLeft to (item 1 of argv) as real
		set windowTop to (item 2 of argv) as real
		set windowWidth to (item 3 of argv) as real
		set windowHeight to (item 4 of argv) as real
		if windowLeft is not equal to windowLeft or windowTop is not equal to windowTop or windowWidth is not equal to windowWidth or windowHeight is not equal to windowHeight then return missing value
		if windowLeft > 1.0E+308 or windowLeft < -1.0E+308 or windowTop > 1.0E+308 or windowTop < -1.0E+308 or windowWidth > 1.0E+308 or windowWidth < -1.0E+308 or windowHeight > 1.0E+308 or windowHeight < -1.0E+308 then return missing value
		if windowWidth ≤ 0 or windowHeight ≤ 0 then return missing value
		return {windowLeft, windowTop, windowLeft + windowWidth, windowTop + windowHeight}
	on error
		return missing value
	end try
end twoPaneFinderWindowBoundsFromArguments

on twoPaneFinderBoundsForVisibleFrame(visibleFrame, desktopHeight)
	set {visibleLeft, visibleBottom} to item 1 of visibleFrame
	set {visibleWidth, visibleHeight} to item 2 of visibleFrame
	set screenLeft to visibleLeft
	set screenTop to desktopHeight - (visibleBottom + visibleHeight)
	set screenRight to visibleLeft + visibleWidth
	set screenBottom to desktopHeight - visibleBottom
	set middleX to screenLeft + (visibleWidth div 2)
	return {{screenLeft, screenTop, middleX, screenBottom}, {middleX, screenTop, screenRight, screenBottom}}
end twoPaneFinderBoundsForVisibleFrame

on run argv
	-- ???????Dock????????????????
	set mainScreen to current application's NSScreen's mainScreen()
	if mainScreen is missing value then error "Unable to determine the main screen"
	set mainFrame to (mainScreen's frame()) as list
	set desktopHeight to item 2 of item 2 of mainFrame

	-- Hammerspoon?????????????????????Finder???????
	set frontmostWindowBounds to my twoPaneFinderWindowBoundsFromArguments(argv)

	set selectedScreen to mainScreen
	try
		set screenObjects to current application's NSScreen's screens()
		if screenObjects is not missing value then
			set screenObjects to screenObjects as list
			set screenFrames to {}
			repeat with screenObject in screenObjects
				set end of screenFrames to ((contents of screenObject)'s frame()) as list
			end repeat
			set selectedIndex to my selectScreenIndexForWindowBounds(frontmostWindowBounds, screenFrames, desktopHeight, 0)
			if selectedIndex > 0 and selectedIndex ≤ (count of screenObjects) then set selectedScreen to item selectedIndex of screenObjects
		end if
	end try
	set visibleFrame to (selectedScreen's visibleFrame()) as list
	set paneBounds to my twoPaneFinderBoundsForVisibleFrame(visibleFrame, desktopHeight)
	set leftBounds to item 1 of paneBounds
	set rightBounds to item 2 of paneBounds
	set desktopFolder to POSIX file ((current application's NSHomeDirectory() as text) & "/Desktop")

	tell application "Finder"
		-- ??????2?????Desktop??????
		if (count of windows) < 2 then
			set newWindowAttempts to 0
			repeat while (count of windows) < 2 and newWindowAttempts < 2
				set newWindowAttempts to newWindowAttempts + 1
				activate
				tell application "System Events" to tell process "Finder" to keystroke "n" using {command down}
				repeat 20 times
					delay 0.1
					if (count of windows) ≥ 2 then exit repeat
				end repeat
			end repeat
			if (count of windows) ≥ 2 then
				set target of window 1 to desktopFolder
				set target of window 2 to desktopFolder
			end if
		end if
		if (count of windows) < 2 then error "Unable to open a second Finder window"

		-- ???2??????????????
		repeat while (count of windows) > 2
			close window 3
		end repeat

		set leftWindow to window 1
		set rightWindow to window 2

		-- ?????????????
		set bounds of leftWindow to leftBounds
		set bounds of rightWindow to rightBounds

		activate
	end tell
end run
