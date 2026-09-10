# Mail — mod-compat changes

This is your `Mail` addon with four small additions layered on, each one
gated on a specific client DLL being loaded. If none of the five mods
(ClassicAPI, SuperWoW, nampower, UnitXP_SP3, VanillaHelpers) are present,
the addon behaves **exactly** as it did before — every hook below checks
for its mod first and is a silent no-op otherwise.

Two of the five mods, **nampower** and **VanillaHelpers**, aren't touched
at all: nampower is purely combat/spell-cast events, and VanillaHelpers'
file I/O and display-remapping surface has nothing that overlaps with a
mailbox addon. Forcing a hook onto either would just be for show, so
nothing was added for them.

**Nothing here has been run against a live client.** Everything below is
reasoned from your actual `Mail.lua` source and each mod's own
documentation (ClassicAPI's real `docs/API.md`, the UnitXP_SP3 wiki, the
SuperWoW Features wiki). Please treat the first live test as the real
verification step, not this writeup.

## Files

| File | What changed |
|---|---|
| `Mail.lua` | One small, isolated, guarded edit (see below) |
| `Mail.xml` | One line added, loading the new companion file after `Mail.lua` |
| `Mail_ModCompat.lua` | **New file.** All three purely-additive features live here |
| `Mail.toc` | Unchanged |

---

## 1. ClassicAPI — steady-rate mailbox polling

**Where:** directly in `Mail.lua` (the one place I edited the original file
— explained below).

**What it was:** a periodic "check for new mail" heartbeat, paced by a
100-frame counter:

```lua
local x = 0
CreateFrame('Frame', InboxFrame):SetScript('OnUpdate', function()
    if x > 0 then x = x - 1
    elseif not Inbox_opening then x = 100; CheckInbox() end
end)
```

Counting frames instead of time means the real-world gap between
`CheckInbox()` calls is tied to your framerate — about 1.6s at 60fps,
under 0.5s at 200fps, several seconds at low fps. There's no reason this
particular poll needs to be frame-rate coupled at all.

**What changed:** if ClassicAPI's `C_Timer.NewTicker` is available (confirmed
real, documented function — `docs/API.md`, Timer section), the poll now
fires every 2 real seconds, full stop, regardless of framerate. If
`C_Timer` isn't present, the exact original frame-counted loop runs
unchanged — nothing is lost when ClassicAPI isn't loaded.

**Why this one couldn't be a companion-file hook:** the original poll runs
on an anonymous frame created inline (`CreateFrame('Frame', InboxFrame)`)
with no name and no reference kept anywhere Mail.lua exposes — there's no
external handle to disable just that one `OnUpdate`. Wrapping it from
outside would mean the two timers running in parallel, both calling
`CheckInbox()`. So this one change lives directly in `Mail.lua`, wrapped
in a single guarded `if C_Timer... else <original> end` block, clearly
commented, and it's the only place the original file was touched.

**How much this improves things:** honestly, modest, and mostly matters at
the extremes. If you play at a fairly normal, steady framerate, you
probably won't notice a difference — the old cadence was already in a
reasonable range. Where it matters: very high-fps setups were calling
`CheckInbox()` far more often than needed (harmless, but wasteful), and
very low-fps setups were checking for new mail more slowly than intended.
This makes the behavior consistent and correct by design instead of by
coincidence of framerate.

---

## 2. ClassicAPI — chat-link items as they're auto-looted

**Where:** `Mail_ModCompat.lua`, wraps `Mail.Inbox_Open`.

**What it does:** `ClassicAPI` documents a real `## Mail` namespace with
`GetInboxItemLink(messageIndex)` — a function stock 1.12 simply doesn't
have (the native `GetInboxHeaderInfo` gives you sender/subject/etc, never
a clickable item link). Every time `Inbox_OpenAll` or `Inbox_OpenAll_NoFilter`
opens a letter, this now posts the looted item as a clickable chat link,
in the same message style your existing `PrintGoldGained()` already uses
for gold.

**Why this one's new territory, not a fix:** your addon currently loots
silently — no chat feedback on *what* came out of the mailbox, only gold
(via the `PrintGoldGained` you already had). This adds the missing half of
that picture using a function that genuinely didn't exist as an option
before.

**How much this improves things:** you get an itemized, clickable record
of exactly what you pulled from the mailbox during a bulk-open, without
tabbing to your bags. Small but genuinely new — nothing in stock 1.12 or
in the addon today gives you this.

---

## 3. UnitXP_SP3 — notify when a bulk run finishes

**Where:** `Mail_ModCompat.lua`, wraps `Mail.Inbox_Abort`, `Mail.Inbox_Abort2`,
and `Mail.SendMail_Send`.

**What it does:** fires `UnitXP("notify", "taskbarIcon")` and
`UnitXP("notify", "systemSound")` — both real, documented calls, confirmed
against the UnitXP_SP3 wiki — when either "Open AH" / "Open All" finishes
draining the inbox, or a multi-item `SendMail` queue finishes sending.

**The heuristic, stated plainly:** "finished" is detected as "the inbox is
empty right after `Abort` runs." This isn't something either mod tells
you directly — it's an inference from your addon's own state. It correctly
skips notifying when `Abort` fires early (bag full mid-run, or you close
the mailbox yourself) since in both cases you're already at the keyboard.
The one edge case it can misread: if the very last letter left in the box
is a COD/GM one that gets *skipped* rather than opened, the box can end up
empty for a reason unrelated to a clean finish. Rare, and the cost of
getting it "wrong" is just one extra harmless notification — not a
functional problem, just worth knowing it's a heuristic and not a
guarantee.

For sending, notify only fires when `numMessages > 1` — an ordinary
single-item mail already shows success on screen immediately, so a
notification for that would just be noise.

**How much this improves things:** this is the one genuinely new
*capability*, not a tuning fix. Today, if you kick off a bulk open or a
multi-item send and tab away, you have no way to know it's done short of
tabbing back and looking. Now you get a taskbar flash / sound the moment
it actually finishes.

---

## 4. SuperWoW — fix the attachment count display for charge items

**Where:** `Mail_ModCompat.lua`, wraps the real global `SendMailFrame_Update`
(installed at `PLAYER_LOGIN`, after Mail's own hook has taken over that
global — see the comment in the file for why the ordering matters).

**What it was:** SuperWoW's own Features wiki documents that
`GetContainerItemInfo` returns a charge-based item's charge count as a
**negative** number instead of a stack count. Your `hook.SendMailFrame_Update`
only shows the little count badge when `count > 1` — so attaching a
charge item (e.g. a limited-charge trinket/consumable) with SuperWoW
loaded would silently show no count at all.

**What changed:** a small pass runs right after Mail's own update, only
touching the count text/visibility on the attachment slots — it doesn't
touch layout or positioning at all. If it sees a negative count, it shows
the absolute value instead of hiding it.

**How much this improves things:** narrow. This only shows up if you (a)
have SuperWoW loaded and (b) attach a charge-based item — a fairly
uncommon item category. Most sessions you'd never see the bug either way.
It's a correctness fix, not a feature.

---

## Installing

Drop all four files in your `Interface/AddOns/Mail/` folder (overwriting
the existing `Mail.lua` and `Mail.xml`), keeping the folder named `Mail`
as the original README requires. `/reload` or relog. No new SavedVariables,
no new slash commands — everything above triggers automatically based on
which DLLs are actually loaded.
