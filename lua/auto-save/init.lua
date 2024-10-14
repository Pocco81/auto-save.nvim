local M = {}

--- @class Config
local cnf = require("auto-save.config")
local autocmds = require("auto-save.utils.autocommands")

local api = vim.api
local fn = vim.fn
local cmd = vim.cmd

local logger
local autosave_running = nil

autocmds.create_augroup({ clear = true })

local timers_by_buffer = {}

--- @param buf number
local function cancel_timer(buf)
  local timer = timers_by_buffer[buf]
  if timer ~= nil then
    timer:close()
    timers_by_buffer[buf] = nil

    logger.log(buf, "Timer canceled")
  end
end

--- @param lfn fun(buf: number) The function to debounce
--- @param duration number The debounce duration
--- @return fun(buf: number) debounced The debounced function
local function debounce(lfn, duration)
  local function inner_debounce(buf)
    -- instead of canceling the timer we could check if there is one already running for this buffer and restart it (`:again`)
    cancel_timer(buf)
    local timer = vim.defer_fn(function()
      lfn(buf)
      timers_by_buffer[buf] = nil
    end, duration)
    timers_by_buffer[buf] = timer

    logger.log(buf, "Timer started")
  end
  return inner_debounce
end

--- Determines if the given buffer is modifiable and if the condition from the config yields true for it
--- @param buf number
--- @return boolean
local function should_be_saved(buf)
  if fn.getbufvar(buf, "&modifiable") ~= 1 then
    return false
  end

  if cnf.opts.condition ~= nil then
    return cnf.opts.condition(buf)
  end

  logger.log(buf, "Should save buffer")

  return true
end

--- @param buf number
local function save(buf)
  if not api.nvim_buf_is_loaded(buf) then
    return
  end

  if not api.nvim_buf_get_option(buf, "modified") then
    logger.log(buf, "Abort saving buffer")

    return
  end

  autocmds.exec_autocmd("AutoSaveWritePre", { saved_buffer = buf })

  local noautocmd = cnf.opts.noautocmd and "noautocmd " or ""
  local lockmarks = cnf.opts.lockmarks and "lockmarks " or ""
  if cnf.opts.write_all_buffers then
    cmd(noautocmd .. lockmarks .. "silent! wall")
  else
    api.nvim_buf_call(buf, function()
      cmd(noautocmd .. lockmarks .. "silent! write")
    end)
  end

  autocmds.exec_autocmd("AutoSaveWritePost", { saved_buffer = buf })
  logger.log(buf, "Saved buffer")
end

--- @param buf number
local function immediate_save(buf)
  cancel_timer(buf)
  save(buf)
end

local save_func = nil
--- @param buf number
local function defer_save(buf)
  -- is it really needed to cache this function
  -- TODO: remove?
  if save_func == nil then
    save_func = (cnf.opts.debounce_delay > 0 and debounce(save, cnf.opts.debounce_delay) or save)
  end
  save_func(buf)
end

function M.on()
  local augroup = autocmds.create_augroup({ clear = true })

  local events = cnf.opts.trigger_events
  autocmds.create_autocmd_for_trigger_events(events.immediate_save, {
    callback = function(opts)
      if should_be_saved(opts.buf) then
        immediate_save(opts.buf)
      end
    end,
    group = augroup,
    desc = "Immediately save a buffer",
  })
  autocmds.create_autocmd_for_trigger_events(events.defer_save, {
    callback = function(opts)
      if should_be_saved(opts.buf) then
        defer_save(opts.buf)
      end
    end,
    group = augroup,
    desc = "Save a buffer after the `debounce_delay`",
  })
  autocmds.create_autocmd_for_trigger_events(events.cancel_deferred_save, {
    callback = function(opts)
      if should_be_saved(opts.buf) then
        cancel_timer(opts.buf)
      end
    end,
    group = augroup,
    desc = "Cancel a pending save timer for a buffer",
  })

  autosave_running = true

  autocmds.exec_autocmd("AutoSaveEnable")
end

function M.off()
  autocmds.create_augroup({ clear = true })

  autosave_running = false

  autocmds.exec_autocmd("AutoSaveDisable")
end

function M.toggle()
  if autosave_running then
    M.off()
  else
    M.on()
  end
end

function M.setup(custom_opts)
  cnf:set_options(custom_opts)
  logger = require("auto-save.utils.logging").new(cnf:get_options())

  if autosave_running == nil then
    if cnf.opts.enabled then
      M.on()
    else
      M.off()
    end
  end
end

return M
