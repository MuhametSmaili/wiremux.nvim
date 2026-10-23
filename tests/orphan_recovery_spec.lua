---@module 'luassert'

local helpers = require("tests.helpers")

describe("orphan recovery through send", function()
	local modules = {
		"wiremux.backend",
		"wiremux.backend.tmux",
		"wiremux.backend.tmux.client",
		"wiremux.backend.tmux.state",
		"wiremux.backend.tmux.operation",
		"wiremux.core.action",
		"wiremux.core.resolver",
		"wiremux.config",
		"wiremux.picker",
		"wiremux.statusline",
		"wiremux.utils.notify",
	}
	local saved, client, picker, metadata, writes, errors

	before_each(function()
		saved = {}
		for _, name in ipairs(modules) do
			saved[name] = package.loaded[name]
			package.loaded[name] = nil
		end
		metadata = {
			session_id = "$1",
			pane_id = "%2",
			window_id = "@2",
			window_index = "2",
			pane_index = "0",
			["@wiremux_target"] = "terminal",
			["@wiremux_origin"] = "%9",
			["@wiremux_kind"] = "window",
		}
		writes, errors = {}, {}
		local query = require("wiremux.backend.tmux.query")
		local function render(fields)
			return (query.list_panes()[4]:gsub("#{(.-)}", function(key)
				return fields[key] or ""
			end))
		end
		client = {
			query = function()
				return {
					"%0" .. query.FIELD_SEPARATOR .. "$1",
					render({ session_id = "$1", pane_id = "%0", window_id = "@1" }) .. "\n" .. render(metadata),
				}
			end,
			execute = function(commands, opts)
				table.insert(writes, { commands = commands, stdin = opts and opts.stdin })
				if opts and opts.stdin then
					assert.are.equal("%0", metadata["@wiremux_origin"], "adoption must finish before delivery")
				end
				for _, command in ipairs(commands) do
					if command[1] == "set-option" then
						metadata[command[5]] = command[6]
					end
				end
				return ""
			end,
		}
		picker = {
			select = function(_, _, choose)
				choose(nil)
			end,
		}
		helpers.register({
			["wiremux.backend.tmux.client"] = client,
			["wiremux.backend"] = {
				get = function()
					return require("wiremux.backend.tmux")
				end,
			},
			["wiremux.picker"] = picker,
			["wiremux.utils.notify"] = {
				debug = function() end,
				warn = function(msg)
					error(msg)
				end,
				error = function(msg)
					table.insert(errors, msg)
				end,
			},
		})
	end)

	after_each(function()
		for _, name in ipairs(modules) do
			package.loaded[name] = saved[name]
		end
	end)

	it("leaves ownership unchanged when the adoption picker is cancelled", function()
		local picked = false
		picker.select = function(items, _, choose)
			picked = true
			assert.are.equal(1, #items)
			assert.are.equal("adopt", items[1].type)
			choose(nil)
		end

		local ok, err = require("wiremux.action.send.delivery").send("payload", { mode = "all", behavior = "pick" })

		assert.is_true(ok, err)
		assert.is_true(picked)
		assert.are.same({}, writes)
		assert.are.equal("%9", metadata["@wiremux_origin"])
	end)

	it("reassigns the selected orphan before sending and reuses it on the next send", function()
		local picks = 0
		picker.select = function(items, _, choose)
			picks = picks + 1
			assert.are.equal("adopt", items[1].type)
			choose(items[1])
		end
		local delivery = require("wiremux.action.send.delivery")
		local options = { mode = "auto", behavior = "pick", focus = false }

		local ok, err = delivery.send("prepared {literal}", options)
		assert.is_true(ok, err)
		assert.are.equal("%0", metadata["@wiremux_origin"])
		assert.are.equal("terminal", metadata["@wiremux_target"])
		assert.are.equal("window", metadata["@wiremux_kind"])
		assert.are.equal("prepared {literal}", writes[2].stdin)
		assert.are.same({ "paste-buffer", "-b", "wiremux", "-p", "-t", "%2" }, writes[2].commands[2])

		ok, err = delivery.send("again", options)
		assert.is_true(ok, err)
		assert.are.equal(1, picks)
		assert.are.equal("again", writes[3].stdin)
		assert.are.same({}, errors)
	end)

	it("does not send or change in-memory ownership if adoption fails", function()
		local selected
		picker.select = function(items, _, choose)
			selected = items[1].instance
			choose(items[1])
		end
		client.execute = function(_, opts)
			assert.is_nil(opts, "must not deliver a payload after failed adoption")
			return nil
		end

		local ok, err = require("wiremux.action.send.delivery").send("payload", { mode = "all", behavior = "pick" })

		assert.is_true(ok, err)
		assert.is_true(selected.orphaned)
		assert.are.equal("%9", selected.origin)
		assert.are.equal("%9", metadata["@wiremux_origin"])
		assert.are.equal(1, #errors)
		assert.matches("Failed to adopt", errors[1])
	end)

	it("does not count orphaned targets in the statusline before adoption", function()
		local statusline = require("wiremux.statusline")
		statusline.update(require("wiremux.backend.tmux.state").get())
		assert.are.equal(0, statusline.get_info().count)
	end)
end)
