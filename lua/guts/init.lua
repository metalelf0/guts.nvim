local M = {}

-- All highlight groups from guts/highlights/ that get applied--
local highlight_modules = { "editor", "fzf_lua", "lsp", "render_markdown", "treesitter" }

-- Theme roles that are background colours — never chroma-boosted.
local bg_roles = { bg = true, bg_alt = true }

-- OKLCH chroma multiplier per variant.
local variant_chroma = {
	base    = 1.00,
	whisper = 1.20,
	scream  = 1.45,
}

function M.dev_reload()
	-- Re-apply whichever variant is currently active.
	local current = vim.g.colors_name or "guts"
	for name, _ in pairs(package.loaded) do
		if name:match("^guts") then
			package.loaded[name] = nil
		end
	end
	vim.cmd("colorscheme " .. current)
end

vim.api.nvim_create_user_command("GutsReload", M.dev_reload, { force = true })

function M.load(variant)
	variant = variant or "base"
	local factor = variant_chroma[variant] or 1.0

	-- Always read from the cached base theme without mutating it, so that
	-- repeated :colorscheme calls don't compound the chroma boost.
	local base_theme = require("guts.theme")
	local theme = {}

	if factor ~= 1.0 then
		local color = require("guts.color")
		for role, value in pairs(base_theme) do
			if not bg_roles[role] and type(value) == "string" then
				theme[role] = color.saturate(value, factor)
			else
				theme[role] = value
			end
		end
	else
		theme = base_theme
	end

	vim.cmd("highlight clear")
	if vim.fn.exists("syntax_on") then
		vim.cmd("syntax reset")
	end

	vim.g.colors_name = variant == "base" and "guts" or ("guts-" .. variant)

	local highlights = {}
	for _, group_name in ipairs(highlight_modules) do
		local group = require("guts.highlights." .. group_name)
		for hl, spec in pairs(group.load(theme)) do
			highlights[hl] = spec
		end
	end
	for group, opts in pairs(highlights) do
		vim.api.nvim_set_hl(0, group, opts)
	end

	require("guts.terminal").load(theme)
end

return M
