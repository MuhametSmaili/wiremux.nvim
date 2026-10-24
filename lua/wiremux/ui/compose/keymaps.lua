local M = {}

-- Track combined mapping modes separately so a native deletion can relinquish just one mode.
local combined_modes = {
	[""] = { "n", "x", "s", "o" },
	v = { "x", "s" },
	["!"] = { "i", "c" },
}

---Normalize a keymap entry into a list of { key, modes, desc }
---@param entry table? Single keymap or array of keymaps
---@return { key: string, modes: string[], desc?: string }[]
function M.normalize(entry)
	if not entry then
		return {}
	end

	local entries = type(entry[1]) == "string" and { entry } or entry
	local result = {}
	for _, km in ipairs(entries) do
		local configured_modes = km.mode or "n"
		if type(configured_modes) == "string" then
			configured_modes = { configured_modes }
		end
		local modes, seen = {}, {}
		for _, mode in ipairs(configured_modes) do
			for _, concrete_mode in ipairs(combined_modes[mode] or { mode }) do
				if not seen[concrete_mode] then
					table.insert(modes, concrete_mode)
					seen[concrete_mode] = true
				end
			end
		end
		table.insert(result, { key = km[1], modes = modes, desc = km.desc })
	end
	return result
end

---Find the first key mapped for a given mode
---@param entry table? Keymap config entry
---@param target_mode string Mode to search for
---@return string?
function M.find_key_for_mode(entry, target_mode)
	for _, km in ipairs(M.normalize(entry)) do
		for _, m in ipairs(km.modes) do
			if m == target_mode then
				return km.key
			end
		end
	end
end

return M
