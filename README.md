# wiremux.nvim

Send code, prompts, and commands from Neovim to programs in tmux.
Use Wiremux with AI assistants, terminals, or other tools.

https://github.com/user-attachments/assets/77d5735d-515b-467e-87c5-417189a6359e

## How to think about Wiremux

A **target** is a tmux pane or window that receives your text.
Wiremux connects your editor to that target.

| Term           | Meaning                                                                                   |
| -------------- | ----------------------------------------------------------------------------------------- |
| **Definition** | Configuration that tells Wiremux how to create a target.                                  |
| **Instance**   | A tmux pane or window that already exists. One definition can create several instances.   |
| **Draft**      | A message that you edit in Compose before you send it. A draft can contain several pages. |

Definitions live in your Neovim configuration. Target metadata lives in tmux.
Target panes remain in tmux after you restart Neovim.

## Install and send your first message

Use Neovim 0.11 or later inside tmux. We recommend tmux 3.0 or later.

Add this [lazy.nvim](https://github.com/folke/lazy.nvim) specification:

```lua
{
  "MuhametSmaili/wiremux.nvim",
  cmd = "Wiremux",
  opts = {
    targets = {
      definitions = {
        terminal = { kind = "pane", split = "horizontal" },
      },
    },
  },
}
```

1. Run `:Wiremux create`.
2. Select `terminal` to create its pane.
3. Return to the Neovim pane with your tmux navigation keys.
4. Run `:Wiremux send ls -la`.

Wiremux pastes `ls -la` into the terminal and moves focus there.
Press Enter in that pane to run the command.

Wiremux does not need an extra picker plugin. It can use fzf-lua, Snacks, or `vim.ui.select`.

<details>
<summary>Other plugin managers</summary>

Install the plugin with your manager:

```lua
-- packer.nvim
use { "MuhametSmaili/wiremux.nvim" }
```

```vim
" vim-plug
Plug 'MuhametSmaili/wiremux.nvim'
```

After the plugin loads, configure the terminal definition:

```lua
require("wiremux").setup({
  targets = {
    definitions = {
      terminal = { kind = "pane", split = "horizontal" },
    },
  },
})
```

</details>

<details>
<summary>Default configuration</summary>

These are the shipped defaults. Copy only the options you want to change into your existing configuration.
Wiremux has no target definitions or editor-wide keymaps by default.

```lua
require("wiremux").setup({
  log_level = "warn",
  targets = {
    definitions = {},
  },
  actions = {
    close = { behavior = "pick" },
    create = { behavior = "pick", focus = true },
    send = { behavior = "pick", focus = true, compose = false },
    focus = { behavior = "last", focus = true },
    toggle = { behavior = "last", focus = false },
  },
  context = {
    resolvers = {},
  },
  ui = {
    compose = {
      width = 0.6,
      height = 0.4,
      title = " Compose Message ",
      border = "rounded",
      style = "minimal",
      close_behavior = "ask",
      on_new_payload = "ask",
      history_limit = 0,
      use_default_keymaps = true,
      wo = {
        wrap = true,
        number = false,
        relativenumber = false,
      },
      keymaps = {
        send = { { "<CR>", mode = { "n" }, desc = "Send to target" } },
        close = {
          { "q", mode = "n", desc = "Close draft" },
          { "<Esc>", mode = "n", desc = "Close draft" },
        },
        append_next = { "<C-s>", mode = "n", desc = "Hide and append next payload" },
        discard = { "Q", mode = "n", desc = "Discard compose page" },
        files = { { "<C-f>", mode = { "n", "i" }, desc = "Insert file" } },
        delete_page = { "<C-x>", mode = "n", desc = "Delete compose page" },
        preview_placeholder = { "K", mode = "n", desc = "Preview placeholder" },
        previous = { "<C-p>", mode = "n", desc = "Previous compose page" },
        next = { "<C-n>", mode = "n", desc = "Next compose page" },
      },
    },
  },
  picker = {
    adapter = nil, -- Detect fzf-lua or Snacks, then fall back to vim.ui.select.
    instances = {
      filter = function(inst, state)
        if not inst.managed or inst.orphaned then
          return inst.session_id == state.session_id
        end
        return inst.origin == state.origin_pane_id
      end,
      sort = function(a, b)
        return (a.last_used_at or 0) > (b.last_used_at or 0)
      end,
    },
    targets = {
      filter = nil,
      sort = nil,
    },
  },
})
```

</details>

<details>
<summary>Real-life configuration: AI tools, keymaps, and prompts</summary>

Use this lazy.nvim specification instead of the minimal example.
Change the tools, keys, and prompts to match your workflow.
Install the AI tools you want to use. Remove definitions for tools you do not use.

Lowercase message keys add to a draft. Uppercase message keys send directly to the last target.
This example enables Compose by default and saves the last three confirmed messages.

```lua
local review_changes = "Review the changes in {file} for bugs and regressions."
  .. "\nReport findings with file/line references."
  .. "\nDo not modify files."
  .. "\n\n{changes}"

local prompts = {
  { label = "Review file changes", value = review_changes },
  { label = "Fix file diagnostics", value = "Fix the diagnostics in {file}:\n{diagnostics_all}" },
  { label = "Fix line diagnostics", value = "Fix this diagnostic:\n{diagnostics}" },
  { label = "Add docs", value = "Add documentation to {this}" },
  { label = "Explain", value = "Explain {this}" },
  { label = "Fix", value = "Fix {this}" },
  { label = "Optimize", value = "How can {this} be optimized?" },
  { label = "Review file", value = "Review {file} for issues" },
  { label = "Write tests", value = "Write tests for {this}" },
  { label = "Fix quickfix entries", value = "Help me fix these issues:\n{quickfix}" },
}

return {
  "MuhametSmaili/wiremux.nvim",
  cmd = "Wiremux",
  opts = {
    targets = {
      definitions = {
        pi = { cmd = "pi", kind = { "pane", "window" }, split = "horizontal", shell = false },
        opencode = { cmd = "opencode", kind = { "pane", "window" }, split = "horizontal", shell = false },
        claudecode = { cmd = "claude", kind = { "pane", "window" }, split = "horizontal", shell = false },
        kiro = { cmd = "kiro-cli", kind = { "pane", "window" }, split = "horizontal", shell = false },
      },
    },
    actions = {
      send = { compose = true, behavior = "pick", focus = true, submit = false },
    },
    ui = {
      compose = {
        close_behavior = "hide",
        on_new_payload = "append",
        history_limit = 3,
      },
    },
  },
  keys = {
    {
      "<leader>aa",
      function() require("wiremux").send("{this}") end,
      mode = { "n", "x" },
      desc = "Add context to draft",
    },
    {
      "<leader>aA",
      function() require("wiremux").send("{this}", { compose = false, behavior = "last", focus = true }) end,
      mode = { "n", "x" },
      desc = "Send context directly",
    },
    {
      "<leader>ae",
      function() require("wiremux").send() end,
      desc = "Open or resume draft",
    },
    {
      "<leader>ar",
      function() require("wiremux").send(review_changes) end,
      desc = "Compose review of file changes",
    },
    {
      "<leader>aR",
      function() require("wiremux").send(review_changes, { compose = false, behavior = "last", focus = true }) end,
      desc = "Send review of file changes directly",
    },
    {
      "<leader>af",
      function() require("wiremux").send("{file}") end,
      desc = "Add file reference to draft",
    },
    {
      "<leader>aF",
      function() require("wiremux").send("{file}", { compose = false, behavior = "last", focus = true }) end,
      desc = "Send file reference directly",
    },
    {
      "<leader>av",
      function() require("wiremux").send("{selection}") end,
      mode = "x",
      desc = "Add selection to draft",
    },
    {
      "<leader>aV",
      function() require("wiremux").send("{selection}", { compose = false, behavior = "last", focus = true }) end,
      mode = "x",
      desc = "Send selection directly",
    },
    {
      "<leader>ad",
      function() require("wiremux").send("{diagnostics}") end,
      mode = { "n", "x" },
      desc = "Compose line diagnostics",
    },
    {
      "<leader>aD",
      function() require("wiremux").send("{diagnostics}", { compose = false, behavior = "last", focus = true }) end,
      mode = { "n", "x" },
      desc = "Send line diagnostics directly",
    },
    {
      "<leader>ag",
      function() require("wiremux").send("{diagnostics_all}") end,
      mode = { "n", "x" },
      desc = "Compose file diagnostics",
    },
    {
      "<leader>aG",
      function() require("wiremux").send("{diagnostics_all}", { compose = false, behavior = "last", focus = true }) end,
      mode = { "n", "x" },
      desc = "Send file diagnostics directly",
    },
    {
      "<leader>ap",
      function() require("wiremux").send(prompts) end,
      mode = { "n", "x" },
      desc = "Choose prompt for draft",
    },
    {
      "<leader>aP",
      function() require("wiremux").send(prompts, { compose = false, behavior = "last", focus = true }) end,
      mode = { "n", "x" },
      desc = "Choose prompt to send directly",
    },
    {
      "<leader>ah",
      function() require("wiremux").history() end,
      desc = "Recover a Compose message",
    },
    {
      "<leader>ac",
      function() require("wiremux").create() end,
      desc = "Create AI target",
    },
    {
      "<leader>ao",
      function() require("wiremux").focus({ behavior = "pick" }) end,
      desc = "Focus AI target",
    },
    {
      "<leader>ax",
      function() require("wiremux").close() end,
      desc = "Close AI target",
    },
    {
      "ga",
      function() return require("wiremux").send_motion({ compose = false }) end,
      mode = { "n", "x" },
      expr = true,
      desc = "Send motion or selection directly",
    },
  },
}
```

Press `<leader>ac` to create an AI target. Select a tool, then choose a pane or window.
Use `<leader>aa` to collect context from several locations.
Use `<leader>ae` to resume the draft without adding a page.

Use `<leader>ar` to compose a review request for the current file's changes.
The prompt asks for findings without file edits. `<leader>aR` sends that request directly.

Use `<leader>ap` to choose a prompt for the draft. `<leader>aP` sends the selected prompt directly.
Use `<leader>ah` to recover a saved message.

File references contain paths, not file contents. Messages do not press Enter in the target.
When you are ready to submit the message, press Enter in the target.

These mappings load Wiremux on first use. No extra picker plugin is required.
History remains off by default outside this example.

</details>

## Everyday use

### Send text

Use `send()` in Lua or in a keymap:

```lua
require("wiremux").send("Explain {this}")
```

`{this}` adds the source location and any visual selection.
Select code first to include it in the message.

<details>
<summary>Send a selection, run a command, or choose a prompt</summary>

Send only the selected text:

```lua
require("wiremux").send("{selection}", { focus = true })
```

Use `submit = true` to press Enter after the text:

```lua
require("wiremux").send("ls -la", { submit = true })
```

Pass a list to choose a prompt:

```lua
require("wiremux").send({
  { label = "Explain this", value = "Explain {this}" },
  { label = "Review changes", value = "Review my changes:\n{changes}" },
  { label = "Run tests", value = "npm test", submit = true },
})
```

Each item needs `value`. Optional fields include `label`, `visible`, `compose`, and `placeholders`.
See `:help wiremux.send()` for all item fields.

For keystrokes around the text, use `pre_keys` and `post_keys`:

```lua
require("wiremux").send({
  value = "my text",
  pre_keys = { "C-c" },
  post_keys = { "Escape" },
})
```

</details>

### Compose drafts

Compose lets you edit a message before you select a target:

```lua
require("wiremux").send("Review {this}", { compose = true })
```

In normal mode, press Enter to send the draft.
In insert mode, Enter adds a line.

**Unsent drafts last only for the current Neovim session.**

<details>
<summary>Default keys and page behavior</summary>

| Key                 | Mode             | Action                                            |
| ------------------- | ---------------- | ------------------------------------------------- |
| Enter               | Normal           | Send all pages.                                   |
| `q` / Escape        | Normal           | Close the draft according to its policy.          |
| `Ctrl+s`            | Normal           | Hide the draft and append the next Compose input. |
| `Ctrl+p` / `Ctrl+n` | Normal           | Select the previous / next page.                  |
| `Ctrl+x`            | Normal           | Delete the current page.                          |
| `Q`                 | Normal           | Discard the current page.                         |
| `K`                 | Normal           | Preview the placeholder under the cursor.         |
| `Ctrl+f`            | Normal or insert | Insert a file reference.                          |

If one page remains, `Ctrl+x` clears it without closing the draft.
`Q` discards that page and closes the draft.

Press `K` again to enter the preview. Press `q` or Escape there to close it.

The `close_behavior` option controls `q` and Escape.
Its default is `"ask"`. The other choices are `"hide"` and `"discard"`.

</details>

<details>
<summary>Collect notes from several locations</summary>

Use this mapping in normal or visual mode:

```lua
vim.keymap.set({ "n", "x" }, "<leader>ar", function()
  require("wiremux").send("Review this context:\n{this}", {
    compose = {
      title = " Review Context ",
      close_behavior = "hide",
      on_new_payload = "append",
    },
  })
end)
```

1. Select code at the first location.
2. Press `<leader>ar`.
3. Press `o` to add a line and enter insert mode.
4. Type your comment.
5. Press Escape to return to normal mode.
6. Press `q` to hide the draft.
7. Select code at another location.
8. Press `<leader>ar` again to add a page.

In normal mode, use `Ctrl+p` and `Ctrl+n` to review the pages.
Wiremux sends them together, with a blank line between pages.

Each page remembers its source location, selected text, and source line.
Other values resolve when you confirm the draft.

Call `require("wiremux").send()` without text to reopen the draft.
This call does not add a page.

By default, new text opens a choice dialog for an existing draft.
`on_new_payload = "append"` removes that extra choice.

</details>

History keeps recent messages for recovery and reuse. It is off by default.

<details>
<summary>Save and reuse messages with history</summary>

After you enable history:

- If a pane closes or delivery fails, you can recover the message.
- You can review the text of a previous message.
- You can send the same message to another pane.

To keep the last three confirmed Compose messages, add this to your existing options:

```lua
ui = {
  compose = {
    history_limit = 3,
  },
},
```

1. Run `:Wiremux history`.
2. Select a message to reopen it in Compose.
3. In normal mode, press Enter to send it.
4. If a target picker opens, choose a pane.

For a Lua keymap, use `require("wiremux").history()` to open the same picker.

You can edit the message before you send it.
History reopens the final text as one page. Placeholders do not resolve again.

Only confirmed Compose messages enter history. History stores their final text before delivery.

Files live in `stdpath("state")/wiremux/history/`.
A lower limit removes older entries on the next history access.
A limit of `0` removes all saved entries on that access.

See `:help wiremux-compose-history` for storage details.

</details>

### Placeholders

A placeholder adds editor context to your message. These are all the built-in placeholders:

| Placeholder         | Value                                 |
| ------------------- | ------------------------------------- |
| `{this}`            | Source location and visual selection. |
| `{selection}`       | Selected code.                        |
| `{file}`            | File path, not file contents.         |
| `{filename}`        | File name without the directory.      |
| `{position}`        | Source location as `file:line:col`.   |
| `{line}`            | Source line text.                     |
| `{diagnostics}`     | Diagnostics on the source line.       |
| `{diagnostics_all}` | All diagnostics in the source buffer. |
| `{quickfix}`        | Current quickfix entries.             |
| `{buffers}`         | Names of loaded, listed buffers.      |
| `{changes}`         | Git changes for the source file.      |

An unavailable placeholder stays unchanged.
Set `placeholders = false` on a send item to keep all tokens literal.
See `:help wiremux-placeholders` for resolution details.

<details>
<summary>Custom placeholders</summary>

Merge configuration examples into your existing options.
A new `setup()` call replaces the previous configuration.

Add custom resolvers under `context.resolvers`:

```lua
require("wiremux").setup({
  context = {
    resolvers = {
      git_branch = function()
        local result = vim.system({ "git", "branch", "--show-current" }, { text = true }):wait()
        return result.code == 0 and vim.trim(result.stdout) or nil
      end,
    },
  },
})
```

Use `{git_branch}` in your messages.
Resolver names start with a letter or underscore and contain only letters, digits, or underscores.

Return a string to replace the placeholder.
Return `nil` to keep it unchanged, or an empty string to remove it.

Resolvers can read the source `origin` argument.
It contains `bufnr`, `path`, `row`, `col`, `selection`, and `line`.
These fields stay fixed for each Compose page. Other editor values resolve on confirmation.

Keep resolvers fast. Do not change editor state from a resolver.
Each `setup()` call replaces custom resolvers and retains built-in resolvers.

</details>

## Customize

Merge these options into your existing configuration.

<details>
<summary>Target definitions and selection</summary>

Add definitions for your tools under `targets.definitions`:

```lua
targets = {
  definitions = {
    claude = { cmd = "claude", kind = { "pane", "window" }, shell = false },
    opencode = { cmd = "opencode", kind = { "pane", "window" }, shell = false },
  },
},
```

`kind` selects a pane or window. A list lets you choose at creation.
`shell = false` runs the program directly.

To select a named target, pass `target`:

```lua
require("wiremux").send("{this}", { target = "claude" })
```

Wiremux reuses matching instances or creates one from the definition.
Filters still apply. Multiple matches can open a picker.

If a definition has no `cmd`, create its terminal before you send arbitrary text.
Otherwise, Wiremux can use the first payload as its startup command.

| Option     | Choices                                   | Purpose                                                       |
| ---------- | ----------------------------------------- | ------------------------------------------------------------- |
| `behavior` | `pick`, `last`, `all`                     | Choose one target, reuse the last target, or use all matches. |
| `mode`     | `auto`, `instances`, `definitions`, `all` | Choose where `send()` and `toggle()` look for targets.        |

For `send()`, `auto` prefers managed instances.
If none pass the filter, Wiremux offers unmanaged panes and definitions.
For a mixed send picker, use `mode = "all"` with `behavior = "pick"`.

When matching managed instances exist, `behavior = "all"` sends to all of them.
If none match, Wiremux can offer adoption or creation.
`toggle()` does not adopt unmanaged panes.

See `:help wiremux-configuration` for target fields and selection options.

</details>

<details>
<summary>Pickers and filters</summary>

If neither fzf-lua nor Snacks is available, Wiremux uses `vim.ui.select`.
To choose an adapter, add this field to your options:

```lua
picker = {
  adapter = "fzf-lua", -- or "snacks"
},
```

By default, managed targets belong to the current tmux pane.
Adoption candidates include same-session unmanaged panes and targets whose owner no longer exists.

Use a filter to change the candidate list:

```lua
picker = {
  instances = {
    filter = function() return true end,
  },
},
```

This filter includes candidates from other sessions. Wiremux excludes the current pane.
`filter = nil` retains the default filter.

Unmanaged panes can have `target = nil`.
Before you use `target` as a string, make sure that `inst.managed` is true.

See `:help wiremux-filters` for instance and definition filters.

</details>

<details>
<summary>Compose keymaps</summary>

Map each action to one keymap or a list of keymaps:

```lua
ui = {
  compose = {
    keymaps = {
      send = { { "<F5>", mode = { "n", "i" } } },
      close = { { "<Esc>", mode = "n" } },
      preview_placeholder = {},
    },
  },
},
```

An omitted action inherits its mappings. A supplied entry replaces all mappings for that action.
An empty action entry disables its mappings.
An empty outer `keymaps` table does not clear defaults.

Set `ui.compose.use_default_keymaps = false` to omit all shipped Compose bindings.
Explicitly configured mappings still apply. This switch is global-only.

Native replacements, option changes, and deletions survive draft refreshes.
See `:help wiremux-compose-keymaps` for the full rules.

</details>

<details>
<summary>Native Compose mappings and actions</summary>

Before you open Compose, register this event handler:

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "WiremuxComposeOpen",
  callback = function(event)
    local buf = event.data.buf

    vim.keymap.set("n", "<F5>", function()
      require("wiremux").compose.send({ buf = buf })
    end, { buffer = buf, desc = "Send draft" })
  end,
})
```

The event runs after Wiremux installs its mappings.
It runs for new or restored windows, not when Wiremux only focuses a visible window.

Pass `{ buf = buf }` so an old callback cannot act on a newer draft.

`require("wiremux").compose` exposes draft actions such as `send()`, `close()`, `previous()`, and `next()`.
Root `require("wiremux").close()` closes a tmux target, not a draft.

A true action result means that the handler accepted the action, not that delivery succeeded.
See `:help wiremux-compose-api` for all actions and return values.

</details>

<details>
<summary>Placeholder completion with blink.cmp or nvim-cmp</summary>

Wiremux offers optional completion sources for Compose.
They suggest placeholders without executing their resolvers.

**blink.cmp**

Merge these settings with your existing sources:

```lua
completion = { documentation = { auto_show = true } },
sources = {
  default = function()
    local sources = { "lsp", "path", "snippets", "buffer" }
    if vim.b.wiremux_compose == true then
      sources[#sources + 1] = "wiremux"
    end
    return sources
  end,
  providers = {
    wiremux = {
      name = "Wiremux",
      module = "wiremux.completion.blink",
      opts = { preview = true },
    },
  },
},
```

This source check delays the Wiremux import until you enter Compose.
blink imports a provider before it checks the `enabled` callback for that provider.
For a Markdown source override, use `inherit_defaults = true` or the same Compose check.

**nvim-cmp**

Add `{ name = "wiremux" }` to your sources, including any Markdown override.
After cmp loads, register the source:

```lua
local function register_wiremux()
  if vim.b.wiremux_compose == true then
    require("wiremux.completion.cmp").register({ preview = true })
  end
end

vim.api.nvim_create_autocmd("BufEnter", {
  group = vim.api.nvim_create_augroup("wiremux_cmp", { clear = true }),
  callback = register_wiremux,
})
register_wiremux()
```

The immediate call handles an open Compose buffer. `BufEnter` handles later visits.

With `preview = true`, completion documentation shows up to 10 lines and 2,048 bytes.
These limits affect the display, not the message that you send.
Preview resolvers run synchronously. Omit `preview` for descriptions only.

Keep your usual Wiremux lazy-loading triggers.
See `:help wiremux-completion` for custom limits and integration details.

</details>

<details>
<summary>Statusline</summary>

Add the target count to lualine:

```lua
{
  require("wiremux").statusline.component(),
  padding = { left = 1, right = 1 },
}
```

For heirline or feline, use the component as a provider:

```lua
{ provider = require("wiremux").statusline.component() }
```

<img width="221" height="55" alt="Wiremux target count in the statusline" src="https://github.com/user-attachments/assets/c95f24b8-a121-4b75-a83c-07b1639cb75f" />

`statusline.get_info()` returns `{ loading, count, last_used }` for custom displays.

</details>

## Commands and help

Use `require("wiremux")` for Lua actions or `:Wiremux` on the command line:

| Lua action  | Command                | Purpose                    |
| ----------- | ---------------------- | -------------------------- |
| `send()`    | `:Wiremux send <text>` | Send text.                 |
| `create()`  | `:Wiremux create`      | Create a target.           |
| `toggle()`  | `:Wiremux toggle`      | Show or hide a target.     |
| `focus()`   | `:Wiremux focus`       | Focus a target.            |
| `close()`   | `:Wiremux close`       | Close a target.            |
| `adopt()`   | `:Wiremux adopt`       | Manage an existing pane.   |
| `history()` | `:Wiremux history`     | Recover a Compose message. |

For motion mappings, see `:help wiremux-howto-send-motion`.

<details>
<summary>Adopt an existing pane</summary>

Run `:Wiremux adopt` to choose an existing pane.
Wiremux adds its metadata without a new pane. Wiremux excludes the current pane.

To assign a name and filter the candidates, use Lua:

```lua
require("wiremux").adopt({
  target = "terminal",
  filter = {
    instances = function(inst)
      return inst.running_command == "zsh"
    end,
  },
})
```

The default adopt picker uses the current tmux session.
A custom filter replaces that default.
See `:help wiremux.adopt()` for filtering and row formatting.

</details>

- Run `:checkhealth wiremux` for setup problems.
- Make sure that Neovim runs inside tmux and that `$TMUX` is set.
- Read `:help wiremux` or the [reference manual](doc/wiremux.txt) for the full API and configuration.

## Credits

[folke/sidekick.nvim](https://github.com/folke/sidekick.nvim) inspired the project and some implementation patterns.

Development included AI-assisted tools. The maintainers reviewed and adjusted all generated code.
