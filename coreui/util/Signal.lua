--!strict
-- util/Signal.lua — the subscribe/notify registry every watcher list in the
-- library is built on.
--
--   local changed = Signal.new()
--   local unsub = changed:Connect(function(value) ... end)
--   changed:Fire(42)
--   unsub()
--
-- This existed eight times before it existed once: util/Context.lua kept four
-- (accent consumers, flag registration, flag values, window state),
-- components/Window.lua three (HUD visibility, HUD state, config folder),
-- components/Settings.lua one (config selection) and util/Bind.lua one (registry
-- observers). Every copy was the same fifteen lines — `table.insert`, a reverse
-- loop to unsubscribe, `table.clone` before notifying — and each one had to
-- independently get the third of those right.
--
-- **That third one is the whole reason this is a module.** A listener is allowed
-- to unsubscribe itself (or add another) from inside its own callback, and
-- mutating the array mid-walk shifts it out from under the loop and silently
-- skips the next listener — a control that doesn't re-theme, a HUD row that
-- doesn't repaint, with nothing to show for it. Firing a snapshot is the fix,
-- and it belongs somewhere it can't be forgotten rather than in a comment
-- repeated at eight call sites.
--
-- Deliberately no dependencies — not even util/Log.lua. Errors are reported
-- through the caller's own handler (see FireGuarded), because what a broken
-- listener *means* differs per signal and the message should say so. It also
-- keeps this requirable from util/Bind.lua and util/Context.lua without a cycle.
--
-- Not a BindableEvent: those are deferred, so a listener is resumed at the end
-- of the resumption cycle rather than inside the call that raised it. Several
-- signals here depend on landing synchronously — Context:OnFlag exists so a
-- loader can attribute a flag to whatever it is building *at that instant*.

local Signal = {}
Signal.__index = Signal

export type Signal<T...> = typeof(setmetatable(
	{} :: { _fns: { (T...) -> () } },
	Signal
))

function Signal.new<T...>(): Signal<T...>
	return (setmetatable({ _fns = {} }, Signal) :: any) :: Signal<T...>
end

-- Subscribe. Returns the unsubscribe; calling it twice is harmless.
--
-- Note that this does NOT replay anything to a late subscriber. Several callers
-- want that (`RegisterAccent` paints immediately, `OnConfigFolder` reports the
-- current folder), but what the "current value" *is* differs every time, so they
-- call `fn` themselves right after connecting rather than handing a value here.
function Signal:Connect<T...>(fn: (T...) -> ()): () -> ()
	table.insert(self._fns, fn)
	return function()
		local list = self._fns
		for i = #list, 1, -1 do
			if list[i] == fn then
				table.remove(list, i)
				break
			end
		end
	end
end

-- Notify every listener, synchronously, over a SNAPSHOT of the list — see the
-- header. A listener that throws takes the rest of the broadcast down with it;
-- use FireGuarded where a listener is a host's code rather than ours.
function Signal:Fire<T...>(...: T...)
	for _, fn in table.clone(self._fns) do
		fn(...)
	end
end

-- Fire, but a throwing listener is reported to `onError` and the remaining
-- listeners still run. This is the shape for anything a *host* subscribes to:
-- someone else's bookkeeping blowing up must never take down the control that
-- moved. `onError` gets the error; the caller words the message, because "a
-- flag watcher errored" and "a HUD observer errored" want different text.
function Signal:FireGuarded<T...>(onError: (any) -> (), ...: T...)
	for _, fn in table.clone(self._fns) do
		local ok, err = pcall(fn, ...)
		if not ok then
			onError(err)
		end
	end
end

-- How many listeners. `Context:NotifyFlag` reads this to skip an expensive
-- read-and-encode when nobody is listening at all.
function Signal:Count(): number
	return #self._fns
end

-- Drop every listener. Teardown only.
function Signal:Clear()
	table.clear(self._fns)
end

return Signal
