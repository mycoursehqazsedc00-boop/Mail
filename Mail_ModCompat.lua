-- Mail_ModCompat.lua
--
-- Companion file for the Mail addon. Adds small, additive features that only
-- activate if specific client DLL mods are loaded (ClassicAPI, UnitXP_SP3,
-- SuperWoW). If none of them are present, every hook below is a no-op and
-- Mail behaves exactly as it does without this file.
--
-- IMPORTANT: this file must load AFTER Mail.lua (see Mail.xml -- the
-- <Script file="Mail_ModCompat.lua"/> line must come after
-- <Script file="Mail.lua"/>). Every hook here wraps a function that lives on
-- the `Mail` table (or, for SendMailFrame_Update, the real global that
-- Mail.lua installs at PLAYER_LOGIN), so Mail.lua has to have run first.
--
-- What's confirmed vs. assumed, stated plainly:
--   - GetInboxItemLink / C_Timer.NewTicker: confirmed against ClassicAPI's
--     actual docs/API.md (the "## Mail" and "## Timer" sections).
--   - UnitXP("notify", ...) and the pcall(UnitXP,"nop","nop") existence
--     check: confirmed against the UnitXP_SP3 wiki (Home page).
--   - The "mailbox is empty => the bulk run finished cleanly" signal used
--     for the notify feature is a HEURISTIC, not something either mod
--     documents. It's a reasonable proxy, not a guaranteed one -- see the
--     README for the exact case where it can miss.
--   - None of this has been run against a live client. Say so plainly:
--     it's reasoned from the addon's real source and each mod's own
--     documentation, not verified in-game.

do
	----------------------------------------------------------------------
	-- Feature 1: ClassicAPI -- chat-link the item as each piece of mail
	-- is auto-looted (Inbox_Open is shared by both the "Open AH" and
	-- "Open All" buttons, so this covers both).
	----------------------------------------------------------------------
	local orig_Inbox_Open = Mail.Inbox_Open
	Mail.Inbox_Open = function(i, ...)
		if GetInboxItemLink then
			local ok, link = pcall(GetInboxItemLink, i)
			if ok and link then
				DEFAULT_CHAT_FRAME:AddMessage('Mail: looted ' .. link, 0.41, .8, .94)
			end
		end
		return orig_Inbox_Open(i, ...)
	end
end

do
	----------------------------------------------------------------------
	-- Feature 2: UnitXP_SP3 -- notify (taskbar flash + system sound) when
	-- a bulk operation finishes: either open-all flow draining the inbox,
	-- or a multi-item SendMail queue finishing.
	--
	-- Existence check is the mod's own recommended idiom (UnitXP_SP3 wiki,
	-- Home page): pcall(UnitXP, "nop", "nop") returns true iff the DLL is
	-- loaded, and is itself safe to call even if UnitXP is nil.
	----------------------------------------------------------------------
	local function Notify()
		if pcall(UnitXP, 'nop', 'nop') then
			pcall(UnitXP, 'notify', 'taskbarIcon')
			pcall(UnitXP, 'notify', 'systemSound')
		end
	end

	-- Heuristic: only fire when the inbox is empty right after Abort runs.
	-- This means "the queue actually drained," and skips the cases where
	-- Abort fired early (bag full mid-run, or the player closed the
	-- mailbox manually) -- in both of those the player is already at the
	-- keyboard, so a notify would be noise, not a signal.
	-- What this can miss: if the very last letter in the box happens to
	-- be a COD/GM one that gets skipped rather than opened, the box can
	-- still read "empty of takeable mail" while GetInboxNumItems() is 0
	-- for an unrelated reason. Rare, and harmless if it happens (you just
	-- get an extra notify), but worth knowing the heuristic isn't exact.
	local function NotifyIfInboxDrained(wasOpening)
		if wasOpening and GetInboxNumItems() == 0 then
			Notify()
		end
	end

	if Mail.Inbox_Abort then
		local orig_Inbox_Abort = Mail.Inbox_Abort
		Mail.Inbox_Abort = function(...)
			local wasOpening = Mail.Inbox_opening
			local ret = orig_Inbox_Abort(...)
			NotifyIfInboxDrained(wasOpening)
			return ret
		end
	end

	if Mail.Inbox_Abort2 then
		local orig_Inbox_Abort2 = Mail.Inbox_Abort2
		Mail.Inbox_Abort2 = function(...)
			local wasOpening = Mail.Inbox_opening
			local ret = orig_Inbox_Abort2(...)
			NotifyIfInboxDrained(wasOpening)
			return ret
		end
	end

	if Mail.SendMail_Send then
		local orig_SendMail_Send = Mail.SendMail_Send
		Mail.SendMail_Send = function(...)
			local numMessages = Mail.SendMail_state and Mail.SendMail_state.numMessages
			local ret = orig_SendMail_Send(...)
			-- only notify for an actual multi-item queue finishing, not
			-- every single ordinary one-item mail (that's already
			-- immediately visible on screen when it succeeds)
			if numMessages and numMessages > 1 and not Mail.SendMail_sending then
				Notify()
			end
			return ret
		end
	end
end

do
	----------------------------------------------------------------------
	-- Feature 3: SuperWoW -- fix the attachment-count display for
	-- charge-based items. SuperWoW's Features wiki documents that
	-- GetContainerItemInfo returns charges as a NEGATIVE count instead of
	-- a stack count. Mail's hook.SendMailFrame_Update only shows the count
	-- text when count > 1, so a negative charge count was silently hidden.
	-- This runs a small post-pass after Mail's own update, touching only
	-- the Count fontstring text/visibility -- it doesn't touch layout.
	--
	-- Must install AFTER Mail's own PLAYER_LOGIN handler has swapped its
	-- hook.SendMailFrame_Update into the real global SendMailFrame_Update
	-- (that swap is what Mail.lua's PLAYER_LOGIN handler does). Relies on
	-- the same "same-event frames dispatch in registration/load order"
	-- behavior that Mail.lua's own hook-install system already depends on
	-- -- which is why this file must load after Mail.lua in Mail.xml.
	----------------------------------------------------------------------
	local f = CreateFrame('Frame')
	f:RegisterEvent('PLAYER_LOGIN')
	f:SetScript('OnEvent', function()
		if not (SUPERWOW_VERSION and SendMailFrame_Update) then return end

		local orig_SMFU = SendMailFrame_Update
		SendMailFrame_Update = function(...)
			local ret = orig_SMFU(...)
			for i = 1, 21 do
				local btn = _G['MailAttachment' .. i]
				if btn and btn.item then
					local ok, texture, count = pcall(GetContainerItemInfo, unpack(btn.item))
					if ok and count and count < 0 then
						local countText = _G[btn:GetName() .. 'Count']
						if countText then
							countText:SetText(-count)
							countText:Show()
						end
					end
				end
			end
			return ret
		end
	end)
end
