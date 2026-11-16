# Mail (Patched for WoW 1.12 / Turtle WoW)

> Mailbox enhancement fork with bulk-open, multi-attachment sending, optional client-mod integrations, and a UTF-8-safe Recent Senders picker for replying to non-English names.

## Client Mods Used
| Mod | Purpose in this addon | Required? |
|---|---|---|
| ClassicAPI | `C_Timer.NewTicker` for steady 2s inbox polling; `GetInboxItemLink` for chat-linking looted items | Optional |
| UnitXP_SP3 | `UnitXP("notify", ...)` taskbar flash and system sound when bulk open/send finishes | Optional |
| SuperWoW | Fixes negative charge count display on attached charge-based items | Optional |

*(The Recent Senders history and dropdown picker in `Mail_RecentSenders.lua` are pure Vanilla Lua 5.0 and work with or without any client DLL mods.)*

## Features
- **Recent Mail Senders Picker (`Mail_RecentSenders.lua`):**
  - Automatically records replyable inbox senders (exact UTF-8 names, including Chinese, Korean, Russian, and special characters) into `Mail_RecentSenders` (`SavedVariables`) on `MAIL_SHOW`, `MAIL_INBOX_UPDATE`, and right before `TakeInboxItem`, `TakeInboxMoney`, `DeleteInboxItem`, or `Mail.Inbox_Open` runs.
  - Prevents losing the ability to reply when an item-only or gold-only mail is auto-deleted by the server immediately after looting.
  - Adds a compact dropdown button next to `SendMailNameEditBox` (`To:`) showing the 12 most recent senders with item/gold/subject tags; clicking any entry fills `SendMailNameEditBox` directly without typing.
- **Multi-Attachment Sending & Auto-Complete (`Mail.lua`):**
  - Attach up to 21 items per send batch, auto-splitting into sequential mails with progress subjects (`[1/N]`).
  - Name auto-complete from saved names, friends, and guild roster.
- **Bulk Inbox Looting (`Mail.lua`):**
  - `Open AH` and `Open All` buttons, plus right-click quick-loot on inbox rows.
- **Optional Client Mod Enhancements (`Mail_ModCompat.lua`):**
  - Prints clickable item links as items are auto-looted (ClassicAPI).
  - Taskbar/sound notification when bulk open or multi-mail send completes (UnitXP_SP3).
  - Displays absolute charge counts for charge-based items (SuperWoW).

## What Was Added / Improved
- **Added `Mail_RecentSenders.lua`:** Pure Vanilla Lua 5.0 companion module with `SavedVariables` persistence (`Mail_RecentSenders`, up to 40 entries per realm), UTF-8-safe tag truncation, pre-loot sender capture hooks, and the `MailRecentSendersButton` / `MailRecentSendersMenu` UI.
- **Added Debug Tracing & History Commands:** `/mailtrace` toggles timestamped capture/selection trace logs; `/mailrecent` lists saved senders and `/mailrecent clear` clears history.
- **Updated `Mail.toc` & `Mail.xml`:** Added `Mail_RecentSenders` to `SavedVariables` and loaded `Mail_RecentSenders.lua` after `Mail_ModCompat.lua` with zero edits to upstream `Mail.lua`.

## Usage
- **Select a recent sender:** Open the **Send Mail** tab and click the dropdown arrow button right next to the `To:` box (`SendMailNameEditBox`).
- **Debug tracing:** `/mailtrace` — toggles live trace output for inbox scans, pre-loot captures, and recipient selection.
- **Manage history:** `/mailrecent` — prints the top 10 saved senders for the current realm; `/mailrecent clear` — clears saved history.

## Credits & License
- Original addon: `shirsig`
- Mod compatibility & Recent Senders patch: Fork additions in `Mail_ModCompat.lua` and `Mail_RecentSenders.lua`
- License: Same as original addon unless stated otherwise.
