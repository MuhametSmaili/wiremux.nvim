---@module 'luassert'

local compose_config = require("wiremux.ui.compose.config")
local keymaps = require("wiremux.ui.compose.keymaps")

describe("configuration", function()
	local config
	local original_config
	local original_context
	local original_notify

	before_each(function()
		original_notify = vim.notify
		original_config = package.loaded["wiremux.config"]
		original_context = package.loaded["wiremux.context"]
		package.loaded["wiremux.config"] = nil
		package.loaded["wiremux.context"] = nil
		config = require("wiremux.config")
		config.setup({ log_level = "off" })
	end)

	after_each(function()
		vim.notify = original_notify
		package.loaded["wiremux.config"] = original_config
		package.loaded["wiremux.context"] = original_context
	end)

	describe("default compose keybindings", function()
		it("sends with normal-mode <CR>", function()
			assert.are.equal("<CR>", keymaps.find_key_for_mode(config.opts.ui.compose.keymaps.send, "n"))
		end)

		it("has no insert-mode send binding", function()
			assert.is_nil(keymaps.find_key_for_mode(config.opts.ui.compose.keymaps.send, "i"))
		end)

		it("uses <C-s> for append-next in normal mode only", function()
			local bindings = keymaps.normalize(config.opts.ui.compose.keymaps.append_next)

			assert.are.equal(1, #bindings)
			assert.are.equal("<C-s>", bindings[1].key)
			assert.are.same({ "n" }, bindings[1].modes)
		end)

		it("navigates pages with normal-mode <C-p> and <C-n>", function()
			assert.are.equal("<C-p>", keymaps.find_key_for_mode(config.opts.ui.compose.keymaps.previous, "n"))
			assert.are.equal("<C-n>", keymaps.find_key_for_mode(config.opts.ui.compose.keymaps.next, "n"))
		end)

		it("deletes the current page with normal-mode <C-x>", function()
			assert.are.equal("<C-x>", keymaps.find_key_for_mode(config.opts.ui.compose.keymaps.delete_page, "n"))
		end)

		it("previews placeholders with normal-mode K", function()
			assert.are.equal("K", keymaps.find_key_for_mode(config.opts.ui.compose.keymaps.preview_placeholder, "n"))
		end)
	end)

	describe("default compose options", function()
		it("enables shipped keymaps by default", function()
			assert.is_true(config.opts.ui.compose.use_default_keymaps)
		end)

		it("uses sixty percent of the editor width", function()
			assert.are.equal(0.6, config.opts.ui.compose.width)
		end)

		it("asks before closing a draft", function()
			assert.are.equal("ask", config.opts.ui.compose.close_behavior)
		end)
	end)

	describe("compose payload policies", function()
		it("accepts append", function()
			local normalized, errors = compose_config.options({ on_new_payload = "append" })

			assert.are.same({}, errors)
			assert.are.equal("append", normalized.on_new_payload)
		end)

		it("rejects an unknown policy", function()
			local normalized, errors = compose_config.options({ on_new_payload = "merge" }, "item.compose")

			assert.is_nil(normalized.on_new_payload)
			assert.are.equal(1, #errors)
			assert.are.equal("item.compose.on_new_payload", errors[1].path)
			assert.matches("invalid on_new_payload", errors[1].message)
		end)
	end)

	describe("compose default keymap policy", function()
		it("accepts an explicitly enabled global policy", function()
			local normalized, errors =
				compose_config.normalize_global({ use_default_keymaps = true }, config.opts.ui.compose)

			assert.are.same({}, errors)
			assert.is_true(normalized.use_default_keymaps)
			assert.are.equal("<CR>", keymaps.find_key_for_mode(normalized.keymaps.send, "n"))
		end)

		it("warns and restores shipped defaults for an invalid policy", function()
			local warnings = {}
			vim.notify = function(message, level)
				warnings[#warnings + 1] = { message = message, level = level }
			end

			config.setup({ ui = { compose = { use_default_keymaps = "false" } } })

			assert.is_true(vim.wait(1000, function()
				return #warnings > 0
			end))
			assert.are.equal(1, #warnings)
			assert.are.equal(vim.log.levels.WARN, warnings[1].level)
			assert.matches("ui.compose.use_default_keymaps must be a boolean", warnings[1].message)
			assert.is_true(config.opts.ui.compose.use_default_keymaps)
			assert.are.equal("<CR>", keymaps.find_key_for_mode(config.opts.ui.compose.keymaps.send, "n"))
		end)

		it("rejects default-keymap policy in action compose options", function()
			local normalized, errors = compose_config.normalize_action({ use_default_keymaps = false }, false)

			assert.are.same({}, normalized)
			assert.are.equal(1, #errors)
			assert.are.equal("actions.send.compose.use_default_keymaps", errors[1].path)
			assert.matches("unknown compose option", errors[1].message)
		end)

		it("rejects per-send default-keymap policy overrides as unknown", function()
			local resolved, errors = compose_config.resolve(config.opts.ui.compose, {
				use_default_keymaps = false,
			}, "item.compose")

			assert.is_nil(resolved)
			assert.are.equal(1, #errors)
			assert.are.equal("item.compose.use_default_keymaps", errors[1].path)
			assert.matches("unknown compose option", errors[1].message)
		end)

		it("accepts runtime bindings on the empty global keymap base", function()
			config.setup({ log_level = "off", ui = { compose = { use_default_keymaps = false } } })

			local resolved, errors = compose_config.resolve(config.opts.ui.compose, {
				keymaps = { send = { "<F8>", mode = "i" } },
			}, "opts.compose")

			assert.are.same({}, errors)
			assert.are.same({ send = { "<F8>", mode = "i" } }, resolved.keymaps)
			assert.is_false(resolved.use_default_keymaps)
		end)

		it("retains the disabled policy in a complete session config", function()
			config.setup({ log_level = "off", ui = { compose = { use_default_keymaps = false } } })

			local resolved, errors = compose_config.resolve(config.opts.ui.compose, true, "opts.compose")

			assert.are.same({}, errors)
			assert.is_false(resolved.use_default_keymaps)
			assert.are.same({}, resolved.keymaps)
		end)

		it("keeps other global defaults when shipped bindings are disabled", function()
			local expected = vim.deepcopy(config.opts.ui.compose)
			expected.use_default_keymaps = false
			expected.keymaps = {}

			config.setup({ log_level = "off", ui = { compose = { use_default_keymaps = false } } })

			assert.are.same(expected, config.opts.ui.compose)
		end)

		it("retains explicit global bindings with shipped bindings disabled", function()
			config.setup({
				log_level = "off",
				ui = { compose = { use_default_keymaps = false, keymaps = { send = { "<F8>", mode = "i" } } } },
			})

			assert.are.same({ send = { "<F8>", mode = "i" } }, config.opts.ui.compose.keymaps)
		end)

		it("omits every shipped action binding when disabled globally", function()
			config.setup({ log_level = "off", ui = { compose = { use_default_keymaps = false } } })

			assert.are.same({}, config.opts.ui.compose.keymaps)
			assert.is_false(config.opts.ui.compose.use_default_keymaps)
		end)
	end)

	describe("compose history limit", function()
		it("disables history by default", function()
			assert.are.equal(0, config.opts.ui.compose.history_limit)
		end)

		it("accepts zero to disable history globally", function()
			local normalized, errors = compose_config.normalize_global({ history_limit = 0 }, { history_limit = 7 })

			assert.are.same({}, errors)
			assert.are.equal(0, normalized.history_limit)
		end)

		it("accepts a positive integer globally", function()
			local normalized, errors = compose_config.normalize_global({ history_limit = 2 }, { history_limit = 7 })

			assert.are.same({}, errors)
			assert.are.equal(2, normalized.history_limit)
		end)

		it("rejects a negative limit and keeps the default", function()
			local normalized, errors = compose_config.normalize_global({ history_limit = -1 }, { history_limit = 7 })

			assert.are.equal(7, normalized.history_limit)
			assert.are.equal(1, #errors)
			assert.are.equal("ui.compose.history_limit", errors[1].path)
			assert.matches("non%-negative integer", errors[1].message)
		end)

		it("rejects a fractional limit and keeps the default", function()
			local normalized, errors = compose_config.normalize_global({ history_limit = 1.5 }, { history_limit = 7 })

			assert.are.equal(7, normalized.history_limit)
			assert.are.equal(1, #errors)
			assert.are.equal("ui.compose.history_limit", errors[1].path)
			assert.matches("non%-negative integer", errors[1].message)
		end)

		it("rejects a runtime history override", function()
			local resolved, errors = compose_config.resolve(
				{ history_limit = 7 },
				{ history_limit = 0 },
				"item.compose"
			)

			assert.is_nil(resolved)
			assert.are.equal(1, #errors)
			assert.are.equal("item.compose.history_limit", errors[1].path)
			assert.matches("unknown compose option", errors[1].message)
		end)

		it("does not copy the global history limit into a session", function()
			local resolved, errors = compose_config.resolve({ history_limit = 7 }, true, "opts.compose")

			assert.are.same({}, errors)
			assert.is_nil(resolved.history_limit)
		end)
	end)

	describe("repeated setup", function()
		it("does not alias explicit user mappings after setup", function()
			local options = {
				log_level = "off",
				ui = { compose = { use_default_keymaps = false, keymaps = { send = { "<F8>", mode = { "i" } } } } },
			}
			local original = vim.deepcopy(options)

			config.setup(options)
			config.opts.ui.compose.keymaps.send.mode[1] = "n"

			assert.are.same(original, options)
			config.setup(options)
			assert.are.same({ send = { "<F8>", mode = { "i" } } }, config.opts.ui.compose.keymaps)
		end)

		it("restores shipped bindings after an earlier opt-out", function()
			config.setup({ log_level = "off", ui = { compose = { use_default_keymaps = false } } })

			config.setup({ log_level = "off" })

			assert.is_true(config.opts.ui.compose.use_default_keymaps)
			assert.are.equal("<CR>", keymaps.find_key_for_mode(config.opts.ui.compose.keymaps.send, "n"))
			assert.are.equal("q", keymaps.find_key_for_mode(config.opts.ui.compose.keymaps.close, "n"))
		end)

		it("owns its option tree instead of aliasing module defaults", function()
			config.opts.ui.compose.title = " Mutated "
			config.opts.actions.send.behavior = "all"

			config.setup({ log_level = "off" })

			assert.are.equal(" Compose Message ", config.opts.ui.compose.title)
			assert.are.equal("pick", config.opts.actions.send.behavior)
		end)

		it("replaces custom resolvers while preserving builtins", function()
			local context = require("wiremux.context")
			config.setup({
				log_level = "off",
				context = { resolvers = {
					first = function()
						return "first"
					end,
				} },
			})
			assert.are.equal("first", context.get("first"))

			config.setup({
				log_level = "off",
				context = { resolvers = {
					second = function()
						return "second"
					end,
				} },
			})

			assert.is_nil(context.get("first"))
			assert.are.equal("second", context.get("second"))
			assert.is_not_nil(context.get("position"))
		end)
	end)

	describe("custom resolver validation", function()
		it("rejects names outside the placeholder grammar", function()
			local errors = require("wiremux.utils.validate").validate({
				context = { resolvers = {
					["bad-name"] = function()
						return "invalid"
					end,
				} },
			})

			assert.are.equal(1, #errors)
			assert.are.equal("context.resolvers.bad-name", errors[1].path)
			assert.matches("resolver name", errors[1].message)
		end)
	end)

	describe("malformed global compose options with logging off", function()
		it("falls back to the default width", function()
			local default_width = config.opts.ui.compose.width

			config.setup({ log_level = "off", ui = { compose = { width = "wide" } } })

			assert.are.equal(default_width, config.opts.ui.compose.width)
		end)

		it("falls back to the default close behavior", function()
			local default_close_behavior = config.opts.ui.compose.close_behavior

			config.setup({ log_level = "off", ui = { compose = { close_behavior = "explode" } } })

			assert.are.equal(default_close_behavior, config.opts.ui.compose.close_behavior)
		end)

		it("falls back to the default send binding for an invalid mapping mode", function()
			local default_send_key = keymaps.find_key_for_mode(config.opts.ui.compose.keymaps.send, "n")

			config.setup({
				log_level = "off",
				ui = { compose = { keymaps = { send = { "<F8>", mode = "invalid" } } } },
			})

			assert.are.equal(default_send_key, keymaps.find_key_for_mode(config.opts.ui.compose.keymaps.send, "n"))
		end)
	end)

	describe("compose action binding replacement", function()
		it("does not alias runtime overrides or inherited bindings", function()
			local global = { keymaps = { send = { "<F8>" }, close = { "q", mode = { "n" } } } }
			local overrides = { keymaps = { send = { "<F9>", mode = { "i" } } } }
			local original_global = vim.deepcopy(global)
			local original_overrides = vim.deepcopy(overrides)

			local resolved, errors = compose_config.resolve(global, overrides, "opts.compose")
			assert.are.same({}, errors)
			resolved.keymaps.send.mode[1] = "n"
			resolved.keymaps.close.mode[1] = "i"

			assert.are.same(original_global, global)
			assert.are.same(original_overrides, overrides)
		end)

		it("rejects false as an action binding", function()
			local resolved, errors = compose_config.resolve(config.opts.ui.compose, {
				keymaps = { send = false },
			}, "opts.compose")

			assert.is_nil(resolved)
			assert.are.equal(1, #errors)
			assert.are.equal("opts.compose.keymaps.send", errors[1].path)
			assert.matches("must be a keymap table or list", errors[1].message)
		end)

		it("keeps inherited mappings when runtime keymaps is empty", function()
			local resolved, errors = compose_config.resolve({
				keymaps = { send = { "<F8>", mode = "i" } },
			}, { keymaps = {} }, "opts.compose")

			assert.are.same({}, errors)
			assert.are.same({ send = { "<F8>", mode = "i" } }, resolved.keymaps)
		end)

		it("keeps shipped mappings when global keymaps is empty", function()
			local defaults = vim.deepcopy(config.opts.ui.compose.keymaps)

			config.setup({ log_level = "off", ui = { compose = { keymaps = {} } } })

			assert.are.same(defaults, config.opts.ui.compose.keymaps)
		end)

		it("disables only the supplied runtime action with an empty binding", function()
			local resolved, errors = compose_config.resolve({
				keymaps = { send = { "<F8>", mode = "i" }, close = { "q" } },
			}, { keymaps = { send = {} } }, "opts.compose")

			assert.are.same({}, errors)
			assert.are.same({ send = {}, close = { "q" } }, resolved.keymaps)
		end)

		it("disables only the supplied global action with an empty binding", function()
			config.setup({
				log_level = "off",
				ui = { compose = { keymaps = { append_next = {} } } },
			})

			assert.are.same({}, config.opts.ui.compose.keymaps.append_next)
			assert.are.equal("<CR>", keymaps.find_key_for_mode(config.opts.ui.compose.keymaps.send, "n"))
		end)

		it("replaces a global single binding with a runtime list", function()
			local resolved, errors = compose_config.resolve({
				keymaps = { send = { "<F7>", mode = "i", desc = "Global send" } },
			}, {
				keymaps = { send = { { "<F8>", mode = "n" }, { "<F9>", mode = "i" } } },
			}, "opts.compose")

			assert.are.same({}, errors)
			assert.are.same({ { "<F8>", mode = "n" }, { "<F9>", mode = "i" } }, resolved.keymaps.send)
		end)

		it("replaces a global binding list with one runtime binding", function()
			local resolved, errors = compose_config.resolve({
				keymaps = { send = { { "<F7>", mode = "i" }, { "<F8>", mode = "n" } } },
			}, {
				keymaps = { send = { "<F9>", mode = "n" } },
			}, "opts.compose")

			assert.are.same({}, errors)
			assert.are.same({ "<F9>", mode = "n" }, resolved.keymaps.send)
		end)

		it("replaces a shipped single binding with a global list", function()
			config.setup({
				log_level = "off",
				ui = { compose = { keymaps = { append_next = { { "<F8>", mode = "i" }, { "<F9>" } } } } },
			})

			assert.are.same({ { "<F8>", mode = "i" }, { "<F9>" } }, config.opts.ui.compose.keymaps.append_next)
		end)

		it("replaces a shipped binding list with one global binding", function()
			config.setup({
				log_level = "off",
				ui = { compose = { keymaps = { close = { "<F8>", mode = "i" } } } },
			})

			assert.are.same({ "<F8>", mode = "i" }, config.opts.ui.compose.keymaps.close)
		end)

		it("does not inherit a shipped mode into an explicit global binding", function()
			config.setup({
				log_level = "off",
				ui = { compose = { keymaps = { append_next = { "<F8>", desc = "Append" } } } },
			})

			assert.are.same({ "<F8>", desc = "Append" }, config.opts.ui.compose.keymaps.append_next)
		end)

		it("does not inherit a global description into a runtime binding", function()
			local resolved, errors = compose_config.resolve({
				keymaps = { send = { "<F8>", mode = "i", desc = "Global send" } },
			}, {
				keymaps = { send = { "<F9>", mode = "n" } },
			}, "opts.compose")

			assert.are.same({}, errors)
			assert.are.same({ "<F9>", mode = "n" }, resolved.keymaps.send)
		end)

		it("does not inherit a global mode into a runtime binding", function()
			local resolved, errors = compose_config.resolve({
				keymaps = { send = { "<F8>", mode = "i", desc = "Global send" } },
			}, {
				keymaps = { send = { "<F9>", desc = "Runtime send" } },
			}, "opts.compose")

			assert.are.same({}, errors)
			assert.are.same({ "<F9>", desc = "Runtime send" }, resolved.keymaps.send)
		end)

		it("does not inherit a shipped description into an explicit global binding", function()
			config.setup({
				log_level = "off",
				ui = { compose = { keymaps = { append_next = { "<F8>", mode = "i" } } } },
			})

			assert.are.same({ "<F8>", mode = "i" }, config.opts.ui.compose.keymaps.append_next)
		end)
	end)

	describe("compose option normalization", function()
		it("keeps valid action defaults while dropping malformed fields", function()
			config.setup({
				log_level = "off",
				actions = { send = { compose = { title = " Action Compose ", width = "wide" } } },
			})

			assert.are.same({ title = " Action Compose " }, config.opts.actions.send.compose)
		end)

		it("reports every malformed runtime option with its path and message", function()
			local normalized, errors = compose_config.options({
				on_new_payload = "merge",
				capture_placeholders = { "file" },
				keymaps = { send = { "<F8>", mode = "bad" } },
			}, "item.compose")

			assert.are.same({}, normalized)
			assert.are.equal(3, #errors)
			local paths = {}
			for _, err in ipairs(errors) do
				paths[err.path] = true
				assert.is_string(err.message)
			end
			assert.is_true(paths["item.compose.on_new_payload"])
			assert.is_true(paths["item.compose.capture_placeholders"])
			assert.is_true(paths["item.compose.keymaps.send.mode"])
		end)

		it("merges runtime overrides with global session fields", function()
			local global = {
				width = 0.6,
				height = 0.4,
				title = " Global ",
				wo = { wrap = true, number = false },
			}

			local resolved, errors = compose_config.resolve(global, {
				title = " Runtime ",
				wo = { number = true },
			}, "opts.compose")

			assert.are.same({}, errors)
			assert.are.equal(0.6, resolved.width)
			assert.are.equal(" Runtime ", resolved.title)
			assert.are.same({ wrap = true, number = true }, resolved.wo)
			assert.are.equal(" Global ", global.title)
			assert.are.same({ wrap = true, number = false }, global.wo)
		end)
	end)
end)
