
-- ~/.config/nvim/lua/custom/methodmove.lua
-- Move C# methods (incl. attributes/doc comments/line comments + optional blank line)
-- using Treesitter nodes + a small "header" scan.

local M = {}

local function method_node_at_cursor()
  local node = vim.treesitter.get_node()
  while node do
    local t = node:type()
    if t == "method_declaration" or t == "constructor_declaration" or t == "local_function_statement" then
      return node
    end
    node = node:parent()
  end
  return nil
end

local function method_range_inclusive(node)
  local sr, _, er, ec = node:range() -- 0-based; end is exclusive
  local start_line = sr + 1

  local end_line = er + 1
  if ec == 0 then
    end_line = er
    if end_line < start_line then end_line = start_line end
  end

  return start_line, end_line
end

local function is_blank(s) return s:match("^%s*$") ~= nil end
local function is_line_comment(s) return s:match("^%s*//") ~= nil end
local function is_xml_doc(s) return s:match("^%s*///") ~= nil end
local function is_attr_start(s) return s:match("^%s*%[") ~= nil end

local function compute_method_top_with_header(start_line)
  local top = start_line
  local blank_used = false
  local in_block_comment = false
  local in_attr = false

  local function line(i) return vim.fn.getline(i) end

  for i = start_line - 1, 1, -1 do
    local s = line(i)

    -- Hard stop: don't ever cross a previous method end-brace
    if not in_block_comment and not in_attr and s:match("^%s*}%s*$") then
      break
    end

    local consumed = false

    if in_block_comment then
      top = i
      consumed = true
      if s:find("/%*") then
        in_block_comment = false
      end
    elseif in_attr then
      top = i
      consumed = true
      if s:find("%[") then
        in_attr = false
      end
    elseif s:find("%*/") then
      -- Block comment (walking upwards): if we hit */, include and keep going until /*
      top = i
      consumed = true
      in_block_comment = true
    elseif s:find("%]") then
      -- Attributes: if we see a ']' line, assume we're inside an attribute block
      top = i
      consumed = true
      in_attr = true
    elseif is_attr_start(s) then
      top = i
      consumed = true
      if not s:find("%]") then
        in_attr = true
      end
    elseif is_xml_doc(s) or is_line_comment(s) then
      top = i
      consumed = true
    elseif is_blank(s) then
      if blank_used then
        break
      end
      blank_used = true
      top = i
      consumed = true
    end

    if not consumed then
      -- Anything else is code: stop
      break
    end
  end

  return top
end


local function get_lines(top, bottom)
  return vim.api.nvim_buf_get_lines(0, top - 1, bottom, false) -- bottom is exclusive in API; we pass inclusive
end

local function set_lines(at_line, lines)
  vim.api.nvim_buf_set_lines(0, at_line - 1, at_line - 1, false, lines)
end

local function delete_lines(top, bottom)
  vim.api.nvim_buf_set_lines(0, top - 1, bottom, false, {})
end

local function resolve_method_node_at_line(line)
  local buf = 0
  local text = vim.fn.getline(line)
  if not text:match("%S") then return nil end
  local col = (text:find("%S") or 1) - 1

  local node = vim.treesitter.get_node({ bufnr = buf, pos = { line - 1, col } })
  while node do
    local t = node:type()
    if t == "method_declaration" or t == "constructor_declaration" or t == "local_function_statement" then
      return node
    end
    node = node:parent()
  end
  return nil
end

local function find_next_method_start_line(from_line)
  local total = vim.api.nvim_buf_line_count(0)
  for l = from_line, total do
    local n = resolve_method_node_at_line(l)
    if n then
      local sr = n:range()
      return sr + 1
    end
  end
  return nil
end

local function find_prev_method_start_line(from_line)
  for l = from_line, 1, -1 do
    local n = resolve_method_node_at_line(l)
    if n then
      local sr = n:range()
      return sr + 1
    end
  end
  return nil
end

local function method_end_line_inclusive_from_start(start_line)
  local node = resolve_method_node_at_line(start_line)
  if not node then return nil end
  local _, end_line = method_range_inclusive(node)
  return end_line
end

local function yank_method_with_header()
  local node = method_node_at_cursor()
  if not node then
    vim.notify("No method/constructor/local function under cursor", vim.log.levels.WARN)
    return
  end

  local start_line, end_line = method_range_inclusive(node)
  local top = compute_method_top_with_header(start_line)
  vim.cmd(string.format("%d,%dy", top, end_line))
end

local function delete_method_with_header()
  local node = method_node_at_cursor()
  if not node then
    vim.notify("No method/constructor/local function under cursor", vim.log.levels.WARN)
    return
  end

  local start_line, end_line = method_range_inclusive(node)
  local top = compute_method_top_with_header(start_line)
  vim.cmd(string.format("%d,%dd", top, end_line))
end

local function move_method(direction)
  local node = method_node_at_cursor()
  if not node then
    vim.notify("No method/constructor/local function under cursor", vim.log.levels.WARN)
    return
  end

  local start_line, end_line = method_range_inclusive(node)
  local top = compute_method_top_with_header(start_line)
  local chunk = get_lines(top, end_line)

  if direction == "down" then
    local next_start = find_next_method_start_line(end_line + 1)
    if not next_start then
      vim.notify("No next method found", vim.log.levels.INFO)
      return
    end

    local next_top = compute_method_top_with_header(next_start)
    local next_end = method_end_line_inclusive_from_start(next_start)
    if not next_end then
      vim.notify("Could not resolve next method end", vim.log.levels.WARN)
      return
    end
    if next_end < next_top then next_end = next_top end

    -- Delete current block first
    delete_lines(top, end_line)

    -- After deletion, everything below shifted up
    local removed = end_line - top + 1
    local insert_at = (next_end - removed) + 1 -- after next block
    set_lines(insert_at, chunk)
    vim.api.nvim_win_set_cursor(0, { insert_at, 0 })
    return
  end

  if direction == "up" then
    local prev_start = find_prev_method_start_line(top - 1)
    if not prev_start then
      vim.notify("No previous method found", vim.log.levels.INFO)
      return
    end

    local prev_top = compute_method_top_with_header(prev_start)

    -- Delete current block first
    delete_lines(top, end_line)

    -- Insert before previous block top
    set_lines(prev_top, chunk)
    vim.api.nvim_win_set_cursor(0, { prev_top, 0 })
    return
  end
end

function M.setup(opts)
  opts = opts or {}
  local keymaps = opts.keymaps or {
    delete = "<leader>dm",
    yank = "<leader>ym",
    move_down = "<leader>mj",
    move_up = "<leader>mk",
  }

  vim.keymap.set("n", keymaps.delete, delete_method_with_header, { desc = "Delete method + header (attrs/comments)" })
  vim.keymap.set("n", keymaps.yank, yank_method_with_header, { desc = "Yank method + header (attrs/comments)" })
  vim.keymap.set("n", keymaps.move_down, function() move_method("down") end, { desc = "Move method down" })
  vim.keymap.set("n", keymaps.move_up, function() move_method("up") end, { desc = "Move method up" })
end

return M
