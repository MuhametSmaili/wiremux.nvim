---@module 'luassert'

local keymaps = require("wiremux.ui.compose.keymaps")

-- Fixed test bindings: behavior tests must not depend on the shipping defaults.
local TEST_CONFIG = {
	width = 0.6,
	height = 0.4,
	title = " Test Draft ",
	border = "rounded",
	style = "minimal",
	on_new_payload = "append",
	close_behavior = "hide",
	wo = { wrap = true, number = false },
	keymaps = {
		send = { "<CR>", mode = "n" },
		close = { "q", mode = "n" },
		append_next = { "<F2>", mode = "n" },
		discard = { "Q", mode = "n" },
		delete_page = { "<C-x>", mode = "n" },
		preview_placeholder = { "K", mode = "n" },
		previous = { "<C-p>", mode = "n" },
		next = { "<C-n>", mode = "n" },
	},
}

local MODULES = {
	"wiremux.ui.compose",
	"wiremux.ui.compose.view",
	"wiremux.config",
	"wiremux.context",
	"wiremux.picker",
	"wiremux.utils.notify",
}

describe("compose UI", function()
	local compose, settings, event_group
	local original_modules, original_confirm, original_exec_autocmds, buffers_before

	local function mapping(key, mode)
		local callback = vim.fn.maparg(key, mode or "n", false, true).callback
		assert.is_function(callback, "Missing test mapping: " .. (mode or "n") .. " " .. key)
		return callback
	end

	local function buffer_mapping(buf, key, mode)
		local result
		vim.api.nvim_buf_call(buf, function()
			result = vim.fn.maparg(key, mode or "n", false, true)
		end)
		return result
	end

	local function decoration(name)
		local value = vim.api.nvim_win_get_config(0)[name]
		if type(value) == "string" then
			return value
		end
		local parts = {}
		for _, chunk in ipairs(value or {}) do
			table.insert(parts, chunk[1])
		end
		return table.concat(parts)
	end

	local function text()
		return table.concat(vim.api.nvim_buf_get_lines(compose.get_buf(), 0, -1, false), "\n")
	end

	-- Only assemble the view input; option validation belongs in config_spec.lua.
	local function open(value, opts)
		opts = opts or {}
		compose.open(value, {
			config = vim.tbl_extend("force", {}, settings, opts.config or {}),
			source = opts.source,
			on_confirm = opts.on_confirm or function() end,
			on_preview = opts.on_preview,
			on_cancel = opts.on_cancel,
		})
		return compose.get_buf()
	end

	before_each(function()
		original_modules = {}
		for _, name in ipairs(MODULES) do
			original_modules[name] = package.loaded[name]
			package.loaded[name] = nil
		end
		original_confirm = vim.fn.confirm
		original_exec_autocmds = vim.api.nvim_exec_autocmds
		buffers_before = {}
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			buffers_before[buf] = true
		end
		settings = vim.deepcopy(TEST_CONFIG)
		event_group = vim.api.nvim_create_augroup("wiremux_compose_test_user", { clear = true })
		compose = require("wiremux.ui.compose")
	end)

	after_each(function()
		vim.fn.confirm = original_confirm
		vim.api.nvim_exec_autocmds = original_exec_autocmds
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if not buffers_before[buf] and vim.api.nvim_buf_is_valid(buf) then
				vim.api.nvim_buf_delete(buf, { force = true })
			end
		end
		vim.api.nvim_del_augroup_by_id(event_group)
		vim.wait(1) -- Drain callbacks queued by file/preview pickers after finalizing the draft.
		for _, name in ipairs(MODULES) do
			package.loaded[name] = original_modules[name]
		end
	end)

	describe("public actions", function()
		before_each(function()
			settings.keymaps = {}
			settings.use_default_keymaps = false
		end)

		it("returns no_session for every action when no draft exists", function()
			local api = require("wiremux.compose")
			for _, name in ipairs({
				"send",
				"close",
				"append_next",
				"discard",
				"files",
				"delete_page",
				"preview_placeholder",
				"previous",
				"next",
			}) do
				local accepted, reason = api[name]()
				assert.is_false(accepted, name)
				assert.are.equal("no_session", reason, name)
			end
		end)

		it("uses the current buffer and sends its latest edits when options are omitted", function()
			local sent
			local buf = open("draft", {
				on_confirm = function(pages)
					sent = pages[1].text
				end,
			})
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "edited draft" })

			assert.is_true(require("wiremux.compose").send())

			assert.are.equal("edited draft", sent)
		end)

		it("accepts buffer zero as the current compose buffer", function()
			open("draft")

			assert.is_true(require("wiremux.compose").discard({ buf = 0 }))

			assert.is_nil(compose.get_buf())
		end)

		it("does not fall back from an unrelated current buffer to the visible draft", function()
			local origin = vim.api.nvim_get_current_win()
			local buf = open("draft")
			vim.api.nvim_set_current_win(origin)

			local accepted, reason = require("wiremux.compose").discard()

			assert.is_false(accepted)
			assert.are.equal("stale_buffer", reason)
			assert.are.equal(buf, compose.get_buf())
		end)

		it("does not redirect a stale explicit buffer to a newer draft", function()
			local api = require("wiremux.compose")
			local old = open("old")
			api.discard({ buf = old })
			local current = open("new")

			local accepted, reason = api.send({ buf = old })

			assert.is_false(accepted)
			assert.are.equal("stale_buffer", reason)
			assert.are.equal(current, compose.get_buf())
			assert.are.equal("new", text())
		end)

		it("rejects an action on an explicitly selected hidden draft", function()
			local api = require("wiremux.compose")
			local buf = open("draft")
			assert.is_true(api.close({ buf = buf }))

			local accepted, reason = api.send({ buf = buf })

			assert.is_false(accepted)
			assert.are.equal("hidden", reason)
			assert.are.equal(buf, compose.get_buf())
		end)

		it("treats a draft whose window now displays another buffer as hidden", function()
			local sent = false
			local buf = open("draft", {
				on_confirm = function()
					sent = true
				end,
			})
			vim.api.nvim_win_set_buf(0, vim.api.nvim_create_buf(false, true))

			local accepted, reason = require("wiremux.compose").send({ buf = buf })

			assert.is_false(accepted)
			assert.are.equal("hidden", reason)
			assert.is_false(sent)
		end)

		it("rejects a reentrant action while confirmation is busy", function()
			local api = require("wiremux.compose")
			local accepted, reason
			open("draft", {
				on_confirm = function()
					accepted, reason = api.send()
					return false
				end,
			})

			assert.is_true(api.send())

			assert.is_false(accepted)
			assert.are.equal("busy", reason)
			assert.are.equal("draft", text())
		end)

		it("rejects malformed options before changing the draft", function()
			local buf = open("draft")

			assert.has_error(function()
				require("wiremux.compose").send(false)
			end)

			assert.are.equal(buf, compose.get_buf())
		end)

		it("rejects invalid buffer values instead of treating false as the current buffer", function()
			local buf = open("draft")
			for _, invalid in ipairs({ false, "buffer", -1, 0.5, math.huge }) do
				assert.has_error(function()
					require("wiremux.compose").send({ buf = invalid })
				end)
			end

			assert.are.equal(buf, compose.get_buf())
		end)

		it("keeps acceptance separate from a declined confirmation", function()
			local buf = open("draft", {
				on_confirm = function()
					return false
				end,
			})

			local accepted, reason = require("wiremux.compose").send()

			assert.is_true(accepted)
			assert.is_nil(reason)
			assert.are.equal(buf, compose.get_buf())
		end)

		it("closes according to the configured hide policy", function()
			local buf = open("draft")

			assert.is_true(require("wiremux.compose").close())

			assert.are.equal(buf, compose.get_buf())
			assert.are.equal(-1, vim.fn.bufwinid(buf))
		end)

		it("arms append-next through the public action without any mappings", function()
			settings.on_new_payload = "keep"
			local buf = open("first")
			local api = require("wiremux.compose")

			assert.is_true(api.append_next())
			assert.are.equal(-1, vim.fn.bufwinid(buf))
			open("second")
			api.previous()

			assert.are.equal("first", text())
		end)

		it("navigates to the previous page through the public action", function()
			open("first")
			open("second")

			assert.is_true(require("wiremux.compose").previous())

			assert.are.equal("first", text())
		end)

		it("navigates to the next page through the public action", function()
			open("first")
			open("second")
			local api = require("wiremux.compose")
			api.previous()

			assert.is_true(api.next())

			assert.are.equal("second", text())
		end)

		it("deletes the current page through the public action", function()
			open("first")
			open("second")

			assert.is_true(require("wiremux.compose").delete_page())

			assert.are.equal("first", text())
		end)

		it("clears the final page through delete_page rather than closing it", function()
			local buf = open("draft")

			assert.is_true(require("wiremux.compose").delete_page())

			assert.are.equal(buf, compose.get_buf())
			assert.are.equal("", text())
		end)

		it("discards only the current page when other pages remain", function()
			open("first")
			open("second")

			assert.is_true(require("wiremux.compose").discard())

			assert.are.equal("first", text())
		end)

		it("inserts a selected file through the public action", function()
			require("wiremux.picker").files = function(_, choose)
				choose("src/main.lua")
			end
			open("draft")
			vim.api.nvim_win_set_cursor(0, { 1, 0 })

			assert.is_true(require("wiremux.compose").files())
			vim.wait(20)

			assert.are.equal("src/main.luadraft", text())
		end)

		it("previews in the explicit compose buffer even when called from another window", function()
			local origin = vim.api.nvim_get_current_win()
			local buf = open("Review {file}", {
				on_preview = function()
					return "src/main.lua", "text"
				end,
			})
			vim.api.nvim_win_set_cursor(0, { 1, 9 })
			vim.api.nvim_set_current_win(origin)

			assert.is_true(require("wiremux.compose").preview_placeholder({ buf = buf }))

			local preview_win = vim.b[buf].lsp_floating_preview
			assert.is_number(preview_win)
			assert.are.same(
				{ "src/main.lua" },
				vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(preview_win), 0, -1, false)
			)
		end)

		it("supports a native send callback installed by the existing open event", function()
			vim.api.nvim_create_autocmd("User", {
				group = event_group,
				pattern = "WiremuxComposeOpen",
				callback = function(event)
					local buf = event.data.buf
					vim.keymap.set("n", "<F5>", function()
						require("wiremux").compose.send({ buf = buf })
					end, { buffer = buf })
				end,
			})
			local sent
			open("draft", {
				on_confirm = function(pages)
					sent = pages[1].text
				end,
			})

			mapping("<F5>")()

			assert.are.equal("draft", sent)
		end)

		it("rejects an action if entering the compose window replaces its buffer", function()
			local origin = vim.api.nvim_get_current_win()
			local confirmed = false
			local buf = open("draft", {
				on_confirm = function()
					confirmed = true
				end,
			})
			local win = vim.api.nvim_get_current_win()
			vim.api.nvim_set_current_win(origin)
			local replacement = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_create_autocmd("WinEnter", {
				group = event_group,
				once = true,
				callback = function()
					vim.api.nvim_win_set_buf(win, replacement)
				end,
			})

			local accepted, reason = require("wiremux.compose").send({ buf = buf })

			assert.is_false(accepted)
			assert.are.equal("hidden", reason)
			assert.is_false(confirmed)
		end)

		it("rejects an action if an enter autocmd redirects focus away from Compose", function()
			local origin = vim.api.nvim_get_current_win()
			local confirmed = false
			local buf = open("draft", {
				on_confirm = function()
					confirmed = true
				end,
			})
			vim.api.nvim_set_current_win(origin)
			vim.api.nvim_create_autocmd("WinEnter", {
				group = event_group,
				once = true,
				callback = function()
					vim.api.nvim_set_current_win(origin)
				end,
			})

			local accepted, reason = require("wiremux.compose").send({ buf = buf })

			assert.is_false(accepted)
			assert.are.equal("stale_buffer", reason)
			assert.is_false(confirmed)
			assert.are.equal(buf, compose.get_buf())
		end)

		it("returns no_session if entering the window finalizes the draft", function()
			local origin = vim.api.nvim_get_current_win()
			local confirmed = false
			local buf = open("draft", {
				on_confirm = function()
					confirmed = true
				end,
			})
			vim.api.nvim_set_current_win(origin)
			vim.api.nvim_create_autocmd("WinEnter", {
				group = event_group,
				once = true,
				callback = function()
					vim.api.nvim_buf_delete(buf, { force = true })
				end,
			})

			local accepted, reason = require("wiremux.compose").send({ buf = buf })

			assert.is_false(accepted)
			assert.are.equal("no_session", reason)
			assert.is_false(confirmed)
		end)

		it("does not redirect an action if entering the window creates a different draft", function()
			local origin = vim.api.nvim_get_current_win()
			local confirmed = false
			local buf = open("old", {
				on_confirm = function()
					confirmed = true
				end,
			})
			vim.api.nvim_set_current_win(origin)
			local replacement
			vim.api.nvim_create_autocmd("WinEnter", {
				group = event_group,
				once = true,
				callback = function()
					require("wiremux.compose").discard({ buf = buf })
					replacement = open("new")
				end,
			})

			local accepted, reason = require("wiremux.compose").send({ buf = buf })

			assert.is_false(accepted)
			assert.are.equal("stale_buffer", reason)
			assert.is_false(confirmed)
			assert.are.equal(replacement, compose.get_buf())
			assert.are.equal("new", text())
		end)

		it("sends the draft through the public API without a send mapping", function()
			local sent
			local buf = open("draft", {
				config = { keymaps = {} },
				on_confirm = function(pages)
					sent = pages[1].text
				end,
			})

			local accepted = require("wiremux").compose.send({ buf = buf })

			assert.is_true(accepted)
			assert.are.equal("draft", sent)
			assert.is_nil(compose.get_buf())
		end)
	end)

	describe("footer", function()
		it("shows only send and close hints", function()
			open("draft")

			assert.are.equal(" Enter Send · q Close ", decoration("footer"))
		end)

		it("does not show normal-mode hints in Visual mode", function()
			open("draft")
			for _, key in ipairs({ "v", "V", "<C-v>" }) do
				vim.api.nvim_feedkeys(vim.keycode(key), "xt", false)
				local footer = decoration("footer")
				vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "xt", false)

				assert.are.equal("", footer)
			end
		end)

		it("shows custom Visual-mode send hints", function()
			open("draft", { config = { keymaps = { send = { "<F5>", mode = "x" } } } })
			for _, key in ipairs({ "v", "V", "<C-v>" }) do
				vim.api.nvim_feedkeys(vim.keycode(key), "xt", false)
				local footer = decoration("footer")
				vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "xt", false)

				assert.are.equal(" <F5> Send ", footer)
			end
		end)

		it("uses mapping modes for editor submodes", function()
			local buf = open("draft", {
				config = {
					keymaps = {
						send = {
							{ "<F1>", mode = "n" },
							{ "<F2>", mode = "i" },
							{ "<F3>", mode = "x" },
							{ "<F4>", mode = "s" },
							{ "<F5>", mode = "o" },
							{ "<F6>", mode = "c" },
						},
					},
				},
			})
			for _, case in ipairs({
				{ "no", "<F5>" },
				{ "niI", "<F1>" },
				{ "ic", "<F2>" },
				{ "Rvc", "<F2>" },
				{ "vs", "<F3>" },
				{ "Vs", "<F3>" },
				{ "\22s", "<F3>" },
				{ "S", "<F4>" },
				{ "\19", "<F4>" },
				{ "cv", "<F6>" },
			}) do
				local original_mode = vim.fn.mode
				vim.fn.mode = function()
					return case[1]
				end
				local ok, err = pcall(vim.api.nvim_exec_autocmds, "ModeChanged", { buffer = buf })
				vim.fn.mode = original_mode

				assert.is_true(ok, tostring(err))
				assert.are.equal(" " .. case[2] .. " Send ", decoration("footer"))
			end
		end)

		it("hides the footer without disabling mappings", function()
			open("draft", { config = { footer = false } })

			assert.are.equal("", decoration("footer"))
			assert.is_function(mapping("<CR>"))
			assert.is_function(mapping("q"))
		end)

		it("updates footer visibility while preserving the draft", function()
			local buf = open("draft")

			open("ignored", { config = { on_new_payload = "keep", footer = false } })

			assert.are.equal("", decoration("footer"))
			assert.are.equal("draft", text())
			assert.are.equal(buf, compose.get_buf())

			open("ignored", { config = { on_new_payload = "keep", footer = true } })

			assert.are.equal(" Enter Send · q Close ", decoration("footer"))
		end)

		it("keeps the footer hidden when resuming a hidden draft", function()
			local buf = open("draft", { config = { footer = false } })
			mapping("q")()

			compose.open("")

			assert.are.equal(buf, compose.get_buf())
			assert.are.equal("", decoration("footer"))
		end)
	end)

	describe("default keymap wiring", function()
		before_each(function()
			local config = require("wiremux.config")
			config.setup({ log_level = "off" })
			settings = config.opts.ui.compose
		end)

		it("does not install a shipped Q mapping", function()
			local buf = open("draft")

			assert.are_not.equal(1, buffer_mapping(buf, "Q").buffer)
		end)

		it("allows an explicit Q discard mapping", function()
			local config = require("wiremux.config")
			config.setup({ log_level = "off", ui = { compose = { keymaps = { discard = { "Q", mode = "n" } } } } })
			settings = config.opts.ui.compose
			local cancelled = false
			local buf = open("draft", {
				on_cancel = function()
					cancelled = true
				end,
			})

			mapping("Q")()

			assert.is_true(cancelled)
			assert.is_false(vim.api.nvim_buf_is_valid(buf))
		end)

		it("installs no main-buffer mappings when shipped defaults are disabled", function()
			local config = require("wiremux.config")
			config.setup({ log_level = "off", ui = { compose = { use_default_keymaps = false } } })
			settings = config.opts.ui.compose

			local buf = open("draft")

			assert.are.same({}, vim.api.nvim_buf_get_keymap(buf, "n"))
			assert.are.same({}, vim.api.nvim_buf_get_keymap(buf, "i"))
		end)

		it("keeps explicit bindings when shipped defaults are disabled", function()
			local config = require("wiremux.config")
			config.setup({
				log_level = "off",
				ui = {
					compose = {
						use_default_keymaps = false,
						keymaps = { send = { { "<F5>", mode = "n" } } },
					},
				},
			})
			settings = config.opts.ui.compose
			local sent
			local buf = open("draft", {
				on_confirm = function(pages)
					sent = pages[1].text
				end,
			})

			assert.are.equal(1, #vim.api.nvim_buf_get_keymap(buf, "n"))
			mapping("<F5>")()

			assert.are.equal("draft", sent)
		end)

		it("does not let a shipped jump blocker override an explicit action binding", function()
			settings.keymaps = { send = { "<C-o>", mode = "n" } }
			local sent
			open("draft", {
				on_confirm = function(pages)
					sent = pages[1].text
				end,
			})

			mapping("<C-o>")()

			assert.are.equal("draft", sent)
		end)

		it("keeps native A available for appending at the end of a line", function()
			local buf = open("first")
			vim.api.nvim_win_set_cursor(0, { 1, 0 })

			vim.api.nvim_feedkeys(vim.keycode("A edited<Esc>"), "xt", false)

			assert.are.equal("first edited", text())
			assert.are_not.equal(-1, vim.fn.bufwinid(buf))
		end)

		it("installs the configured normal-mode send binding", function()
			local sent
			open("draft", {
				on_confirm = function(pages)
					sent = pages[1].text
				end,
			})
			local key = keymaps.find_key_for_mode(settings.keymaps.send, "n")

			mapping(key)()

			assert.are.equal("draft", sent)
		end)

		it("installs the configured normal-mode append-next binding", function()
			local buf = open("draft")
			local key = keymaps.find_key_for_mode(settings.keymaps.append_next, "n")

			mapping(key)()

			assert.are.equal(-1, vim.fn.bufwinid(buf))
			assert.are.equal(buf, compose.get_buf())
		end)

		it("does not install an insert-mode C-s send binding", function()
			local buf = open("draft")

			assert.are_not.equal(1, buffer_mapping(buf, "<C-s>", "i").buffer)
		end)
	end)

	describe("pages", function()
		it("saves edits before appending a new page", function()
			local buf = open("first")
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "edited first" })

			open("second")
			mapping("<C-p>")()

			assert.are.equal("edited first", text())
		end)

		it("navigates pages and updates the page counter", function()
			open("first")
			open("second")

			mapping("<C-p>")()
			assert.are.equal("first", text())
			assert.matches("%[1/2%]", decoration("title"))
			mapping("<C-n>")()
			assert.are.equal("second", text())
			assert.matches("%[2/2%]", decoration("title"))
		end)

		it("does not undo into another page's text", function()
			open("first")
			open("second")
			mapping("<C-p>")()

			vim.cmd("silent undo")

			assert.are.equal("first", text())
		end)

		it("confirms edited pages with their sources in order", function()
			local first_source, second_source = { page = 1 }, { page = 2 }
			local pages
			local buf = open("first", { source = first_source })
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "edited first" })
			open("second", {
				source = second_source,
				on_confirm = function(value)
					pages = value
				end,
			})

			mapping("<CR>")()

			assert.are.equal(2, #pages)
			assert.are.equal("edited first", pages[1].text)
			assert.are.equal(first_source, pages[1].source)
			assert.are.equal("second", pages[2].text)
			assert.are.equal(second_source, pages[2].source)
		end)

		it("deletes the current page and advances to the next", function()
			local pages
			open("first")
			open("second")
			open("third", {
				on_confirm = function(value)
					pages = value
				end,
			})
			mapping("<C-p>")()

			mapping("<C-x>")()

			assert.are.equal("third", text())
			mapping("<CR>")()
			assert.are.same({ "first", "third" }, { pages[1].text, pages[2].text })
			assert.are.equal(2, #pages)
		end)

		it("wraps to the first page when deleting the last", function()
			open("first")
			open("second")

			mapping("<C-x>")()

			assert.are.equal("first", text())
			assert.not_matches("%[", decoration("title"))
		end)

		it("clears the only page without discarding its source", function()
			local source, pages = { page = 1 }, nil
			local buf = open("only", {
				source = source,
				on_confirm = function(value)
					pages = value
				end,
			})

			mapping("<C-x>")()

			assert.are.equal(buf, compose.get_buf())
			assert.are.equal("", text())
			mapping("<CR>")()
			assert.are.equal(1, #pages)
			assert.are.equal(source, pages[1].source)
		end)

		it("creates an empty page with its incoming source", function()
			local source, pages = { page = 1 }, nil
			open("", {
				source = source,
				on_confirm = function(value)
					pages = value
				end,
			})

			mapping("<CR>")()

			assert.are.equal(1, #pages)
			assert.are.equal("", pages[1].text)
			assert.are.equal(source, pages[1].source)
		end)
	end)

	describe("new payload policies", function()
		it("keeps the existing page and its source", function()
			settings.on_new_payload = "keep"
			local source, pages = { original = true }, nil
			open("first", { source = source })

			open("ignored", {
				source = { incoming = true },
				on_confirm = function(value)
					pages = value
				end,
			})
			mapping("<CR>")()

			assert.are.equal(1, #pages)
			assert.are.equal("first", pages[1].text)
			assert.are.equal(source, pages[1].source)
		end)

		it("replaces every old page and source", function()
			local source, pages = { replacement = true }, nil
			open("first", { source = { old = 1 } })
			open("second", { source = { old = 2 } })

			open("replacement", {
				config = { on_new_payload = "replace" },
				source = source,
				on_confirm = function(value)
					pages = value
				end,
			})
			mapping("<CR>")()

			assert.are.equal(1, #pages)
			assert.are.equal("replacement", pages[1].text)
			assert.are.equal(source, pages[1].source)
		end)

		it("keeps distinct opaque sources for identical appended text", function()
			local first, second = { future = { marker = "first" } }, { future = { marker = "second" } }
			local pages
			open("same", { source = first })

			open("same", {
				source = second,
				on_confirm = function(value)
					pages = value
				end,
			})
			mapping("<CR>")()

			assert.are.equal(2, #pages)
			assert.are.equal(first, pages[1].source)
			assert.are.equal(second, pages[2].source)
			assert.are.same({ marker = "first" }, pages[1].source.future)
			assert.are.same({ marker = "second" }, pages[2].source.future)
		end)

		it("uses the latest confirmation callback even when keeping old text", function()
			settings.on_new_payload = "keep"
			local old_calls, sent = 0, nil
			open("first", {
				on_confirm = function()
					old_calls = old_calls + 1
				end,
			})

			open("ignored", {
				on_confirm = function(pages)
					sent = pages[1].text
				end,
			})
			mapping("<CR>")()

			assert.are.equal(0, old_calls)
			assert.are.equal("first", sent)
		end)

		it("defaults the ask prompt to keeping the existing draft", function()
			settings.on_new_payload = "ask"
			local prompt_default
			vim.fn.confirm = function(_, _, default)
				prompt_default = default
				return default
			end
			open("first")

			open("ignored")

			assert.are.equal(1, prompt_default)
			assert.are.equal("first", text())
			assert.not_matches("%[", decoration("title"))
		end)

		it("reuses a whitespace-only draft instead of appending", function()
			open("   ")

			open("replacement")

			assert.are.equal("replacement", text())
			assert.not_matches("%[", decoration("title"))
		end)

		it("replaces an entirely whitespace-only multi-page draft", function()
			local buf = open("first")
			open("second")
			mapping("<C-p>")()
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "  " })
			mapping("<C-n>")()
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "", "\t" })

			open("replacement")

			assert.are.equal("replacement", text())
			assert.not_matches("%[", decoration("title"))
		end)

		it("appends to a hidden draft and selects the incoming page", function()
			local buf = open("first")
			mapping("q")()

			open("second")

			assert.are.equal(buf, compose.get_buf())
			assert.are.equal("second", text())
			assert.matches("%[2/2%]", decoration("title"))
		end)
	end)

	describe("append-next", function()
		local prompts

		before_each(function()
			settings.on_new_payload = "ask"
			prompts = 0
			vim.fn.confirm = function(_, _, default)
				prompts = prompts + 1
				return default
			end
		end)

		it("saves edits and hides the draft", function()
			local buf = open("first")
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "edited first" })

			mapping("<F2>")()

			assert.are.equal(-1, vim.fn.bufwinid(buf))
			compose.open("")
			assert.are.equal("edited first", text())
		end)

		it("bypasses the next non-empty payload prompt", function()
			local pages
			open("first")
			mapping("<F2>")()

			open("second", {
				on_confirm = function(value)
					pages = value
				end,
			})
			mapping("<CR>")()

			assert.are.equal(0, prompts)
			assert.are.equal(2, #pages)
			assert.are.same({ "first", "second" }, { pages[1].text, pages[2].text })
		end)

		it("survives reopening without text", function()
			open("first")
			mapping("<F2>")()

			compose.open("")
			open("second")

			assert.are.equal(0, prompts)
			assert.are.equal("second", text())
			assert.matches("%[2/2%]", decoration("title"))
		end)

		it("is consumed after one non-empty payload", function()
			open("first")
			mapping("<F2>")()
			open("second")

			open("ignored")

			assert.are.equal(1, prompts)
			assert.are.equal("second", text())
			assert.matches("%[2/2%]", decoration("title"))
		end)
	end)

	describe("confirmation", function()
		it("preserves the complete draft when confirmation returns false", function()
			open("first")
			local buf = open("second", {
				on_confirm = function()
					return false
				end,
			})

			mapping("<CR>")()

			assert.are.equal(buf, compose.get_buf())
			assert.are.equal("second", text())
			mapping("<C-p>")()
			assert.are.equal("first", text())
		end)

		it("returns to editing after a confirmation error and allows retry", function()
			local calls, message = 0, nil
			require("wiremux.utils.notify").error = function(value)
				message = value
			end
			local buf = open("draft", {
				on_confirm = function()
					calls = calls + 1
					if calls == 1 then
						error("prepare failed")
					end
					return false
				end,
			})

			mapping("<CR>")()
			mapping("<CR>")()

			assert.are.equal(2, calls)
			assert.matches("prepare failed", message)
			assert.are.equal(buf, compose.get_buf())
		end)

		it("blocks re-entry from inside the confirmation callback", function()
			local calls, send = 0, nil
			open("draft", {
				on_confirm = function()
					calls = calls + 1
					send()
				end,
			})
			send = mapping("<CR>")

			send()

			assert.are.equal(1, calls)
		end)

		it("ignores a stale send callback after successful confirmation", function()
			local calls = 0
			open("draft", {
				on_confirm = function()
					calls = calls + 1
				end,
			})
			local send = mapping("<CR>")
			send()

			send()

			assert.are.equal(1, calls)
			assert.is_nil(compose.get_buf())
		end)

		it("does not cancel a successfully confirmed draft", function()
			local cancelled = false
			open("draft", {
				on_cancel = function()
					cancelled = true
				end,
			})

			mapping("<CR>")()

			assert.is_nil(compose.get_buf())
			assert.is_false(cancelled)
		end)

		it("releases the view exactly once", function()
			local view = require("wiremux.ui.compose.view")
			local close, calls, closed_view = view.close, 0, nil
			view.close = function(value)
				calls, closed_view = calls + 1, value
				return close(value)
			end
			open("draft")
			local send = mapping("<CR>")

			send()
			send()

			assert.are.equal(1, calls)
			assert.is_nil(view.get_buf(closed_view))
		end)

		it("releases page sources after cleanup", function()
			local source = { marker = "temporary" }
			local weak = setmetatable({ source }, { __mode = "v" })
			open("draft", { source = source })
			source = nil

			mapping("<CR>")()
			collectgarbage("collect")
			collectgarbage("collect")

			assert.is_nil(weak[1])
		end)
	end)

	describe("closing and discarding", function()
		it("reopens without replacing the source or confirmation callback", function()
			local source, pages = { original = true }, nil
			local buf = open("draft", {
				source = source,
				on_confirm = function(value)
					pages = value
				end,
			})
			mapping("q")()

			compose.open("")
			assert.are.equal(buf, compose.get_buf())
			mapping("<CR>")()

			assert.are.equal("draft", pages[1].text)
			assert.are.equal(source, pages[1].source)
		end)

		it("cancels once when the draft buffer is wiped", function()
			local calls = 0
			local buf = open("draft", {
				on_cancel = function()
					calls = calls + 1
				end,
			})

			vim.api.nvim_buf_delete(buf, { force = true })

			assert.are.equal(1, calls)
			assert.is_nil(compose.get_buf())
		end)

		it("clears state before calling a cancellation callback that throws", function()
			local calls, state_was_clear, message = 0, false, nil
			require("wiremux.utils.notify").error = function(value)
				message = value
			end
			open("draft", {
				on_cancel = function()
					calls = calls + 1
					state_was_clear = compose.get_buf() == nil
					error("cancel failed")
				end,
			})
			local discard = mapping("Q")

			discard()
			discard()

			assert.are.equal(1, calls)
			assert.is_true(state_was_clear)
			assert.matches("cancel failed", message)
		end)

		it("discards only the current page and keeps the other sources", function()
			local first, second, third = { page = 1 }, { page = 2 }, { page = 3 }
			local pages, cancelled = nil, false
			open("first", { source = first })
			open("second", { source = second })
			local buf = open("third", {
				source = third,
				on_confirm = function(value)
					pages = value
				end,
				on_cancel = function()
					cancelled = true
				end,
			})
			mapping("<C-p>")()

			mapping("Q")()

			assert.are.equal(buf, compose.get_buf())
			assert.are.equal("third", text())
			assert.is_false(cancelled)
			mapping("<CR>")()
			assert.are.equal(2, #pages)
			assert.are.same({ "first", "third" }, { pages[1].text, pages[2].text })
			assert.are.equal(first, pages[1].source)
			assert.are.equal(third, pages[2].source)
		end)

		it("selects the first page after discarding the last", function()
			open("first")
			open("second")

			mapping("Q")()

			assert.are.equal("first", text())
			assert.not_matches("%[", decoration("title"))
		end)

		it("cancels and closes when discarding the only page", function()
			local cancelled, confirmed = false, false
			open("only", {
				on_cancel = function()
					cancelled = true
				end,
				on_confirm = function()
					confirmed = true
				end,
			})

			mapping("Q")()

			assert.is_nil(compose.get_buf())
			assert.is_true(cancelled)
			assert.is_false(confirmed)
		end)

		it("discards without the close prompt", function()
			local prompts = 0
			vim.fn.confirm = function()
				prompts = prompts + 1
				return 3
			end
			open("draft", { config = { close_behavior = "ask" } })

			mapping("Q")()

			assert.are.equal(0, prompts)
			assert.is_nil(compose.get_buf())
		end)

		it("discards every page when closing with discard behavior", function()
			settings.close_behavior = "discard"
			local cancelled, confirmed = false, false
			open("first")
			open("second", {
				on_cancel = function()
					cancelled = true
				end,
				on_confirm = function()
					confirmed = true
				end,
			})

			mapping("q")()

			assert.is_nil(compose.get_buf())
			assert.is_true(cancelled)
			assert.is_false(confirmed)
		end)
	end)

	describe("open events", function()
		local events

		before_each(function()
			events = {}
			vim.api.nvim_create_autocmd("User", {
				group = event_group,
				pattern = "WiremuxComposeOpen",
				callback = function(event)
					table.insert(events, event.data)
				end,
			})
		end)

		it("emits a fresh focused window that user hooks can customize", function()
			vim.api.nvim_create_autocmd("User", {
				group = event_group,
				pattern = "WiremuxComposeOpen",
				callback = function(event)
					vim.wo[event.data.win].spell = true
				end,
			})

			local buf = open("first")

			assert.are.equal(1, #events)
			assert.is_false(events[1].reopened)
			assert.are.equal(buf, events[1].buf)
			assert.are.equal(vim.api.nvim_get_current_win(), events[1].win)
			assert.is_true(vim.wo[0].spell)
		end)

		it("does not emit another open event for an already visible window", function()
			open("first")

			open("second")

			assert.are.equal(1, #events)
		end)

		it("marks a hidden window as reopened", function()
			local buf = open("first")
			mapping("q")()

			compose.open("")

			assert.are.equal(2, #events)
			assert.is_true(events[2].reopened)
			assert.are.equal(buf, events[2].buf)
		end)

		it("keeps the draft available after an external window close", function()
			local buf = open("draft")
			vim.api.nvim_win_close(vim.api.nvim_get_current_win(), true)

			compose.open("")

			assert.are.equal(buf, compose.get_buf())
			assert.are_not.equal(-1, vim.fn.bufwinid(buf))
			assert.are.equal(2, #events)
		end)

		it("keeps compose usable when a user hook fails", function()
			vim.api.nvim_exec_autocmds = function()
				error("custom setup failed")
			end
			local message
			require("wiremux.utils.notify").error = function(value)
				message = value
			end

			local buf = open("draft")

			assert.is_true(vim.api.nvim_buf_is_valid(buf))
			assert.matches("custom setup failed", message)
		end)
	end)

	describe("view configuration", function()
		it("refreshes window dimensions", function()
			open("draft", { config = { width = 0.3, height = 0.2 } })

			open("ignored", { config = { on_new_payload = "keep", width = 0.7, height = 0.5 } })

			local window = vim.api.nvim_win_get_config(0)
			assert.are.equal(math.floor(vim.o.columns * 0.7), window.width)
			assert.are.equal(math.floor(vim.o.lines * 0.5), window.height)
		end)

		it("refreshes the title while keeping existing text", function()
			open("draft", { config = { title = " First " } })

			open("ignored", { config = { on_new_payload = "keep", title = " Latest " } })

			assert.are.equal(" Latest ", decoration("title"))
			assert.are.equal("draft", text())
		end)

		it("refreshes the border", function()
			open("draft", { config = { border = "rounded" } })
			local previous = vim.api.nvim_win_get_config(0).border

			open("ignored", { config = { on_new_payload = "keep", border = "single" } })

			assert.are_not.same(previous, vim.api.nvim_win_get_config(0).border)
		end)

		it("replaces window options and resets omitted options", function()
			open("draft", { config = { wo = { wrap = true, number = false, spell = true } } })

			open("ignored", { config = { on_new_payload = "keep", wo = { wrap = false, number = true } } })

			assert.is_false(vim.wo[0].wrap)
			assert.is_true(vim.wo[0].number)
			assert.is_false(vim.wo[0].spell)
		end)

		it("refreshes the footer when a binding changes", function()
			open("draft", { config = { keymaps = { send = { "<F5>", mode = "n" } } } })

			open("ignored", { config = { on_new_payload = "keep", keymaps = { send = { "<F6>", mode = "n" } } } })

			assert.matches("F6", decoration("footer"))
			assert.not_matches("F5", decoration("footer"))
		end)

		it("applies new configuration while reopening a hidden session", function()
			open("first")
			mapping("q")()

			open("second", {
				config = {
					width = 0.75,
					title = " Reopened ",
					wo = { number = true },
					keymaps = { send = { "<F7>", mode = "n" } },
				},
			})

			assert.are.equal(math.floor(vim.o.columns * 0.75), vim.api.nvim_win_get_config(0).width)
			assert.matches("Reopened%s+%[2/2%]", decoration("title"))
			assert.is_true(vim.wo[0].number)
			assert.is_function(buffer_mapping(compose.get_buf(), "<F7>").callback)
		end)
	end)

	describe("keymap ownership", function()
		it("preserves native mapping options when the callback is unchanged", function()
			settings.keymaps = { send = { "<F5>", mode = "n" } }
			local buf = open("draft")
			local callback = buffer_mapping(buf, "<F5>").callback
			vim.keymap.set("n", "<F5>", callback, {
				buffer = buf,
				silent = true,
				nowait = false,
				desc = "Native send options",
			})

			open("second")
			open("third")

			local current = buffer_mapping(buf, "<F5>")
			assert.are.equal(callback, current.callback)
			assert.are.equal(1, current.silent)
			assert.are.equal(0, current.nowait)
			assert.are.equal("Native send options", current.desc)
		end)

		for _, case in ipairs({
			{ name = "silent", field = "silent", options = { silent = true } },
			{ name = "nowait", field = "nowait", options = { nowait = false } },
			{ name = "description", field = "desc", options = { desc = "Native send" } },
			{ name = "description removal", field = "desc", options = {}, clear_description = true },
			{ name = "remapping", field = "noremap", options = { remap = true } },
			{ name = "expression", field = "expr", options = { expr = true } },
			{ name = "script", field = "script", options = { script = true } },
		}) do
			it("preserves a native " .. case.name .. " change with an unchanged callback", function()
				settings.keymaps = { send = { "<F5>", mode = "n" } }
				local buf = open("draft")
				local original = buffer_mapping(buf, "<F5>")
				local options = vim.tbl_extend("force", {
					buffer = buf,
					nowait = true,
					desc = original.desc,
				}, case.options)
				if case.clear_description then
					options.desc = nil
				end
				vim.keymap.set("n", "<F5>", original.callback, options)
				local expected = buffer_mapping(buf, "<F5>")
				assert.are_not.equal(original[case.field], expected[case.field])

				open("second")

				local current = buffer_mapping(buf, "<F5>")
				assert.are.equal(expected[case.field], current[case.field])
				assert.are.equal(original.callback, current.callback)
			end)
		end

		it("keeps a native option override when configuration removes the action binding", function()
			settings.keymaps = { send = { "<F5>", mode = "n" } }
			local buf = open("draft")
			local original = buffer_mapping(buf, "<F5>")
			vim.keymap.set("n", "<F5>", original.callback, {
				buffer = buf,
				nowait = true,
				silent = true,
				desc = original.desc,
			})

			open("second", { config = { keymaps = {} } })

			local current = buffer_mapping(buf, "<F5>")
			assert.are.equal(original.callback, current.callback)
			assert.are.equal(1, current.silent)
		end)

		it("keeps ownership after an identical native reinstall so configuration can remove the binding", function()
			settings.keymaps = { send = { "<F5>", mode = "n" } }
			local buf = open("draft")
			local original = buffer_mapping(buf, "<F5>")
			vim.keymap.set("n", "<F5>", original.callback, {
				buffer = buf,
				nowait = true,
				desc = original.desc,
			})

			open("second", { config = { keymaps = {} } })

			assert.are.same({}, buffer_mapping(buf, "<F5>"))
		end)

		it("omits footer hints for same-callback option overrides in the open hook", function()
			settings.keymaps = { send = { "<F5>", mode = "n" } }
			vim.api.nvim_create_autocmd("User", {
				group = event_group,
				pattern = "WiremuxComposeOpen",
				callback = function(event)
					local original = buffer_mapping(event.data.buf, "<F5>")
					vim.keymap.set("n", "<F5>", original.callback, {
						buffer = event.data.buf,
						nowait = true,
						silent = true,
						desc = original.desc,
					})
				end,
			})

			open("draft")

			assert.not_matches("Send", decoration("footer"))
		end)

		for _, case in ipairs({
			{ mode = "", removed = "n", retained = "o", label = "normal/operator-pending" },
			{ mode = "!", removed = "i", retained = "c", label = "insert/command-line" },
		}) do
			it("tracks native deletions independently in combined " .. case.label .. " mappings", function()
				settings.keymaps = { send = { "<F5>", mode = case.mode } }
				local buf = open("draft")
				vim.keymap.del(case.removed, "<F5>", { buffer = buf })

				open("second")

				assert.are.same({}, buffer_mapping(buf, "<F5>", case.removed))
				assert.is_function(buffer_mapping(buf, "<F5>", case.retained).callback)
			end)
		end

		it("preserves native replacement and deletion after hiding and restoring the draft", function()
			local buf = open("draft")
			vim.keymap.del("n", "<CR>", { buffer = buf })
			local calls = 0
			vim.keymap.set("n", "<F5>", function()
				calls = calls + 1
			end, { buffer = buf })
			require("wiremux.compose").close()

			compose.open("")
			open("second")
			mapping("<F5>")()

			assert.are.same({}, buffer_mapping(buf, "<CR>"))
			assert.are.equal(1, calls)
		end)

		it("does not reclaim a user replacement after the user later deletes it", function()
			settings.keymaps = { send = { "<F5>", mode = "n" } }
			local buf = open("draft")
			vim.keymap.set("n", "<F5>", function() end, { buffer = buf })
			open("second")
			vim.keymap.del("n", "<F5>", { buffer = buf })

			open("third")

			assert.are.same({}, buffer_mapping(buf, "<F5>"))
		end)

		it("preserves a visual-mode deletion without deleting the remaining select-mode binding", function()
			settings.keymaps = { send = { "<F5>", mode = "v" } }
			local buf = open("draft")
			vim.keymap.del("x", "<F5>", { buffer = buf })

			open("second")

			assert.are.same({}, buffer_mapping(buf, "<F5>", "x"))
			assert.is_function(buffer_mapping(buf, "<F5>", "s").callback)
		end)

		it("omits footer hints for mappings deleted in the open hook", function()
			vim.api.nvim_create_autocmd("User", {
				group = event_group,
				pattern = "WiremuxComposeOpen",
				callback = function(event)
					vim.keymap.del("n", "<CR>", { buffer = event.data.buf })
				end,
			})

			open("draft")

			assert.not_matches("Send", decoration("footer"))
		end)

		it("omits footer hints for mappings replaced in the open hook", function()
			vim.api.nvim_create_autocmd("User", {
				group = event_group,
				pattern = "WiremuxComposeOpen",
				callback = function(event)
					vim.keymap.set("n", "<CR>", function() end, { buffer = event.data.buf })
				end,
			})

			open("draft")

			assert.not_matches("Send", decoration("footer"))
		end)

		it("clears the final footer hint when focusing an already-visible draft", function()
			settings.use_default_keymaps = false
			settings.keymaps = { send = { "<F5>", mode = "n" } }
			local buf = open("draft")
			assert.matches("Send", decoration("footer"))
			vim.keymap.del("n", "<F5>", { buffer = buf })

			compose.open("")

			assert.are.equal("", decoration("footer"))
		end)

		it("uses another still-owned binding in the footer when the first was deleted", function()
			local buf = open(
				"draft",
				{ config = { keymaps = {
					send = { { "<F5>", mode = "n" }, { "<F6>", mode = "n" } },
				} } }
			)
			vim.keymap.del("n", "<F5>", { buffer = buf })

			compose.open("")

			assert.matches("F6.*Send", decoration("footer"))
			assert.not_matches("F5", decoration("footer"))
		end)

		it("does not advertise an action shadowed by another configured action", function()
			open("draft", {
				config = {
					keymaps = {
						send = { "<F5>", mode = "n" },
						close = { "<F5>", mode = "n" },
					},
				},
			})

			assert.matches("Close", decoration("footer"))
			assert.not_matches("Send", decoration("footer"))
		end)

		it("preserves a mapping deleted by the user through repeated refreshes", function()
			local buf = open("draft")
			vim.keymap.del("n", "<CR>", { buffer = buf })

			open("second")
			open("third")

			assert.are.same({}, buffer_mapping(buf, "<CR>"))
		end)

		it("does not reclaim a deleted mapping after configuration removes and reintroduces it", function()
			local buf = open("draft", { config = { keymaps = { send = { "<F5>", mode = "n" } } } })
			vim.keymap.del("n", "<F5>", { buffer = buf })

			open("second", { config = { keymaps = {} } })
			open("third", { config = { keymaps = { send = { "<F5>", mode = "n" } } } })

			assert.are.same({}, buffer_mapping(buf, "<F5>"))
		end)

		it("does not reclaim a deleted mapping through an equivalent key spelling", function()
			local buf = open("draft", { config = { keymaps = { send = { "<F5>", mode = "n" } } } })
			vim.keymap.del("n", "<F5>", { buffer = buf })

			open("second", { config = { keymaps = { send = { "<f5>", mode = "n" } } } })

			assert.are.same({}, buffer_mapping(buf, "<F5>"))
		end)

		it("removes obsolete Wiremux mappings during refresh", function()
			local buf = open("draft", { config = { keymaps = { send = { "<F5>", mode = "n" } } } })
			assert.is_function(buffer_mapping(buf, "<F5>").callback)

			open("ignored", { config = { on_new_payload = "keep", keymaps = { send = { "<F6>", mode = "n" } } } })

			assert.are.same({}, buffer_mapping(buf, "<F5>"))
			assert.is_function(buffer_mapping(buf, "<F6>").callback)
		end)

		it("preserves a mapping replaced by the user", function()
			settings.keymaps = { send = { "<F5>", mode = "n" } }
			settings.on_new_payload = "keep"
			local buf = open("draft")
			local calls, message = 0, nil
			vim.keymap.set("n", "<F5>", function()
				calls = calls + 1
			end, { buffer = buf })
			require("wiremux.utils.notify").debug = function(value)
				message = value
			end

			open("ignored")
			mapping("<F5>")()

			assert.are.equal(1, calls)
			assert.matches("preserving", message)
		end)
	end)

	describe("placeholder preview", function()
		local source, received_source, received_name, calls, buf

		before_each(function()
			source, calls = { stored = true }, 0
			received_source, received_name = nil, nil
			buf = open("Review {changes}", {
				source = source,
				on_preview = function(page_source, name)
					calls = calls + 1
					received_source, received_name = page_source, name
					return "diff --git a/file b/file", "diff"
				end,
			})
			vim.api.nvim_win_set_cursor(0, { 1, 9 })
		end)

		it("previews the source placeholder without changing the page", function()
			mapping("K")()

			local preview_win = vim.b[buf].lsp_floating_preview
			local preview_buf = vim.api.nvim_win_get_buf(preview_win)
			assert.are.same({ "diff --git a/file b/file" }, vim.api.nvim_buf_get_lines(preview_buf, 0, -1, false))
			assert.are.equal("diff", vim.bo[preview_buf].syntax)
			assert.are.equal(source, received_source)
			assert.are.equal("changes", received_name)
			assert.are.equal("Review {changes}", text())
		end)

		it("focuses an existing preview without resolving it again", function()
			mapping("K")()
			local preview_win = vim.b[buf].lsp_floating_preview

			mapping("K")()

			assert.are.equal(preview_win, vim.api.nvim_get_current_win())
			assert.are.equal(1, calls)
		end)

		it("closes the focused preview with Escape", function()
			mapping("K")()
			mapping("K")()
			local preview_win = vim.api.nvim_get_current_win()

			mapping("<Esc>")()

			assert.is_false(vim.api.nvim_win_is_valid(preview_win))
		end)

		it("does not resolve when the cursor is outside a placeholder", function()
			vim.api.nvim_win_set_cursor(0, { 1, 0 })

			mapping("K")()

			assert.are.equal(0, calls)
		end)
	end)

	describe("file insertion", function()
		it("ignores a queued file selection after its session is finalized", function()
			local choose
			require("wiremux.picker").files = function(_, callback)
				choose = callback
			end
			open("old", {
				config = {
					keymaps = {
						files = { "<F4>", mode = "n" },
						discard = { "Q", mode = "n" },
					},
				},
			})
			mapping("<F4>")()
			choose("stale.txt")
			mapping("Q")()
			open("new")

			vim.wait(20)

			assert.are.equal("new", text())
		end)
	end)
end)
