local uv = vim.uv or vim.loop
local levels_reverse = {}
for k, v in pairs(vim.log.levels) do
	levels_reverse[v] = k
end

local Log = {}

---@type integer
Log.level = vim.log.levels.WARN

---@return string
Log.get_logfile = function()
	local fs = require("turato.fs")

	local ok, stdpath = pcall(vim.fn.stdpath, "log")
	if not ok then
		stdpath = vim.fn.stdpath("cache")
	end
	assert(type(stdpath) == "string")
	return fs.join(stdpath, "mcf.log")
end

---@param level integer
---@param msg string
---@param ... any[]
---@return string
local function format(level, msg, ...)
	local args = vim.F.pack_len(...)
	for i = 1, args.n do
		local v = args[i]
		if type(v) == "table" then
			args[i] = vim.inspect(v)
		elseif v == nil then
			args[i] = "nil"
		end
	end
	local ok, text = pcall(string.format, msg, vim.F.unpack_len(args))
	local timestr = vim.fn.strftime("%H:%M:%S")

	-- Get the line number and file name from the debug info
	local debug_info = debug.getinfo(3, "Sl") -- 3 levels up to get the caller
	local line_number = debug_info and debug_info.currentline or "unknown"
	local source = debug_info and debug_info.short_src or "unknown"

	-- -- Get the full call stack
	-- local traceback = debug.traceback("", 3) -- Start trace from 3 levels up to exclude logging functions

	if ok then
		local str_level = levels_reverse[level]
		return string.format("%s[%s] %s:%d %s", timestr, str_level, source, line_number, text)
	else
		return string.format(
			"%s[ERROR] error formatting log line: '%s' args %s",
			timestr,
			vim.inspect(msg),
			vim.inspect(args)
		)
	end
end

---@param line string
local function write(line)
	-- This will be replaced during initialization
end

local initialized = false
local function initialize()
	if initialized then
		return
	end
	initialized = true
	local filepath = Log.get_logfile()

	local stat = uv.fs_stat(filepath)
	if stat and stat.size > 10 * 1024 * 1024 then
		local backup = filepath .. ".1"
		uv.fs_unlink(backup)
		uv.fs_rename(filepath, backup)
	end

	local parent = vim.fs.dirname(filepath)
	vim.fn.mkdir(parent, "p")

	local logfile, openerr = io.open(filepath, "a+")
	if not logfile then
		local err_msg = string.format("Failed to open mcf.nvim log file: %s", openerr)
		vim.notify(err_msg, vim.log.levels.ERROR)
	else
		write = function(line)
			logfile:write(line)
			logfile:write("\n")
			logfile:flush()
		end
	end
end

---Override the file handler e.g. for tests
---@param handler fun(line: string)
function Log.set_handler(handler)
	write = handler
	initialized = true
end

function Log.log(level, msg, ...)
	if Log.level <= level then
		initialize()
		local text = format(level, msg, ...)
		write(text)
	end
end

function Log.trace(...)
	Log.log(vim.log.levels.TRACE, ...)
end

function Log.debug(...)
	Log.log(vim.log.levels.DEBUG, ...)
end

function Log.info(...)
	Log.log(vim.log.levels.INFO, ...)
end

function Log.warn(...)
	Log.log(vim.log.levels.WARN, ...)
end

function Log.error(...)
	Log.log(vim.log.levels.ERROR, ...)
end

return Log
