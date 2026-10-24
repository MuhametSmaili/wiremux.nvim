---Public actions for the current Compose draft. These do not open a draft or act on tmux targets.
---@class wiremux.compose
local M = {}

---@class wiremux.compose.ActionOptions
---@field buf? integer Compose buffer; omitted or 0 means the current buffer

---@alias wiremux.compose.ActionReason "no_session"|"stale_buffer"|"hidden"|"busy"

---Confirm all pages. Acceptance does not imply successful delivery.
---@param opts? wiremux.compose.ActionOptions
---@return boolean accepted, wiremux.compose.ActionReason? reason
function M.send(opts)
	return require("wiremux.ui.compose").dispatch("send", opts)
end

---Close according to close_behavior, preserving the existing draft policy.
---@param opts? wiremux.compose.ActionOptions
---@return boolean accepted, wiremux.compose.ActionReason? reason
function M.close(opts)
	return require("wiremux.ui.compose").dispatch("close", opts)
end

---Hide the draft and append the next non-empty compose input.
---@param opts? wiremux.compose.ActionOptions
---@return boolean accepted, wiremux.compose.ActionReason? reason
function M.append_next(opts)
	return require("wiremux.ui.compose").dispatch("append_next", opts)
end

---Discard this page; close the draft if it is the last page.
---@param opts? wiremux.compose.ActionOptions
---@return boolean accepted, wiremux.compose.ActionReason? reason
function M.discard(opts)
	return require("wiremux.ui.compose").dispatch("discard", opts)
end

---Pick a file and insert its reference at the compose cursor.
---@param opts? wiremux.compose.ActionOptions
---@return boolean accepted, wiremux.compose.ActionReason? reason
function M.files(opts)
	return require("wiremux.ui.compose").dispatch("files", opts)
end

---Delete this page; clear the page if it is the last one.
---@param opts? wiremux.compose.ActionOptions
---@return boolean accepted, wiremux.compose.ActionReason? reason
function M.delete_page(opts)
	return require("wiremux.ui.compose").dispatch("delete_page", opts)
end

---Preview the placeholder at the compose cursor, or focus its open preview.
---@param opts? wiremux.compose.ActionOptions
---@return boolean accepted, wiremux.compose.ActionReason? reason
function M.preview_placeholder(opts)
	return require("wiremux.ui.compose").dispatch("preview_placeholder", opts)
end

---Select the previous page.
---@param opts? wiremux.compose.ActionOptions
---@return boolean accepted, wiremux.compose.ActionReason? reason
function M.previous(opts)
	return require("wiremux.ui.compose").dispatch("previous", opts)
end

---Select the next page.
---@param opts? wiremux.compose.ActionOptions
---@return boolean accepted, wiremux.compose.ActionReason? reason
function M.next(opts)
	return require("wiremux.ui.compose").dispatch("next", opts)
end

return M
