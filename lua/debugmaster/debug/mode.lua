---@class dm.debug.mode
local M = {}


local root = nil  ---@type string?
local keymaps = require("debugmaster.debug.keymaps")
local cfg = require('debugmaster.cfg')
local api = vim.api
local augroup = api.nvim_create_augroup("debugmaster", {})
local local_maps = {} ---@type dm.KeySpec[]
local originals = {} ---@type table<integer, table<string, table<string, any>>>

---@param map dm.KeySpec
---@param buf? integer
local function set_keymap(map, buf)
  vim.keymap.set(map.modes or 'n', map.key, map.action, {
    buffer = buf,
    nowait = map.nowait,
    desc = map.desc,
  })
end

for _, group in ipairs(keymaps.groups) do
  for _, map in ipairs(group.mappings) do
    if #map.key == 1 then
      table.insert(local_maps, map)
    elseif cfg.global_mapping then
      set_keymap(map, nil)
    end
  end
end

---@param buf integer
local function save_original_settings(buf)
  if originals[buf] then
    return
  end
  originals[buf] = {}
  local v = {}
  for _, map in ipairs(local_maps) do
    for _, mode in ipairs(map.modes or { "n" }) do
      local origin = vim.fn.maparg(map.key, mode, false, true)
      if next(origin) ~= nil and origin.buffer == 1 then
        v[mode] = v[mode] or {}
        v[mode][map.key] = origin
      end
    end
  end
  originals[buf] = v
end

---@param buf integer
---@param root? string
local function set_keymap_local(buf, root)
  if vim.bo[buf].buftype ~= '' then
    return nil
  end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == '' then
    return nil
  end
  root = root or vim.fs.root(name, '.git')
  if root == nil or vim.fs.relpath(root, name) == nil then
    return nil
  end
  save_original_settings(buf)
  for _, map in ipairs(local_maps) do
    set_keymap(map, buf)
  end
  return root
end

function M.set_keymap_sidepane(buf)
  for _, map in ipairs(keymaps.sidepanel.mappings) do
    set_keymap(map, buf)
  end
end

M.enable = function()
  if root then  -- for now, only active one
    vim.notify('have enabled for ' .. root)
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  root = set_keymap_local(buf, root)
  if root == nil then
    vim.notify('can not find a git repo')
    return
  end
  api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    callback = function(e)
      if root and originals[e.buf] == nil then
        set_keymap_local(e.buf, root)
      end
    end,
  })
  api.nvim_create_autocmd('BufUnload', {
    group = augroup,
    callback = function(e)
      if originals[e.buf] then
        originals[e.buf] = nil
      end
    end
  })
  api.nvim_exec_autocmds("User", { pattern = "DebugModeChanged", data = { enabled = true } })
end

function M.disable()
  if not root then
    return
  end
  root = nil
  api.nvim_clear_autocmds({ group = augroup })
  for buf, v in pairs(originals) do
    if api.nvim_buf_is_valid(buf) and v then
      for _, map in pairs(local_maps) do
        local modes = map.modes or {'n'}
        pcall(vim.keymap.del, modes, map.key, {buf = buf})
        for _, mode in ipairs(modes) do
          if v[mode] and v[mode][map.key] then
            pcall(api.nvim_buf_call, buf, function()
              vim.fn.mapset(mode, false, v[mode][map.key])
            end)
          end
        end
      end
    end
    originals[buf] = nil
  end
  api.nvim_exec_autocmds("User", { pattern = "DebugModeChanged", data = { enabled = false } })
end

function M.toggle()
  (root ~= nil and M.disable or M.enable)()
end

function M.is_active()
  return root ~= nil
end

return M
