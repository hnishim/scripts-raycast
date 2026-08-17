#!/usr/bin/osascript

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Export Active PowerPoint to PDF
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 📄

# Documentation:
# @raycast.description アクティブなPowerPoint資料を同じフォルダへPDF化

use framework "Foundation"
use scripting additions

property commandTitle : "PowerPoint PDF化"

on run
	try
		set sourceFileAlias to my activePresentationFile()
		set sourcePOSIXPath to POSIX path of sourceFileAlias
		set targetPOSIXPath to my pdfPathFor(sourcePOSIXPath)

		if (my checkExistence(targetPOSIXPath)) then
			if (my confirmOverwrite(targetPOSIXPath)) is false then
				return
			end if
		end if

		set targetFile to POSIX file targetPOSIXPath
		tell application "Microsoft PowerPoint"
			set presentationToExport to active presentation
			save presentationToExport in targetFile as save as PDF
		end tell

		if not (my checkExistence(targetPOSIXPath)) then
			error "PDFの保存後にファイルを確認できませんでした。"
		end if

		my notify("PDFを作成しました", targetPOSIXPath)
	on error errorMessage number errorNumber
		if errorNumber is -128 then
			return
		end if

		my notify("PDF化に失敗しました", my userFacingError(errorMessage))
		error errorMessage number errorNumber
	end try
end run

on activePresentationFile()
	tell application "Microsoft PowerPoint"
		if (count of presentations) is 0 then
			error "PowerPointでプレゼンテーションが開かれていません。"
		end if

		set activePresentation to active presentation
		set sourceFullName to full name of activePresentation
	end tell

	try
		return sourceFullName as alias
	on error
		try
			return (POSIX file sourceFullName) as alias
		on error
			error "未保存のプレゼンテーションです。先にPPTXとして保存してください。"
		end try
	end try
end activePresentationFile

on pdfPathFor(sourcePOSIXPath)
	set savedDelimiters to AppleScript's text item delimiters

	try
		set AppleScript's text item delimiters to "/"
		set pathItems to text items of sourcePOSIXPath
		set fileName to last item of pathItems
		set directoryItems to items 1 thru -2 of pathItems
		set directoryPath to directoryItems as text

		set AppleScript's text item delimiters to "."
		set nameItems to text items of fileName
		if (count of nameItems) is greater than 1 then
			set fileStem to (items 1 thru -2 of nameItems) as text
		else
			set fileStem to fileName
		end if

		set AppleScript's text item delimiters to savedDelimiters
		return directoryPath & "/" & fileStem & ".pdf"
	on error errorMessage number errorNumber
		set AppleScript's text item delimiters to savedDelimiters
		error errorMessage number errorNumber
	end try
end pdfPathFor

on checkExistence(posixPath)
	return (current application's NSFileManager's defaultManager()'s fileExistsAtPath_(posixPath)) as boolean
end checkExistence

on notify(notificationTitle, notificationMessage)
	try
		using terms from application "Standard Additions"
			display notification notificationMessage with title commandTitle subtitle notificationTitle
		end using terms from
	on error
		log notificationMessage
	end try
end notify

on confirmOverwrite(targetPOSIXPath)
	using terms from application "Standard Additions"
		set dialogResult to display dialog ¬
			("同名のPDFがすでにあります。\n\n" & targetPOSIXPath & "\n\n上書きしますか？") ¬
			with title commandTitle ¬
			buttons {"キャンセル", "上書き"} ¬
			default button "キャンセル" ¬
			cancel button "キャンセル"
	end using terms from
	return (button returned of dialogResult) is "上書き"
end confirmOverwrite

on userFacingError(errorMessage)
	if errorMessage is "" then
		return "PowerPointからエラーが返されました。"
	end if
	return errorMessage
end userFacingError
