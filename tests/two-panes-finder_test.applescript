#!/usr/bin/osascript

-- Deterministic, fixture-only tests for the pure handlers in
-- two-panes-finder.applescript. The fixture runner removes the production
-- run handler before compiling the source, so Finder is never contacted.

use framework "Foundation"
use scripting additions

on uncommentRunner(commentedSource)
	set uncommentedLines to {}
	repeat with sourceLine in paragraphs of commentedSource
		set lineText to sourceLine as text
		if (length of lineText) ≥ 3 and (text 1 thru 3 of lineText) is "-- " then
			set lineText to text 4 thru -1 of lineText
		else if (length of lineText) is 2 and lineText is "--" then
			set lineText to ""
		else if (length of lineText) > 2 and (text 1 thru 2 of lineText) is "--" then
			set lineText to text 3 thru -1 of lineText
		end if
		set end of uncommentedLines to lineText
	end repeat
	set savedDelimiters to AppleScript's text item delimiters
	set AppleScript's text item delimiters to linefeed
	set uncommentedSource to uncommentedLines as text
	set AppleScript's text item delimiters to savedDelimiters
	return uncommentedSource
end uncommentRunner

on assertSourceContains(sourceText, expectedText, caseName)
	if sourceText does not contain expectedText then
		error "FAIL: " & caseName & " (missing source text: " & expectedText & ")"
	end if
end assertSourceContains

on executableSource(sourceText)
	set executableLines to {}
	repeat with sourceLine in paragraphs of sourceText
		set lineText to sourceLine as text
		set trimmedLine to lineText
		repeat while trimmedLine is not "" and ((text 1 thru 1 of trimmedLine) is space or (text 1 thru 1 of trimmedLine) is tab)
			set trimmedLine to text 2 thru -1 of trimmedLine
		end repeat
		set isCommentLine to false
		if trimmedLine is not "" and (text 1 thru 1 of trimmedLine) is "#" then set isCommentLine to true
		if (length of trimmedLine) ≥ 2 and (text 1 thru 2 of trimmedLine) is "--" then set isCommentLine to true
		if trimmedLine is not "" and isCommentLine is false then
			set end of executableLines to lineText
		end if
	end repeat
	set savedDelimiters to AppleScript's text item delimiters
	set AppleScript's text item delimiters to linefeed
	set resultSource to executableLines as text
	set AppleScript's text item delimiters to savedDelimiters
	return resultSource
end executableSource

on assertSourceNotContains(sourceText, unexpectedText, caseName)
	if sourceText contains unexpectedText then
		error "FAIL: " & caseName & " (unexpected source text: " & unexpectedText & ")"
	end if
end assertSourceNotContains

on sourceTextOffset(searchText, sourceText)
	set savedDelimiters to AppleScript's text item delimiters
	set AppleScript's text item delimiters to searchText
	set sourceParts to text items of sourceText
	set AppleScript's text item delimiters to savedDelimiters
	if (count of sourceParts) is 1 then return 0
	return (length of (item 1 of sourceParts)) + 1
end sourceTextOffset

on assertSourceOrder(sourceText, firstNeedle, secondNeedle, caseName)
	set firstOffset to my sourceTextOffset(firstNeedle, sourceText)
	set secondOffset to my sourceTextOffset(secondNeedle, sourceText)
	if firstOffset is 0 or secondOffset is 0 or firstOffset ≥ secondOffset then
		error "FAIL: " & caseName & " (source order is invalid)"
	end if
end assertSourceOrder

