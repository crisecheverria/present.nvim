local M = {}

local function create_floating_window(config, enter)
	if enter == nil then
		enter = false
	end

	local buf = vim.api.nvim_create_buf(false, true) -- No file, scratch buffer
	local win = vim.api.nvim_open_win(buf, enter or false, config)

	return { buf = buf, win = win }
end

---@class present.FooterImageConfig
---@field path string: Path to the image (supports `~`)
---@field width? integer: Display width in columns (default 24)
---@field height? integer: Display height in rows (default 8)

local default_config = {
	---@type present.FooterImageConfig|nil
	footer_image = nil,
}

local state = {
	parsed = {},
	current_slide = 1,
	floats = {},
	slide_images = {},
	footer_image_render = nil,
	config = vim.deepcopy(default_config),
}

M.setup = function(opts)
	opts = opts or {}
	state.config = vim.tbl_deep_extend("force", vim.deepcopy(default_config), opts)
end

---@class present.Slides
---@fields slides present.Slide[]: The slides of the file

---@class present.Slide
---@field title string: The title of the slide
---@field body string[]: The body of the slide

--- Takes some lines and parses them
---@param lines string[]: The lines in the buffer
---@return present.Slides
local parse_slides = function(lines)
	local slides = { slides = {} }
	local current_slide = {
		title = "",
		body = {},
	}

	local separator = "^#"

	for _, line in ipairs(lines) do
		-- print(line, "find:", line:find(separator), "|")
		if line:find(separator) then
			if #current_slide.title > 0 then
				table.insert(slides.slides, current_slide)
			end

			current_slide = {
				title = line,
				body = {},
			}
		else
			table.insert(current_slide.body, line)
		end
	end

	table.insert(slides.slides, current_slide)

	return slides
end

local create_window_configurations = function()
	local width = vim.o.columns
	local height = vim.o.lines

	local footer_image_cfg = state.config.footer_image
	local footer_image_width = footer_image_cfg and (footer_image_cfg.width or 24) or 0
	local footer_image_height = footer_image_cfg and (footer_image_cfg.height or 8) or 0
	-- Reserve space above the footer text so slide content never overlaps the watermark
	local footer_image_reserved = footer_image_cfg and (footer_image_height + 1) or 0

	local header_height = 3 -- header + border
	local footer_height = 1 + footer_image_reserved -- footer text + reserved space for footer image
	local body_height = height - header_height - footer_height - 2 -- spacing

	-- Add some margin for better presentation
	local margin_horizontal = math.floor(width * 0.1) -- 10% margin
	local margin_vertical = 2
	local content_width = width - (margin_horizontal * 2)
	local content_height = body_height - (margin_vertical * 2)

	return {
		background = {
			relative = "editor",
			width = width,
			height = height,
			style = "minimal",
			border = "none",
			col = 0,
			row = 0,
			zindex = 1,
		},
		header = {
			relative = "editor",
			width = width,
			height = 1,
			style = "minimal",
			border = "rounded",
			col = 0,
			row = 0,
			zindex = 2,
		},
		body = {
			relative = "editor",
			width = content_width,
			height = content_height,
			style = "minimal",
			border = "none",
			col = margin_horizontal,
			row = header_height + margin_vertical,
			zindex = 2,
		},
		footer = {
			relative = "editor",
			width = width,
			height = 1,
			style = "minimal",
			col = 0,
			row = height - 1,
			zindex = 3,
		},
		footer_image = footer_image_cfg and {
			relative = "editor",
			width = footer_image_width,
			height = footer_image_height,
			style = "minimal",
			border = "none",
			col = math.max(math.floor((width - footer_image_width) / 2), 0),
			row = math.max(height - footer_image_height - 2, 0),
			zindex = 4,
		} or nil,
	}
end

--- Finds markdown image syntax (`![alt](path)`) in a slide body
---@param body string[]: The lines of a slide's body
---@return { row: integer, col: integer, path: string }[]
local find_images_in_body = function(body)
	local images = {}
	for i, line in ipairs(body) do
		local start_idx, _, path = line:find("!%[.-%]%((.-)%)")
		if path then
			table.insert(images, { row = i - 1, col = start_idx - 1, path = path })
		end
	end
	return images
