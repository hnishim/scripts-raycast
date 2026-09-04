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

on run argv
	set repositoryPath to (current application's NSFileManager's defaultManager()'s currentDirectoryPath()) as text
	set productionPath to repositoryPath & "/two-panes-finder.applescript"
	set testPath to repositoryPath & "/tests/two-panes-finder_test.applescript"
	set productionSource to (current application's NSString's stringWithContentsOfFile_encoding_error_(productionPath, current application's NSUTF8StringEncoding, missing value)) as text
	set testSource to (current application's NSString's stringWithContentsOfFile_encoding_error_(testPath, current application's NSUTF8StringEncoding, missing value)) as text

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
-- 	return "PASS: two-panes-finder handler contract (20 assertions; no Finder window side effects)"
-- end run
-- END FIXTURE RUNNER
