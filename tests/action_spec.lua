---@module 'luassert'

local helpers = require("tests.helpers_action")

describe("action", function()
	local mocks

	before_each(function()
		mocks = helpers.setup()
	end)

	after_each(function()
		helpers.teardown()
	end)

	describe("run with targets result", function()
		it("executes callback with targets", function()
			local executed = false
			local received_targets

			mocks.resolver.resolve = function()
				return {
					kind = "targets",
					targets = {
						{ id = "%1", kind = "pane", target = "test" },
					},
				}
			end

			mocks.action.run({ prompt = "Test", behavior = "all" }, {
				on_targets = function(targets, state)
					executed = true
					received_targets = targets
				end,
			})

			assert.is_true(executed)
			assert.are.equal(1, #received_targets)
			assert.are.equal("%1", received_targets[1].id)
		end)
	end)

	describe("run with pick result", function()
		it("shows picker when result is pick", function()
			local picker_shown = false

			mocks.resolver.resolve = function()
				return {
					kind = "pick",
					items = {
						{ type = "instance", instance = { id = "%1" }, label = "test" },
					},
				}
			end

			mocks.picker.select = function(items, opts, callback)
				picker_shown = true
				assert.are.equal(1, #items)
				assert.are.equal("Test Prompt", opts.prompt)
			end

			mocks.action.run({ prompt = "Test Prompt", behavior = "pick" }, {
				on_targets = function() end,
			})

			assert.is_true(picker_shown)
		end)

		it("executes callback when instance is picked", function()
			local executed = false

			mocks.resolver.resolve = function()
				return {
					kind = "pick",
					items = {
						{
							type = "instance",
							instance = { id = "%1", kind = "pane", target = "test" },
							label = "test",
						},
					},
				}
			end

			mocks.picker.select = function(items, opts, callback)
				-- Simulate user picking first item
				callback(items[1])
			end

			mocks.action.run({ prompt = "Test", behavior = "pick" }, {
				on_targets = function(targets, state)
					executed = true
					assert.are.equal(1, #targets)
					assert.are.equal("%1", targets[1].id)
				end,
			})

			assert.is_true(executed)
		end)

		it("dispatches an unmanaged instance for adoption", function()
			local adopted
			local instance = { id = "%7", kind = "pane", managed = false }

			mocks.resolver.resolve = function()
				return {
					kind = "pick",
					items = {
						{ type = "adopt", instance = instance, label = "[~] %7" },
					},
				}
			end

			mocks.picker.select = function(items, _, callback)
				callback(items[1])
			end

			mocks.action.run({ prompt = "Test", behavior = "pick" }, {
				on_adopt = function(received)
					adopted = received
				end,
			})

			assert.are.equal(instance, adopted)
		end)

		it("creates target when definition is picked", function()
			local create_called = false
			local executed = false

			mocks.resolver.resolve = function()
				return {
					kind = "pick",
					items = {
						{
							type = "definition",
							target = "server",
							def = { kind = "pane" },
							label = "server",
						},
					},
				}
			end

			mocks.backend.create = function(name, def, state)
				create_called = true
				assert.are.equal("server", name)
				return { id = "%1", kind = "pane", target = "server" }
			end

			mocks.picker.select = function(items, opts, callback)
				callback(items[1])
			end

			mocks.action.run({ prompt = "Test", behavior = "pick" }, {
				on_definition = function(name, def, state)
					executed = true
					assert.are.equal("server", name)
					local inst = mocks.backend.create(name, def, state)
					assert.are.equal("%1", inst.id)
				end,
			})

			assert.is_true(create_called)
			assert.is_true(executed)
		end)

		it("handles create failure gracefully", function()
			local error_shown = false

			mocks.resolver.resolve = function()
				return {
					kind = "pick",
					items = {
						{
							type = "definition",
							target = "server",
							def = { kind = "pane" },
							label = "server",
						},
					},
				}
			end

			mocks.backend.create = function()
				return nil -- Simulate failure
			end

			mocks.notify.error = function(msg)
				error_shown = true
				assert.matches("failed to create", msg)
			end

			mocks.picker.select = function(items, opts, callback)
				callback(items[1])
			end

			mocks.action.run({ prompt = "Test", behavior = "pick" }, {
				on_definition = function(name, def, state)
					local inst = mocks.backend.create(name, def, state)
					if not inst then
						mocks.notify.error("failed to create target: " .. name)
					end
				end,
			})

			assert.is_true(error_shown)
		end)

		it("handles picker cancellation", function()
			mocks.resolver.resolve = function()
				return {
					kind = "pick",
					items = {
						{ type = "instance", instance = { id = "%1" }, label = "test" },
					},
					has_instances = true,
					has_definitions = false,
				}
			end

			mocks.picker.select = function(items, opts, callback)
				callback(nil) -- User cancelled
			end

			mocks.action.run({ prompt = "Test", behavior = "pick" }, {
				on_targets = function()
					error("should not execute when cancelled")
				end,
			})

			-- Test passes if no error thrown
		end)
	end)

	describe("run with no targets", function()
		it("shows warning when no targets available", function()
			local warned = false

			mocks.resolver.resolve = function()
				return { kind = "pick", items = {} }
			end

			mocks.notify.warn = function(msg)
				warned = true
				assert.matches("No targets", msg)
			end

			mocks.action.run({ prompt = "Test", behavior = "pick" }, {
				on_targets = function()
					error("should not execute")
				end,
			})

			assert.is_true(warned)
		end)
	end)

	describe("real resolver integration", function()
		before_each(function()
			package.loaded["wiremux.core.resolver"] = nil
		end)

		describe("action labels", function()
			local reads, label

			before_each(function()
				reads, label = 0, nil
				mocks.config.opts.actions = { focus = {}, close = {}, toggle = { focus = false } }
				mocks.backend.state.get = function()
					reads = reads + 1
					return {
						origin_pane_id = "%0",
						session_id = "$1",
						instances = {
							{
								id = "%1",
								managed = true,
								target = "terminal",
								origin = "%0",
								session_id = "$1",
								kind = "pane",
								window_index = 2,
								pane_index = 1,
								window_name = "dev",
								running_command = "node",
							},
							{
								id = "%2",
								managed = true,
								target = "other",
								origin = "%0",
								session_id = "$1",
								kind = "pane",
							},
						},
					}
				end
				mocks.picker.select = function(items, opts, choose)
					label = opts.format_item(items[1])
					assert.are.equal(label, opts.format_item(items[1]))
					choose(nil)
				end
			end)

			it("omits the send badge while reusing one state refresh", function()
				local ok, err =
					require("wiremux.action.send.delivery").send("payload", { behavior = "pick", mode = "all" })

				assert.is_true(ok, err)
				assert.are.equal("           2:1    terminal · dev [node]", label)
				assert.are.equal(1, reads)
			end)

			for _, case in ipairs({
				{ action = "focus", label = "[focus]    2:1    terminal · dev [node]" },
				{ action = "close", label = "[close]    2:1    terminal · dev [node]" },
				{ action = "toggle", label = "[toggle]   2:1    terminal · dev [node]" },
			}) do
				it("labels " .. case.action .. " rows without implying a send", function()
					require("wiremux.action." .. case.action)[case.action]({ behavior = "pick" })

					assert.are.equal(case.label, label)
					assert.are.equal(1, reads)
				end)
			end
		end)

		it("never feeds unmanaged panes into a toggle filter", function()
			mocks.config.opts.actions.toggle = { focus = false }
			mocks.config.opts.targets.definitions = { terminal = { kind = "pane" } }
			mocks.backend.state.get = function()
				return {
					instances = { { id = "%1", managed = true, target = "other", kind = "pane" } },
					panes = { { id = "%2", managed = false, kind = "pane" } },
				}
			end
			mocks.backend.create = function()
				error("must wait for selection")
			end
			local picks, filtered = 0, 0
			mocks.picker.select = function(items, _, callback)
				picks = picks + 1
				assert.are.equal(1, #items)
				assert.are.equal("definition", items[1].type)
				callback(nil)
			end
			for _, mode in ipairs({ "auto", "all" }) do
				require("wiremux.action.toggle").toggle({
					mode = mode,
					filter = {
						instances = function(inst)
							filtered = filtered + 1
							return inst.target:match("^terminal$") ~= nil
						end,
					},
				})
			end
			assert.are.equal(2, picks)
			assert.are.equal(2, filtered)
		end)

		it("cancels, adopts and sends a prepared payload, then uses the managed target", function()
			local pane = { id = "%7", managed = false, kind = "pane" }
			local state = {
				origin_pane_id = "%0",
				instances = {},
				panes = {
					{ id = "%0", managed = false, kind = "pane" },
					pane,
				},
			}
			mocks.backend.state.get = function()
				return state
			end
			mocks.config.opts.targets.definitions = { terminal = { kind = "pane" } }
			mocks.backend.create = function()
				error("must not create")
			end
			local picks, adoptions, sends = 0, 0, 0
			mocks.picker.select = function(items, _, callback)
				picks = picks + 1
				assert.are.equal(2, #items)
				assert.are.equal("adopt", items[1].type)
				assert.are.equal("definition", items[2].type)
				callback(picks == 2 and items[1] or nil)
			end
			mocks.backend.adopt = function(inst, received_state)
				adoptions = adoptions + 1
				assert.are.equal(pane, inst)
				assert.are.equal(state, received_state)
				inst.managed, inst.target = true, "pane-7"
				state.instances = { inst }
				return true
			end
			mocks.backend.send = function(payload, targets, opts, received_state)
				sends = sends + 1
				assert.are.equal(1, adoptions)
				assert.are.equal("prepared\n{literal}", payload)
				assert.are.same({ pane }, targets)
				assert.is_true(targets[1].managed)
				assert.are.equal(state, received_state)
				assert.are.same({ focus = false, pre_keys = { "C-c" }, post_keys = { "Enter" } }, opts)
			end
			local options =
				{ behavior = "pick", mode = "all", focus = false, pre_keys = { "C-c" }, post_keys = { "Enter" } }
			local delivery = require("wiremux.action.send.delivery")
			assert.is_true(delivery.send("prepared\n{literal}", options))
			assert.are.equal(0, adoptions)
			assert.are.equal(0, sends)
			assert.is_true(delivery.send("prepared\n{literal}", options))
			assert.are.equal(1, sends)
			options.mode = "auto"
			assert.is_true(delivery.send("prepared\n{literal}", options))
			assert.are.equal(2, sends)
			assert.are.equal(2, picks)
			assert.are.equal(1, adoptions)
		end)
	end)

	describe("adopt", function()
		describe("default rows", function()
			local target, state, labels, reads

			before_each(function()
				target = {
					id = "%1",
					managed = false,
					session_id = "$1",
					kind = "pane",
					window_index = 2,
					pane_index = 1,
					window_name = "dev",
					running_command = "node",
				}
				state = { origin_pane_id = "%0", session_id = "$1", instances = {}, panes = { target } }
				labels, reads = {}, 0
				mocks.backend.state.get = function()
					reads = reads + 1
					return state
				end
				mocks.backend.adopt = function()
					error("cancellation must not adopt")
				end
				mocks.backend.send = function()
					error("standalone adoption must not send")
				end
				mocks.picker.select = function(items, opts, choose)
					for _, item in ipairs(items) do
						labels[item.id] = opts.format_item(item)
						assert.are.equal(labels[item.id], opts.format_item(item))
					end
					choose(nil)
				end
			end)

			it("uses the same pane and window layout without extra discovery or mutation", function()
				local before = vim.deepcopy(state)

				require("wiremux.action.adopt").adopt()

				assert.are.equal("[adopt]    2:1    node · dev", labels["%1"])
				assert.are.equal(1, reads)
				assert.are.same(before, state)
			end)

			it("marks targets already owned by this pane", function()
				target.managed, target.origin, target.target = true, "%0", "terminal"

				require("wiremux.action.adopt").adopt()

				assert.are.equal("[yours]    2:1    terminal · dev [node]", labels["%1"])
			end)

			it("distinguishes a confirmed orphan from a live foreign owner", function()
				target.managed, target.orphaned, target.origin, target.target = true, true, "%9", "terminal"

				require("wiremux.action.adopt").adopt()

				assert.are.equal("[re-adopt] 2:1    terminal · dev [node]", labels["%1"])
			end)

			it("shows a foreign owner's location even when session filtering hides it", function()
				target.managed, target.origin, target.target = true, "%9", "terminal"
				table.insert(state.panes, { id = "%9", session_id = "$2", window_index = 4, pane_index = 0 })

				require("wiremux.action.adopt").adopt()

				assert.are.equal("[reassign] 2:1    terminal · dev [node] (owner $2:4:0)", labels["%1"])
				assert.is_nil(labels["%9"])
				assert.are.equal(1, reads)
			end)

			it("shows an owner's location when a custom filter hides it from the current snapshot", function()
				target.managed, target.origin = true, "%9"
				table.insert(state.panes, { id = "%9", session_id = "$1", window_index = 4, pane_index = 0 })

				require("wiremux.action.adopt").adopt({
					filter = {
						instances = function(inst)
							return inst.id == "%1"
						end,
					},
				})

				assert.are.equal("[reassign] 2:1    node · dev (owner 4:0)", labels["%1"])
				assert.is_nil(labels["%9"])
			end)

			it("finds the owner in legacy instances even when a custom filter hides it", function()
				target.managed, target.origin = true, "%9"
				state.instances = { target, { id = "%9", session_id = "$1", window_index = 4, pane_index = 0 } }
				state.panes = nil

				require("wiremux.action.adopt").adopt({
					filter = {
						instances = function(inst)
							return inst.id == "%1"
						end,
					},
				})

				assert.are.equal("[reassign] 2:1    node · dev (owner 4:0)", labels["%1"])
				assert.is_nil(labels["%9"])
			end)

			it("does not infer an orphan from an unverified missing owner", function()
				target.managed, target.origin = true, "%9"

				require("wiremux.action.adopt").adopt()

				assert.are.equal("[reassign] 2:1    node · dev (owner %9, unverified)", labels["%1"])
				assert.is_nil(target.orphaned)
			end)

			it("does not treat absent owner and current-pane metadata as already yours", function()
				target.managed = true
				state.origin_pane_id = nil

				require("wiremux.action.adopt").adopt()

				assert.are.equal("[adopt]    2:1    node · dev (owner unknown)", labels["%1"])
			end)

			it("ignores leftover ownership metadata on unmanaged panes", function()
				target.origin = "%9"

				require("wiremux.action.adopt").adopt()

				assert.are.equal("[adopt]    2:1    node · dev", labels["%1"])
			end)

			it("hides generated target names and duplicate window or command hints", function()
				target.target, target.window_name = "pane-1", "node"

				require("wiremux.action.adopt").adopt()

				assert.are.equal("[adopt]    2:1    node", labels["%1"])
			end)

			it("uses a pane fallback when names and commands are empty", function()
				target.target, target.running_command, target.window_name = "", "", ""

				require("wiremux.action.adopt").adopt()

				assert.are.equal("[adopt]    2:1    pane", labels["%1"])
			end)

			it("passes the selected foreign-owned pane to adoption without sending", function()
				local adoptions = 0
				target.managed, target.origin = true, "%9"
				mocks.backend.adopt = function(selected, snapshot, opts)
					assert.are.equal(target, selected)
					assert.are.equal(state, snapshot)
					assert.are.equal("terminal", opts.target)
					adoptions = adoptions + 1
					return true
				end
				mocks.picker.select = function(items, opts, choose)
					assert.are.equal("[reassign] 2:1    node · dev (owner %9, unverified)", opts.format_item(items[1]))
					choose(items[1])
				end

				require("wiremux.action.adopt").adopt({ target = "terminal" })

				assert.are.equal(1, adoptions)
				assert.are.equal(1, reads)
			end)
		end)

		it("shows all current-session panes", function()
			local adopted

			mocks.backend.state.get = function()
				return {
					origin_pane_id = "%0",
					session_id = "$1",
					instances = {
						{ session_id = "$1", id = "%0", target = "current", kind = "pane" },
						{ session_id = "$1", id = "%1", target = "server", kind = "pane", running_command = "zsh" },
						{ session_id = "$2", id = "%2", target = "other", kind = "pane" },
					},
					panes = {
						{
							session_id = "$1",
							id = "%0",
							target = "current",
							kind = "pane",
							window_index = 1,
							pane_index = 0,
						},
						{
							session_id = "$1",
							id = "%1",
							target = "server",
							kind = "pane",
							window_index = 1,
							pane_index = 1,
							running_command = "zsh",
						},
						{
							session_id = "$1",
							id = "%3",
							kind = "pane",
							window_index = 2,
							pane_index = 0,
							running_command = "fish",
						},
						{
							session_id = "$2",
							id = "%2",
							target = "other",
							kind = "pane",
							window_index = 1,
							pane_index = 0,
						},
					},
				}
			end

			mocks.backend.adopt = function(target)
				adopted = target
				return true
			end

			mocks.picker.select = function(items, opts, callback)
				assert.are.equal("Adopt target", opts.prompt)
				assert.are.equal(2, #items)
				assert.are.equal("%1", items[1].id)
				assert.are.equal("%3", items[2].id)
				assert.are.equal("[adopt]    1:1    server [zsh]", opts.format_item(items[1]))
				assert.are.equal("[adopt]    2:0    fish", opts.format_item(items[2]))
				callback(items[1])
			end

			require("wiremux.action.adopt").adopt()

			assert.are.equal("%1", adopted.id)
		end)

		it("applies an optional local instance filter", function()
			local adopted

			mocks.backend.state.get = function()
				return {
					origin_pane_id = "%0",
					session_id = "$1",
					instances = {
						{ session_id = "$1", id = "%1", target = "server", kind = "pane" },
						{ session_id = "$1", id = "%2", target = "claude", kind = "pane" },
					},
				}
			end

			mocks.backend.adopt = function(target)
				adopted = target
				return true
			end

			mocks.picker.select = function(items, _, callback)
				assert.are.equal(1, #items)
				assert.are.equal("%2", items[1].id)
				callback(items[1])
			end

			require("wiremux.action.adopt").adopt({
				filter = {
					instances = function(inst)
						return inst.target == "claude"
					end,
				},
			})

			assert.are.equal("%2", adopted.id)
		end)

		it("lets a local filter choose cross-session and unmanaged panes", function()
			local adopted
			local adopt_opts

			mocks.backend.state.get = function()
				return {
					origin_pane_id = "%0",
					session_id = "$1",
					instances = {
						{ session_id = "$1", id = "%1", target = "server", kind = "pane" },
					},
					panes = {
						{ session_id = "$1", id = "%0", target = "current", kind = "pane" },
						{ session_id = "$1", id = "%1", target = "server", kind = "pane" },
						{ session_id = "$2", id = "%2", target = "remote", kind = "pane" },
						{ session_id = "$2", id = "%3", kind = "pane", running_command = "zsh" },
					},
				}
			end

			mocks.backend.adopt = function(target, _, opts)
				adopted = target
				adopt_opts = opts
				return true
			end

			mocks.picker.select = function(items, opts, callback)
				assert.are.equal(3, #items)
				assert.are.equal("%1", items[1].id)
				assert.are.equal("%2", items[2].id)
				assert.are.equal("%3", items[3].id)
				assert.are.equal("[adopt]    $2:3   zsh", opts.format_item(items[3]))
				callback(items[3])
			end

			require("wiremux.action.adopt").adopt({
				target = "terminal",
				filter = {
					instances = function()
						return true
					end,
				},
			})

			assert.are.equal("%3", adopted.id)
			assert.are.equal("terminal", adopt_opts.target)
		end)

		it("uses an optional local item formatter", function()
			mocks.backend.state.get = function()
				return {
					origin_pane_id = "%0",
					session_id = "$1",
					panes = {
						{ session_id = "$1", id = "%1", target = "server", kind = "pane", running_command = "zsh" },
					},
					instances = {},
				}
			end

			mocks.backend.adopt = function()
				return true
			end

			mocks.picker.select = function(items, opts, callback)
				assert.are.equal("server:%1:$1", opts.format_item(items[1]))
				callback(items[1])
			end

			require("wiremux.action.adopt").adopt({
				format_item = function(inst, state)
					return string.format("%s:%s:%s", inst.target, inst.id, state.session_id)
				end,
			})
		end)

		it("leaves default target naming to the backend", function()
			local adopted
			local adopt_opts

			mocks.backend.state.get = function()
				return {
					origin_pane_id = "%0",
					session_id = "$1",
					instances = {},
					panes = {
						{ session_id = "$1", id = "%1", kind = "pane" },
					},
				}
			end

			mocks.backend.adopt = function(target, _, opts)
				adopted = target
				adopt_opts = opts
				return true
			end

			mocks.picker.select = function(items, _, callback)
				callback(items[1])
			end

			require("wiremux.action.adopt").adopt()

			assert.are.equal("%1", adopted.id)
			assert.is_nil(adopt_opts.target)
		end)

		it("warns when no current-session targets can be adopted", function()
			local warned = false

			mocks.backend.state.get = function()
				return {
					origin_pane_id = "%0",
					session_id = "$1",
					instances = {
						{ session_id = "$1", id = "%0", target = "current", kind = "pane" },
						{ session_id = "$2", id = "%2", target = "other", kind = "pane" },
					},
				}
			end

			mocks.notify.warn = function(msg)
				warned = true
				assert.matches("No adoptable", msg)
			end

			require("wiremux.action.adopt").adopt()

			assert.is_true(warned)
		end)
	end)
end)
