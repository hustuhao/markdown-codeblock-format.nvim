local log = require("turato.log")
local conform = require("conform")

local M = {}

-- Default config for formatters
M.formatters = {
	lua = { "stylua" },
	python = { "black" },
	javascript = { "prettier" },
	sh = { "shfmt" },
	sql = { "sqlfmt" },
	go = { "goimports", "gofmt" },
	rust = { "rustfmt" },
	json = { "jq" },
}

function M.format_with_conform(language, code_content, bufnr, range)
	-- Directly get the formatters for the given language
	local formatters_for_lang = M.formatters[language]

	-- If there are  formatters for this language, return true
	if not formatters_for_lang then
		log.error("no formmatter setup for %s.", language)
		vim.notify(string.format("No formatter setup for %s.", language), vim.log.levels.INFO)
		return code_content
	end

	-- Find the formatters suitable for the current buffer.
	local formatters = vim.tbl_filter(function(info)
		-- Check if the formatter name exists in the list for this language
		for _, formatter in ipairs(formatters_for_lang) do
			if formatter:lower() == info.name:lower() then
				return true
			end
		end
		return false
	end, conform.list_all_formatters())

	if #formatters == 0 then
		log.error("no formmatter setup for %s.Please check conform.nvim config. config.", language)
		return code_content
	end

	-- create a temp buff
	local temp_bufnr = vim.api.nvim_create_buf(false, true)

	-- set text to temp buff
	vim.api.nvim_buf_set_lines(temp_bufnr, 0, -1, false, vim.split(code_content, "\n"))

	local temp_lines = vim.api.nvim_buf_get_lines(temp_bufnr, 0, -1, false)
	log.debug("lines to format:%s", temp_lines)

	-- -- use conform.format to format temp buff
	local opts = {
		bufnr = temp_bufnr,
		-- range = range,
		formatters = vim.tbl_map(function(info)
			return info.name
		end, formatters),
	}

	local success, err = conform.format(opts, function(err, did_edit)
		if err then
			log.error("Formatter error:%s", err)
			return
		end
		if not did_edit then
			log.info("No changes were made.")
			vim.notify("No changes were made.", vim.log.levels.INFO)
			return
		end

		-- Get formatted content.
		local formatted_lines = vim.api.nvim_buf_get_lines(temp_bufnr, 0, -1, false)
		local formatted_code = table.concat(formatted_lines, "\n")

		-- Clean up the temporary buffer
		vim.api.nvim_buf_delete(temp_bufnr, { force = true })

		-- Replace the content of the original buffer
		vim.api.nvim_buf_set_text(
			bufnr,
			range.start[1],
			range.start[2],
			range["end"][1],
			range["end"][2],
			vim.split(formatted_code .. "\n", "\n")
		)
		vim.notify("Formatting success.", vim.log.levels.INFO)
	end)

	if not success then
		log.error("Formatting failed. err:%s", err)
	end
end

-- Format the selected code block
function M.format_selected_code()
	local start_pos = vim.fn.getpos("'<")
	local end_pos = vim.fn.getpos("'>")

	local start_row = start_pos[2] - 1
	local start_col = start_pos[3] - 1
	local end_row = end_pos[2] - 1
	local end_col = end_pos[3] - 1

	-- Get the selected text
	local lines = vim.api.nvim_buf_get_text(0, start_row, start_col, end_row, end_col, {})

	-- Parsing code block language
	local first_line = lines[1]
	local language = first_line:match("^```(.*)")
	language = clean_language_symbol(language)
	if not language then
		log.debug("the code block has no language tag")
		return
	end
	log.debug("find language:%s.", language)

	table.remove(lines, 1) -- Remove first line: ```
	table.remove(lines, #lines) -- Remove the last line ```
	local code_content = table.concat(lines, "\n")

	-- Get buffer number of current text
	local bufnr = vim.api.nvim_get_current_buf()
	log.debug("code content: %s", code_content)

	-- Start to format the selected code block
	local range = {
		start = { start_row + 1, 0 },
		["end"] = { end_row, 0 },
	}
	M.format_with_conform(language, code_content, bufnr, range)
end

function M.setup(opts)
	log.debug("load mf end, opts:", opts)
	opts = opts or {}
	M.setup_formatter(opts.formatters)
	log.debug("load mf start, opts:", opts)
end

function M.setup_formatter(opts)
	log.debug("load mf formatter start")
	if opts.formatters then
		for lang, formatters in pairs(opts.formatters) do
			M.formatters[lang] = formatters
		end
		log.debug("setup formaters:", vim.inspect(opts.formaters))
	end
	log.debug("load mf formatter end")
end

-- Trim leading and trailing whitespace
function clean_language_symbol(lang)
	return lang:match("^%s*(.-)%s*$")
end

return M
