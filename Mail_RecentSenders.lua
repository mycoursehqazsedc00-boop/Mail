-- Mail_RecentSenders.lua
--
-- Pure Vanilla Lua 5.0 companion module for the Mail addon.
-- Automatically records recent replyable mail senders (including non-ASCII /
-- UTF-8 names such as Chinese, Korean, Russian, etc.) BEFORE attachments or
-- money are looted and the mail is auto-deleted by the server.
-- Adds a compact dropdown button next to SendMailNameEditBox so the user can
-- select any recent sender with one click without needing to type non-English
-- characters.
--
-- Also provides `/mailtrace` (debug tracing toggle) and `/mailrecent`
-- (inspect or clear saved sender history).

do
	local _G = getfenv(0)

	local MAX_HISTORY = 40
	local MAX_VISIBLE_ROWS = 12
	local ROW_HEIGHT = 18
	local MENU_WIDTH = 240

	local isInitialized = false
	local mailButton
	local mailMenu
	local menuRows = {}
	local emptyRow

	local function GetRealmKey()
		local realm = GetCVar and GetCVar("realmName")
		if not realm or realm == "" then
			realm = "Default"
		end
		return realm
	end

	local function EnsureDB()
		if type(_G.Mail_RecentSenders) ~= "table" then
			_G.Mail_RecentSenders = {}
		end
		local db = _G.Mail_RecentSenders
		if db._trace == nil then
			db._trace = false
		end
		local key = GetRealmKey()
		if type(db[key]) ~= "table" then
			db[key] = {}
		end
		return db[key], db
	end

	local function Trace(msg)
		local _, db = EnsureDB()
		if db._trace and DEFAULT_CHAT_FRAME then
			local ts = date and date("%H:%M:%S") or "00:00:00"
			DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[Mail Trace " .. ts .. "]|r " .. tostring(msg))
		end
	end

	local function SafeTruncate(str, maxBytes)
		if not str or str == "" then
			return ""
		end
		if strlen(str) <= maxBytes then
			return str
		end
		-- Avoid cutting in the middle of a multi-byte UTF-8 sequence
		local cut = maxBytes
		while cut > 0 do
			local b = strbyte(str, cut)
			if not b or b < 128 or b >= 192 then
				-- If byte at `cut` is a UTF-8 leading byte (>=192), step back 1 so we don't leave a dangling lead byte
				if b and b >= 192 then
					cut = cut - 1
				end
				break
			end
			cut = cut - 1
		end
		if cut <= 0 then
			return ""
		end
		return strsub(str, 1, cut) .. "..."
	end

	local function BuildTag(subject, money, hasItem)
		if hasItem then
			if subject and subject ~= "" then
				return "[Item] " .. SafeTruncate(subject, 18)
			end
			return "[Item]"
		elseif money and money > 0 then
			local g = floor(money / 10000)
			if g > 0 then
				return "[" .. g .. "g]"
			end
			return "[Gold]"
		elseif subject and subject ~= "" then
			return SafeTruncate(subject, 22)
		end
		return ""
	end

	local function RecordSender(sender, subject, money, hasItem, canReply, isGM, promoteIfExisting, sourceLabel)
		if not sender or sender == "" then
			return false
		end
		local playerName = UnitName("player")
		if playerName and sender == playerName then
			return false
		end
		if isGM or not canReply then
			Trace("Skip (" .. tostring(sourceLabel) .. "): " .. sender .. " (isGM=" .. tostring(isGM) .. ", canReply=" .. tostring(canReply) .. ")")
			return false
		end

		local history = EnsureDB()
		local tag = BuildTag(subject, money, hasItem)
		local now = time and time() or 0
		local n = getn(history)
		local foundIndex = nil

		for i = 1, n do
			if history[i] and history[i].sender == sender then
				foundIndex = i
				break
			end
		end

		if foundIndex then
			if not promoteIfExisting then
				-- Passive inbox scan: only fill missing tag if we had none
				if (not history[foundIndex].tag or history[foundIndex].tag == "") and tag ~= "" then
					history[foundIndex].tag = tag
				end
				return false
			end
			local entry = tremove(history, foundIndex)
			if tag ~= "" then
				entry.tag = tag
			end
			entry.time = now
			tinsert(history, 1, entry)
			Trace("Promoted (" .. tostring(sourceLabel) .. "): " .. sender .. " " .. (entry.tag or ""))
			return true
		end

		local entry = {
			sender = sender,
			tag = tag,
			time = now,
		}
		tinsert(history, 1, entry)
		while getn(history) > MAX_HISTORY do
			tremove(history)
		end
		Trace("Saved (" .. tostring(sourceLabel) .. "): " .. sender .. " " .. tag)
		return true
	end

	local function CaptureInboxSlot(index, promoteIfExisting, sourceLabel)
		if not index or not GetInboxHeaderInfo then
			return
		end
		local _, _, sender, subject, money, _, _, hasItem, _, _, _, canReply, isGM = GetInboxHeaderInfo(index)
		RecordSender(sender, subject, money, hasItem, canReply, isGM, promoteIfExisting, sourceLabel)
	end

	local function ScanInbox(sourceLabel)
		if not GetInboxNumItems then
			return
		end
		local num = GetInboxNumItems()
		if not num or num <= 0 then
			return
		end
		-- Scan backwards so newest/lowest-index mails end up at the top when first discovered
		for i = num, 1, -1 do
			CaptureInboxSlot(i, false, sourceLabel)
		end
	end

	local function SelectRecentSender(sender)
		if not sender or sender == "" then
			return
		end
		-- Clear Mail_To so Mail.lua's SendMailNameEditBox:SetText wrapper does not block SetText
		_G.Mail_To = nil
		if SendMailNameEditBox then
			SendMailNameEditBox:SetText(sender)
			SendMailNameEditBox:HighlightText(0, 0)
		end
		if MailAutoCompleteBox and MailAutoCompleteBox:IsVisible() then
			MailAutoCompleteBox:Hide()
		end
		if mailMenu then
			mailMenu:Hide()
		end
		if MailSubjectEditBox then
			MailSubjectEditBox:SetFocus()
		elseif SendMailSubjectEditBox then
			SendMailSubjectEditBox:SetFocus()
		end
		if SendMailFrame_CanSend then
			SendMailFrame_CanSend()
		end
		Trace("Selected sender into To: " .. sender)
	end

	local function RefreshMenu()
		if not mailMenu then
			return
		end
		local history = EnsureDB()
		local count = getn(history)
		local visible = count
		if visible > MAX_VISIBLE_ROWS then
			visible = MAX_VISIBLE_ROWS
		end

		if visible == 0 then
			for i = 1, MAX_VISIBLE_ROWS do
				menuRows[i]:Hide()
			end
			emptyRow:Show()
			mailMenu:SetHeight(ROW_HEIGHT + 16)
			return
		end

		emptyRow:Hide()
		for i = 1, MAX_VISIBLE_ROWS do
			local row = menuRows[i]
			if i <= visible then
				local entry = history[i]
				row.senderName = entry.sender
				row.nameText:SetText(entry.sender)
				row.tagText:SetText(entry.tag or "")
				row:Show()
			else
				row.senderName = nil
				row:Hide()
			end
		end
		mailMenu:SetHeight((visible * ROW_HEIGHT) + 16)
	end

	local function CreateUI()
		if mailButton or not SendMailNameEditBox or not SendMailFrame then
			return
		end

		mailButton = CreateFrame("Button", "MailRecentSendersButton", SendMailFrame)
		mailButton:SetWidth(20)
		mailButton:SetHeight(20)
		mailButton:SetPoint("LEFT", SendMailNameEditBox, "RIGHT", 2, 0)
		mailButton:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
		mailButton:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
		mailButton:SetDisabledTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Disabled")
		mailButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

		mailButton:SetScript("OnEnter", function()
			GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
			GameTooltip:SetText("Recent Mail Senders", 1, 1, 1)
			GameTooltip:AddLine("Click to fill the recipient from recent inbox senders (supports non-English names).", nil, nil, nil, 1)
			GameTooltip:Show()
		end)
		mailButton:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		mailButton:SetScript("OnClick", function()
			if mailMenu:IsVisible() then
				mailMenu:Hide()
			else
				if MailAutoCompleteBox and MailAutoCompleteBox:IsVisible() then
					MailAutoCompleteBox:Hide()
				end
				RefreshMenu()
				mailMenu:Show()
			end
		end)

		mailMenu = CreateFrame("Frame", "MailRecentSendersMenu", SendMailFrame)
		mailMenu:SetWidth(MENU_WIDTH)
		mailMenu:SetHeight(ROW_HEIGHT + 16)
		mailMenu:SetPoint("TOPLEFT", SendMailNameEditBox, "BOTTOMLEFT", 0, -2)
		mailMenu:SetFrameStrata("DIALOG")
		mailMenu:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 5, right = 5, top = 5, bottom = 5 },
		})
		if TOOLTIP_DEFAULT_COLOR then
			mailMenu:SetBackdropBorderColor(TOOLTIP_DEFAULT_COLOR.r, TOOLTIP_DEFAULT_COLOR.g, TOOLTIP_DEFAULT_COLOR.b)
		else
			mailMenu:SetBackdropBorderColor(0.8, 0.8, 0.8)
		end
		if TOOLTIP_DEFAULT_BACKGROUND_COLOR then
			mailMenu:SetBackdropColor(TOOLTIP_DEFAULT_BACKGROUND_COLOR.r, TOOLTIP_DEFAULT_BACKGROUND_COLOR.g, TOOLTIP_DEFAULT_BACKGROUND_COLOR.b, 0.95)
		else
			mailMenu:SetBackdropColor(0.05, 0.05, 0.1, 0.95)
		end
		mailMenu:EnableMouse(true)
		mailMenu:Hide()

		emptyRow = mailMenu:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		emptyRow:SetPoint("TOPLEFT", mailMenu, "TOPLEFT", 10, -10)
		emptyRow:SetText("No recent mail senders yet")
		emptyRow:Hide()

		for i = 1, MAX_VISIBLE_ROWS do
			local row = CreateFrame("Button", "MailRecentSendersRow" .. i, mailMenu)
			row:SetWidth(MENU_WIDTH - 12)
			row:SetHeight(ROW_HEIGHT)
			row:SetPoint("TOPLEFT", mailMenu, "TOPLEFT", 6, -8 - ((i - 1) * ROW_HEIGHT))
			row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

			local nameText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
			nameText:SetPoint("LEFT", row, "LEFT", 4, 0)
			nameText:SetWidth(115)
			nameText:SetJustifyH("LEFT")
			row.nameText = nameText

			local tagText = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
			tagText:SetPoint("RIGHT", row, "RIGHT", -4, 0)
			tagText:SetWidth(100)
			tagText:SetJustifyH("RIGHT")
			row.tagText = tagText

			row:SetScript("OnClick", function()
				if this.senderName then
					SelectRecentSender(this.senderName)
				end
			end)

			menuRows[i] = row
		end

		local origOnHide = SendMailFrame:GetScript("OnHide")
		SendMailFrame:SetScript("OnHide", function()
			if mailMenu and mailMenu:IsVisible() then
				mailMenu:Hide()
			end
			if origOnHide then
				return origOnHide()
			end
		end)
	end

	local function InstallHooks()
		-- Pre-hook Blizzard mail actions so sender is captured even if the server deletes the mail immediately
		if TakeInboxItem then
			local origTakeInboxItem = TakeInboxItem
			TakeInboxItem = function(index, itemIndex)
				CaptureInboxSlot(index, true, "TakeInboxItem")
				return origTakeInboxItem(index, itemIndex)
			end
		end

		if TakeInboxMoney then
			local origTakeInboxMoney = TakeInboxMoney
			TakeInboxMoney = function(index)
				CaptureInboxSlot(index, true, "TakeInboxMoney")
				return origTakeInboxMoney(index)
			end
		end

		if DeleteInboxItem then
			local origDeleteInboxItem = DeleteInboxItem
			DeleteInboxItem = function(index)
				CaptureInboxSlot(index, true, "DeleteInboxItem")
				return origDeleteInboxItem(index)
			end
		end

		-- Pre-hook Mail.Inbox_Open (used by right-click quick-loot, Open AH, and Open All)
		if Mail and Mail.Inbox_Open then
			local origInboxOpen = Mail.Inbox_Open
			Mail.Inbox_Open = function(index, a2, a3)
				CaptureInboxSlot(index, true, "Inbox_Open")
				return origInboxOpen(index, a2, a3)
			end
		end
	end

	local function RegisterSlashCommands()
		_G.SLASH_MAILTRACE1 = "/mailtrace"
		_G.SlashCmdList["MAILTRACE"] = function()
			local _, db = EnsureDB()
			db._trace = not db._trace
			if DEFAULT_CHAT_FRAME then
				DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffMail RecentSenders trace:|r " .. (db._trace and "|cff00ff00ON|r" or "|cffff4444OFF|r"))
			end
		end

		_G.SLASH_MAILRECENT1 = "/mailrecent"
		_G.SlashCmdList["MAILRECENT"] = function(msg)
			local cmd = strlower(msg or "")
			local history = EnsureDB()
			if cmd == "clear" then
				local n = getn(history)
				for i = n, 1, -1 do
					tremove(history, i)
				end
				if mailMenu and mailMenu:IsVisible() then
					RefreshMenu()
				end
				if DEFAULT_CHAT_FRAME then
					DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffMail RecentSenders:|r Cleared history.")
				end
				return
			end

			local n = getn(history)
			if DEFAULT_CHAT_FRAME then
				DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffMail RecentSenders (" .. GetRealmKey() .. "):|r " .. n .. " saved")
				local limit = n
				if limit > 10 then
					limit = 10
				end
				for i = 1, limit do
					local e = history[i]
					DEFAULT_CHAT_FRAME:AddMessage("  " .. i .. ". " .. tostring(e.sender) .. " " .. tostring(e.tag or ""))
				end
			end
		end
	end

	local f = CreateFrame("Frame")
	f:RegisterEvent("PLAYER_LOGIN")
	f:RegisterEvent("MAIL_SHOW")
	f:RegisterEvent("MAIL_INBOX_UPDATE")
	f:RegisterEvent("MAIL_CLOSED")
	f:SetScript("OnEvent", function()
		if event == "PLAYER_LOGIN" then
			if not isInitialized then
				isInitialized = true
				EnsureDB()
				CreateUI()
				InstallHooks()
				RegisterSlashCommands()
			end
		elseif event == "MAIL_SHOW" or event == "MAIL_INBOX_UPDATE" then
			ScanInbox(event)
		elseif event == "MAIL_CLOSED" then
			if mailMenu and mailMenu:IsVisible() then
				mailMenu:Hide()
			end
		end
	end)
end