end

--- Resolves an image path from markdown relative to the presentation file
---@param path string: The path as written in the markdown
---@param source_dir string: The directory of the presentation file
---@return string|nil: The absolute path, or nil if unsupported (e.g. remote urls)
local resolve_image_path = function(path, source_dir)
	if path:match("^%a+://") then
		return nil
	end
	if path:sub(1, 1) == "/" then
		return path
	end
	if path:sub(1, 1) == "~" then
		return vim.fn.fnamemodify(path, ":p")
	end
	return vim.fn.fnamemodify(source_dir .. "/" .. path, ":p")
end

local warned_missing_image_setup = false
local warned_missing_footer_image = false

--- Resolves the configured footer/watermark image path (supports `~`, relative to cwd)
---@param path string
---@return string|nil
local resolve_footer_image_path = function(path)
	if not path then
		return nil
	end
	return vim.fn.fnamemodify(vim.fn.expand(path), ":p")
end

local clear_slide_images = function()
	for _, img in ipairs(state.slide_images) do
		pcall(img.clear, img)
	end
	state.slide_images = {}
end

--- Renders any markdown images found in a slide's body using image.nvim, if installed
---@param slide present.Slide
local render_slide_images = function(slide)
	local ok, image_api = pcall(require, "image")
	if not ok then
		return
	end

	for _, found in ipairs(find_images_in_body(slide.body)) do
		local path = resolve_image_path(found.path, state.source_dir)
		if path and vim.fn.filereadable(path) == 1 then
			local render_ok, img = pcall(image_api.from_file, path, {
				window = state.floats.body.win,
				buffer = state.floats.body.buf,
				x = found.col,
				y = found.row,
				with_virtual_padding = true,
			})

			if render_ok and img then
				pcall(img.render, img)
				table.insert(state.slide_images, img)
			elseif not warned_missing_image_setup and tostring(img):find("not setup", 1, true) then
				warned_missing_image_setup = true
				vim.notify(
					"present.nvim: image.nvim is installed but not set up. "
						.. "Call require('image').setup() in your config to enable image rendering in slides.",
					vim.log.levels.WARN
				)
			end
		end
	end
end

--- Renders (or re-renders) the persistent footer/watermark image, if configured.
--- Unlike slide images, this is rendered once and stays up across every slide.
local render_footer_image = function()
	if state.footer_image_render then
		pcall(state.footer_image_render.clear, state.footer_image_render)
		state.footer_image_render = nil
	end

	local cfg = state.config.footer_image
	if not cfg or not state.floats.footer_image then
		return
	end

	local ok, image_api = pcall(require, "image")
	if not ok then
		return
	end

	local path = resolve_footer_image_path(cfg.path)
	if not path or vim.fn.filereadable(path) ~= 1 then
		if not warned_missing_footer_image then
			warned_missing_footer_image = true
			vim.notify("present.nvim: footer_image path not readable: " .. tostring(cfg.path), vim.log.levels.WARN)
		end
		return
	end

	local render_ok, img = pcall(image_api.from_file, path, {
		window = state.floats.footer_image.win,
		buffer = state.floats.footer_image.buf,
		x = 0,
		y = 0,
		width = cfg.width or 24,
		height = cfg.height or 8,
		with_virtual_padding = true,
	})

	if render_ok and img then
		pcall(img.render, img)
		state.footer_image_render = img
	elseif not warned_missing_image_setup and tostring(img):find("not setup", 1, true) then
		warned_missing_image_setup = true
		vim.notify(
			"present.nvim: image.nvim is installed but not set up. "
				.. "Call require('image').setup() in your config to enable image rendering in slides.",
			vim.log.levels.WARN
		)
	end
end

local foreach_float = function(cb)
	for name, float in pairs(state.floats) do
		cb(name, float)
	end
end

local present_keymap = function(mode, key, callback)
	vim.keymap.set(mode, key, callback, {
		buffer = state.floats.body.buf,
	})
end

