local M = {}

---@param inst wiremux.Instance
---@return string
function M.default_target_name(inst)
	return "pane-" .. (inst.id:match("%d+") or inst.id)
end

---@param inst wiremux.Instance
---@param state wiremux.State
---@return string
function M.location(inst, state)
	local location
	if inst.window_index and inst.pane_index then
		location = string.format("%s:%s", inst.window_index, inst.pane_index)
	elseif inst.window_index then
		location = tostring(inst.window_index)
	else
		location = inst.window_name or inst.id:match("%d+") or inst.id
	end
	if inst.session_id and inst.session_id ~= state.session_id then
		return inst.session_id .. ":" .. location
	end
	return location
end

---Format a picker row using only the existing pane snapshot.
---@param inst wiremux.Instance
---@param state wiremux.State
---@param action string
---@param name string
---@return string
function M.format_label(inst, state, action, name)
	local marker = action == "send" and "" or "[" .. action .. "]"
	local label = string.format("%-10s %-6s %s", marker, M.location(inst, state), name)
	local window = inst.window_name
	if window and window ~= "" and window ~= name then
		label = label .. " · " .. window
	end
	local command = inst.running_command
	if command and command ~= "" and command ~= name and command ~= window then
		label = label .. " [" .. command .. "]"
	end
	return label
end

---@param inst wiremux.Instance
---@return string
function M.adoption_name(inst)
	local name = inst.target
	if not name or name == "" or name == M.default_target_name(inst) then
		name = inst.running_command
	end
	if not name or name == "" then
		name = "pane"
	end
	return name
end

return M