on run argv
	set repositoryPath to (current application's NSFileManager's defaultManager()'s currentDirectoryPath()) as text
	set productionPath to repositoryPath & "/two-panes-finder.applescript"
	set testPath to repositoryPath & "/tests/two-panes-finder_test.applescript"
	set productionSource to (current application's NSString's stringWithContentsOfFile_encoding_error_(productionPath, current application's NSUTF8StringEncoding, missing value)) as text
	set testSource to (current application's NSString's stringWithContentsOfFile_encoding_error_(testPath, current application's NSUTF8StringEncoding, missing value)) as text
	set productionExecutableSource to my executableSource(productionSource)

	-- The Finder-facing generation contract is intentionally static here: the
	-- fixture below must remain Finder-free, while the production source must
	-- use Finder's menu action and integer ID state.
	my assertSourceContains(productionSource, "tell application \"Finder\" to launch", "Finder launch before window planning")
	my assertSourceContains(productionSource, "set processReady to false", "Finder process readiness state")
	my assertSourceContains(productionSource, "tell application \"System Events\" to tell process \"Finder\" to set processReady to exists", "Finder process readiness probe")
	my assertSourceContains(productionSource, "if processReady then exit repeat", "Finder process readiness gate")
	my assertSourceContains(productionSource, "on twoPaneFinderOpenNewWindowByMenu()", "C menu generation handler")
	my assertSourceContains(productionExecutableSource, "click menu item \"New Finder Window\" of menu \"File\" of menu bar 1", "C menu generation path")
	my assertSourceContains(productionSource, "twoPaneFinderNewWindowIDs", "new Finder window ID separation")
	my assertSourceContains(productionSource, "set newWindowIDs to my twoPaneFinderNewWindowIDs(existingWindowIDs, currentWindowIDs)", "new window IDs are derived before targeting")
	my assertSourceContains(productionSource, "twoPaneFinderCloseWindowIDs", "existing window close IDs are derived from the snapshot")
	my assertSourceContains(productionExecutableSource, "set target of window id newWindowIDValue to desktopFolder", "only new window IDs receive the Desktop target")
	my assertSourceContains(productionExecutableSource, "set paneWindowIDs to existingWindowIDs & newWindowIDs", "pane state uses existing and new integer IDs")
	my assertSourceContains(productionExecutableSource, "close window id (contents of closeWindowID)", "only snapshotted excess IDs are closed")
	my assertSourceContains(productionExecutableSource, "set bounds of window id (contents of leftID) to leftBounds", "left pane is re-resolved by integer ID")
	my assertSourceContains(productionExecutableSource, "set bounds of window id (contents of rightID) to rightBounds", "right pane is re-resolved by integer ID")
	my assertSourceContains(productionExecutableSource, "if existingWindowCount ≥ 3 then", "three-or-more existing windows branch")
	my assertSourceContains(productionExecutableSource, "set closeWindowIDs to my twoPaneFinderCloseWindowIDs(existingWindowIDs)", "excess IDs are computed before closing")
	my assertSourceContains(productionExecutableSource, "set leftID to item 1 of existingWindowIDs", "first snapshotted existing ID is reused on the left")
	my assertSourceContains(productionExecutableSource, "set rightID to item 2 of existingWindowIDs", "second snapshotted existing ID is reused on the right")
	my assertSourceOrder(productionSource, "tell application \"Finder\" to launch", "set existingWindowIDs to id of every window", "Finder launch precedes existing window snapshot")
	my assertSourceOrder(productionExecutableSource, "if processReady then exit repeat", "my twoPaneFinderOpenNewWindowByMenu()", "readiness precedes menu generation")
	my assertSourceOrder(productionExecutableSource, "set newWindowIDs to my twoPaneFinderNewWindowIDs(existingWindowIDs, currentWindowIDs)", "set target of window id newWindowIDValue to desktopFolder", "new window ID extraction precedes target assignment")
	my assertSourceOrder(productionExecutableSource, "set closeWindowIDs to my twoPaneFinderCloseWindowIDs(existingWindowIDs)", "close window id (contents of closeWindowID)", "close IDs are computed before closing")
	my assertSourceOrder(productionExecutableSource, "close window id (contents of closeWindowID)", "set leftID to item 1 of existingWindowIDs", "excess close precedes existing ID reuse")
	my assertSourceOrder(productionExecutableSource, "set leftID to item 1 of existingWindowIDs", "set bounds of window id (contents of leftID) to leftBounds", "left ID precedes left bounds assignment")
	my assertSourceOrder(productionExecutableSource, "set rightID to item 2 of existingWindowIDs", "set bounds of window id (contents of rightID) to rightBounds", "right ID precedes right bounds assignment")
	my assertSourceNotContains(productionExecutableSource, "make new Finder window", "native direct Finder generation is excluded")
	my assertSourceNotContains(productionExecutableSource, "keystroke \"n\" using {command down}", "Cmd-N is not the primary generation path")
	my assertSourceNotContains(productionExecutableSource, "repeat with candidateWindow in every window", "candidate window loop reference is not used")
	my assertSourceNotContains(productionExecutableSource, "contents of candidateWindow", "candidate window contents are not used as Finder objects")
	my assertSourceNotContains(productionExecutableSource, "set target of window 1 to desktopFolder", "existing window 1 is not directly targeted")
	my assertSourceNotContains(productionExecutableSource, "set target of window 2 to desktopFolder", "existing window 2 is not directly targeted")
	my assertSourceNotContains(productionExecutableSource, "close window 3", "window index close is excluded")

	-- Keep the production script's handlers while replacing its Finder-facing run.
	set savedDelimiters to AppleScript's text item delimiters
	set AppleScript's text item delimiters to "on run argv"
	set productionParts to text items of productionSource
	if (count of productionParts) is not 2 then
		error "FAIL: production run handler markers were not found"
	end if
	set productionPrefix to item 1 of productionParts
	set productionAfterRunMarker to item 2 of productionParts
	set AppleScript's text item delimiters to "end run"
	set productionRunParts to text items of productionAfterRunMarker
	if (count of productionRunParts) is not 2 then
		error "FAIL: production run handler markers were not found"
	end if
	set productionHandlers to productionPrefix & item 2 of productionRunParts

	-- Reuse the executable fixture runner below without duplicating it in a string.
	set runnerStartMarker to "-- " & "BEGIN FIXTURE RUNNER"
	set runnerEndMarker to "-- " & "END FIXTURE RUNNER"
	set AppleScript's text item delimiters to runnerStartMarker
	set runnerParts to text items of testSource
	if (count of runnerParts) is not 2 then
		error "FAIL: fixture runner markers were not found"
	end if
	set AppleScript's text item delimiters to runnerEndMarker
	set runnerEndParts to text items of item 2 of runnerParts
	if (count of runnerEndParts) is not 2 then
		error "FAIL: fixture runner markers were not found"
	end if
	set runnerSource to my uncommentRunner(item 1 of runnerEndParts)
	set AppleScript's text item delimiters to savedDelimiters
	set combinedSource to productionHandlers & return & runnerSource
	set fixturePath to "/private/tmp/hir134-combined.applescript"
	current application's NSString's stringWithString_(combinedSource)'s writeToFile_atomically_encoding_error_(fixturePath, true, current application's NSUTF8StringEncoding, missing value)
	set outputPipe to current application's NSPipe's pipe()
	set errorPipe to current application's NSPipe's pipe()
	set taskObject to current application's NSTask's alloc()'s init()
	taskObject's setLaunchPath_("/usr/bin/osascript")
	taskObject's setArguments_({fixturePath})
	taskObject's setStandardOutput_(outputPipe)
	taskObject's setStandardError_(errorPipe)
	set launchError to reference
	set launchResult to taskObject's launchAndReturnError_(launchError)
	set launched to item 1 of launchResult
	if not launched then error "FAIL: fixture runner could not launch"
	taskObject's waitUntilExit()
	set outputData to outputPipe's fileHandleForReading()'s readDataToEndOfFile()
	set errorData to errorPipe's fileHandleForReading()'s readDataToEndOfFile()
	set outputText to (current application's NSString's alloc()'s initWithData_encoding_(outputData, current application's NSUTF8StringEncoding)) as text
	set errorText to (current application's NSString's alloc()'s initWithData_encoding_(errorData, current application's NSUTF8StringEncoding)) as text
	if (taskObject's terminationStatus()) is not 0 then error "FAIL: fixture runner could not execute: " & errorText
	return outputText
end run

-- BEGIN FIXTURE RUNNER
-- on assertEqual(expectedValue, actualValue, caseName)
-- 	if actualValue is not equal to expectedValue then
-- 		error "FAIL: " & caseName & " (expected " & (expectedValue as text) & ", got " & (actualValue as text) & ")"
-- 	end if
-- end assertEqual
--
-- on assertEqualList(expectedValue, actualValue, caseName)
-- 	if (actualValue as text) is not equal to (expectedValue as text) then
-- 		error "FAIL: " & caseName & " (expected " & (expectedValue as text) & ", got " & (actualValue as text) & ")"
-- 	end if
-- end assertEqualList
--
-- on run argv
-- 	-- NSScreen-like AppKit frames: main screen first, external screen second.
-- 	set horizontalScreens to {{{0, 0}, {1920, 1080}}, {{1920, 0}, {1920, 1080}}}
-- 	set upperScreens to {{{0, 0}, {1920, 1080}}, {{0, 1080}, {1920, 1200}}}
-- 	set lowerScreens to {{{0, -1200}, {1920, 1200}}, {{0, 0}, {1920, 1080}}}
--
-- 	-- The generated script is the production script itself, so the handlers
-- 	-- under test are invoked directly in the generated production script.
--
-- 	-- The Hammerspoon task passes the script path to osascript first; the
-- 	-- production run handler receives the remaining four values as strings.
-- 	set validBounds to my twoPaneFinderWindowBoundsFromArguments({"100", "200", "640", "480"})
-- 	my assertEqualList({100.0, 200.0, 740.0, 680.0}, validBounds, "valid run argv bounds")
-- 	set missingBounds to my twoPaneFinderWindowBoundsFromArguments({"100", "200", "640"})
-- 	my assertEqual(true, missingBounds is missing value, "missing run argv fallback marker")
-- 	set invalidBounds to my twoPaneFinderWindowBoundsFromArguments({"100", "200", "not-a-number", "480"})
-- 	my assertEqual(true, invalidBounds is missing value, "invalid run argv fallback marker")
--
-- 	-- Horizontal two-screen selection: built-in/main and external.
-- 	my assertEqual(1, my selectScreenIndexForWindowBounds({100, 100, 700, 500}, horizontalScreens, 1080, 1), "main screen selection")
-- 	my assertEqual(2, my selectScreenIndexForWindowBounds({1920, 100, 2500, 500}, horizontalScreens, 1080, 1), "external screen selection")
-- 	my assertEqual(2, my selectScreenIndexForWindowBounds({1820, 0, 2020, 200}, horizontalScreens, 1080, 1), "right boundary belongs to external screen")
-- 	my assertEqual(1, my selectScreenIndexForWindowBounds({-100, 0, 100, 200}, horizontalScreens, 1080, 1), "left boundary belongs to main screen")
--
-- 	-- Screens above and below the main screen use the Finder/AppKit Y transform.
-- 	my assertEqual(2, my selectScreenIndexForWindowBounds({100, -500, 700, -340}, upperScreens, 1080, 1), "upper screen selection")
-- 	my assertEqual(1, my selectScreenIndexForWindowBounds({100, 1400, 700, 1600}, lowerScreens, 1080, 2), "lower screen selection")
--
-- 	-- Unavailable/invalid bounds and a center outside every screen fall back.
-- 	my assertEqual(1, my selectScreenIndexForWindowBounds(missing value, horizontalScreens, 1080, 1), "unavailable bounds fallback")
-- 	my assertEqual(2, my selectScreenIndexForWindowBounds({1, 2, 3}, horizontalScreens, 1080, 2), "invalid bounds fallback")
-- 	my assertEqual(1, my selectScreenIndexForWindowBounds({5000, 100, 5500, 500}, horizontalScreens, 1080, 1), "off-screen fallback")
--
-- 	-- Finder bounds derived from an AppKit visible frame. The split is width div 2.
-- 	set paneBounds to my twoPaneFinderBoundsForVisibleFrame({{0, 50}, {1921, 1000}}, 1080)
-- 	set leftBounds to item 1 of paneBounds
-- 	set rightBounds to item 2 of paneBounds
-- 	my assertEqualList({0, 30, 960, 1030}, leftBounds, "left pane bounds")
-- 	my assertEqualList({960, 30, 1921, 1030}, rightBounds, "right pane bounds")
-- 	my assertEqual(0, item 1 of leftBounds, "left edge preserved")
-- 	my assertEqual(1921, item 3 of rightBounds, "right edge preserved")
-- 	my assertEqual(30, item 2 of leftBounds, "top edge converted")
-- 	my assertEqual(1030, item 4 of leftBounds, "bottom edge converted")
-- 	my assertEqual(960, item 3 of leftBounds, "center split left")
-- 	my assertEqual(960, item 1 of rightBounds, "center split right")
--
-- 	-- Existing Finder window counts determine creation and desktop targeting.
-- 	my assertEqualList({2, 0, 2}, my twoPaneFinderWindowPlan(0), "zero existing windows plan")
-- 	my assertEqualList({1, 1, 1}, my twoPaneFinderWindowPlan(1), "one existing window plan")
-- 	my assertEqualList({0, 2, 0}, my twoPaneFinderWindowPlan(2), "two existing windows plan")
-- 	my assertEqualList({0, 2, 0}, my twoPaneFinderWindowPlan(3), "three existing windows plan")
--
-- 	my assertEqualList({}, my twoPaneFinderCloseWindowIDs({}), "no excess windows to close")
-- 	my assertEqualList({}, my twoPaneFinderCloseWindowIDs({101, 102}), "two windows are both retained")
-- 	my assertEqualList({103}, my twoPaneFinderCloseWindowIDs({101, 102, 103}), "third window is the first excess ID")
-- 	my assertEqualList({103, 104}, my twoPaneFinderCloseWindowIDs({101, 102, 103, 104}), "all excess IDs are returned")
--
-- 	-- Only window IDs created after direct Finder generation are eligible for pane placement.
-- 	my assertEqualList({202}, my twoPaneFinderNewWindowIDs({101}, {101, 202}), "new window ID after one existing window")
-- 	my assertEqualList({}, my twoPaneFinderNewWindowIDs({101, 102}, {101, 102}), "no new window IDs")
-- 	my assertEqualList({201, 202}, my twoPaneFinderNewWindowIDs({}, {201, 202}), "all current IDs are new")
--
-- 	return "PASS: two-panes-finder handler contract (49 assertions; no Finder window side effects)"
-- end run
-- END FIXTURE RUNNER