M.start_presentation = function(opts)
	opts = opts or {}
	opts.bufnr = opts.bufnr or 0

	local lines = vim.api.nvim_buf_get_lines(opts.bufnr, 0, -1, false)
	state.parsed = parse_slides(lines)
	state.current_slide = 1
	state.title = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(opts.bufnr), ":t")
	state.source_dir = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(opts.bufnr), ":h")

	local windows = create_window_configurations()
	state.floats.background = create_floating_window(windows.background)
	state.floats.header = create_floating_window(windows.header)
	state.floats.footer = create_floating_window(windows.footer)
	if windows.footer_image then
		state.floats.footer_image = create_floating_window(windows.footer_image)
	end
	state.floats.body = create_floating_window(windows.body, true)

	foreach_float(function(name, float)
		-- Only set markdown filetype for content windows, not background/footer_image
		if name ~= "background" and name ~= "footer_image" then
			vim.bo[float.buf].filetype = "markdown"
		end

		-- Remove any visual artifacts for the body window
		if name == "body" then
			vim.wo[float.win].number = false
			vim.wo[float.win].relativenumber = false
			vim.wo[float.win].cursorline = false
			vim.wo[float.win].cursorcolumn = false
			vim.wo[float.win].colorcolumn = ""
			vim.wo[float.win].signcolumn = "no"
			vim.wo[float.win].foldcolumn = "0"

			-- Enable treesitter syntax highlighting for the body buffer using native Neovim API
			vim.treesitter.start(float.buf, "markdown")
		end
	end)

	local set_slide_content = function(idx)
		local width = vim.o.columns
		local slide = state.parsed.slides[idx]

		local padding = string.rep(" ", (width - #slide.title) / 2)
		local title = padding .. slide.title
		vim.api.nvim_buf_set_lines(state.floats.header.buf, 0, -1, false, { title })
		vim.api.nvim_buf_set_lines(state.floats.body.buf, 0, -1, false, slide.body)

		local footer = string.format("  %d / %d | %s", state.current_slide, #state.parsed.slides, state.title)
		vim.api.nvim_buf_set_lines(state.floats.footer.buf, 0, -1, false, { footer })

		clear_slide_images()
		render_slide_images(slide)
	end

	present_keymap("n", "n", function()
		state.current_slide = math.min(state.current_slide + 1, #state.parsed.slides)
		set_slide_content(state.current_slide)
	end)

	present_keymap("n", "p", function()
		state.current_slide = math.max(state.current_slide - 1, 1)
		set_slide_content(state.current_slide)
	end)

	present_keymap("n", "q", function()
		vim.api.nvim_win_close(state.floats.body.win, true)
	end)

	local restore = {
		cmdheight = {
			original = vim.o.cmdheight,
			present = 0,
		},
	}

	-- Set the options we want during presentation
	for option, config in pairs(restore) do
		vim.opt[option] = config.present
	end

	vim.api.nvim_create_autocmd("BufLeave", {
		buffer = state.floats.body.buf,
		callback = function()
			-- Reset the values when we are done with the presentation
			for option, config in pairs(restore) do
				vim.opt[option] = config.original
			end

			clear_slide_images()

			if state.footer_image_render then
				pcall(state.footer_image_render.clear, state.footer_image_render)
				state.footer_image_render = nil
			end

			foreach_float(function(_, float)
				pcall(vim.api.nvim_win_close, float.win, true)
			end)
			state.floats.footer_image = nil
		end,
	})

	vim.api.nvim_create_autocmd("VimResized", {
		group = vim.api.nvim_create_augroup("present-resized", {}),
		callback = function()
			if not vim.api.nvim_win_is_valid(state.floats.body.win) or state.floats.body.win == nil then
				return
			end

			local updated = create_window_configurations()
			foreach_float(function(name, _)
				vim.api.nvim_win_set_config(state.floats[name].win, updated[name])
			end)

			-- Re-calculates current slide contents
			set_slide_content(state.current_slide)
			render_footer_image()
		end,
	})

	set_slide_content(state.current_slide)
	render_footer_image()
end

-- M.start_presentation({ bufnr = 213 })

M._parse_slides = parse_slides

return M
