local M = {}

local cnf = require("auto-save.config")
local callback = require("auto-save.utils.data").do_callback
local colors = require("auto-save.utils.colors")
local echo = require("auto-save.utils.echo")
local autosave_running
local api = vim.api
local g = vim.g
local fn = vim.fn
local cmd = vim.cmd
local o = vim.o
local AUTO_SAVE_COLOR = "MsgArea"
local BLACK = "#000000"
local WHITE = "#ffffff"

api.nvim_create_augroup("AutoSave", {
    clear = true,
})


local global_vars = {}
local last_undo_seq = vim.fn.getreginfo('"').undo_seq

local function check_last_command_undo()
    local current_undo_seq = vim.fn.getreginfo('"').undo_seq
    last_undo_seq = current_undo_seq
    return (current_undo_seq ~= last_undo_seq)
end

local function set_buf_var(buf, name, value)
    if buf == nil then
        global_vars[name] = value
    else
        if api.nvim_buf_is_valid(buf) then
            api.nvim_buf_set_var(buf, "autosave_" .. name, value)
        end
    end
end

local function get_buf_var(buf, name)
    if buf == nil then
        return global_vars[name]
    end
    local success, mod = pcall(api.nvim_buf_get_var, buf, "autosave_" .. name)
    return success and mod or nil
end

local function debounce(lfn, duration)
    local function inner_debounce()
        local buf = api.nvim_get_current_buf()
        if not get_buf_var(buf, "queued") then
            vim.defer_fn(function()
                set_buf_var(buf, "queued", false)
                lfn(buf)
            end, duration)
            set_buf_var(buf, "queued", true)
        end
    end

    return inner_debounce
end

function M.save(buf)
    if check_last_command_undo() then
        api.nvim.echo("Autosave skipped")
        return
    end

    buf = buf or api.nvim_get_current_buf()

    callback("before_asserting_save")

    if cnf.opts.condition(buf) == false then
        return
    end

    if not api.nvim_buf_get_option(buf, "modified") then
        return
    end

    callback("before_saving")

    if g.auto_save_abort == true then
        return
    end

    if cnf.opts.write_all_buffers then
        cmd("silent! wall")
    else
        api.nvim_buf_call(buf, function()
            cmd("silent! write")
        end)
    end

    callback("after_saving")

    api.nvim_echo(
        {
            {
                (
                    type(cnf.opts.execution_message.message) == "function"
                        and cnf.opts.execution_message.message()
                    or cnf.opts.execution_message.message
                ),
                AUTO_SAVE_COLOR,
            },
        },
        true,
        {}
    )
    if cnf.opts.execution_message.cleaning_interval > 0 then
        fn.timer_start(cnf.opts.execution_message.cleaning_interval, function()
            cmd([[echon '']])
        end)
    end
    api.nvim_echo({
        {
            (
                type(cnf.opts.execution_message.message) == "function"
                    and cnf.opts.execution_message.message()
                or cnf.opts.execution_message.message
            ),
            AUTO_SAVE_COLOR,
        },
    }, true, {})
    if cnf.opts.execution_message.cleaning_interval > 0 then
        fn.timer_start(cnf.opts.execution_message.cleaning_interval, function()
            cmd([[echon '']])
        end)
    end
end

local save_func = (
    cnf.opts.debounce_delay > 0 and debounce(M.save, cnf.opts.debounce_delay) or M.save
)

local function perform_save()
    g.auto_save_abort = false
    save_func()
end

function M.on()
    api.nvim_create_autocmd(cnf.opts.trigger_events, {
        callback = function()
            perform_save()
        end,
        pattern = "*",
        group = "AutoSave",
    })

    api.nvim_create_autocmd({ "VimEnter", "ColorScheme", "UIEnter" }, {
        callback = function()
            vim.schedule(function()
                if cnf.opts.execution_message.dim > 0 then
                    MSG_AREA = colors.get_hl("MsgArea")
                    if MSG_AREA.foreground ~= nil then
                        MSG_AREA.background = (
                            MSG_AREA.background or colors.get_hl("Normal")["background"]
                        )
                        local foreground = (
                            o.background == "dark"
                                and colors.darken(
                                    (MSG_AREA.background or BLACK),
                                    cnf.opts.execution_message.dim,
                                    MSG_AREA.foreground or BLACK
                                )
                            or colors.lighten(
                                (MSG_AREA.background or WHITE),
                                cnf.opts.execution_message.dim,
                                MSG_AREA.foreground or WHITE
                            )
                        )

                        colors.highlight("AutoSaveText", { fg = foreground })
                        AUTO_SAVE_COLOR = "AutoSaveText"
                    end
                end
            end)
        end,
        pattern = "*",
        group = "AutoSave",
    })

    callback("enabling")
    autosave_running = true
end

function M.off()
    api.nvim_create_augroup("AutoSave", {
        clear = true,
    })

    callback("disabling")
    autosave_running = false
end

function M.toggle()
    if autosave_running then
        M.off()
        echo("off")
    else
        M.on()
        echo("on")
    end
end

function M.setup(custom_opts)
    cnf:set_options(custom_opts)
end

return M

