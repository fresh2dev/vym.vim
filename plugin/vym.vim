if exists("g:loaded_vym") || &compatible
    finish
endif
let g:loaded_vym = 1

function s:GetNVimVersion()
    redir => s
    silent! version
    redir END
    return matchstr(s, 'NVIM v\zs[^\n]*')
endfunction

function s:GetVymVersion(vym_command)
    silent let l:version = trim(system(a:vym_command." --version"))
    return l:version
endfunction

function! s:CreateEnv()
    let env = {
        \ "os": { "name": "", "open_command": "" },
        \ "vim": {
        \     "type": "vim", "version": v:version, "terminal": v:false,
        \     "settings": {
        \              "shell": &shell,
        \              "shellcmdflag": &shellcmdflag,
        \              "shellredir": &shellredir,
        \          },
        \     },
        \ }

    let os = env.os
    if has("linux")
        let os.name = "linux"
        let os.open_command = "xdg-open"
    endif
    if has("mac")
        let os.name = "mac"
        let os.open_command = "open"
    endif
    if has("win32")
        let os.name = "win32"
        let os.open_command = "start"
    endif

    let vim = env.vim
    if has("nvim")
        let vim.type = "nvim"
        if has("nvim-0.3.0")
            let vim.terminal = v:true
        endif
        let vim.version = s:GetNVimVersion()
    else
        if has("terminal")
            let vim.terminal = v:true
        endif
    endif

    return env
endfunction

function! s:IsCompatible(env)
    return a:env.vim.terminal
endfunction

function! s:CreateConfig(env)
    let l:config = {
        \ "env": a:env,
        \ "settings": {
        \     "vym_command": get(g:, "vym_command", "vym --vym-in-vim"),
        \     "shell_command": get(g:, "vym_shell_command", &shell . " " . &shellcmdflag),
        \     "default_explore_path": get(g:, "vym_default_explore_path", "."),
        \ },
        \ }

    let l:config.vym_exec = l:config.settings.vym_command

    return l:config
endfunction

let s:env = s:CreateEnv()

try
    if !s:IsCompatible(s:env)
        throw "(n)VIM version not compatible due to lack of terminal support."
    endif
    let s:config = s:CreateConfig(s:env)
catch
    echoerr "[Vym.vim] Error: ".v:exception
    finish
endtry

let s:sessions = {}

function! s:OnTerminalExit(session)
    let l:terminal_buffer = a:session.terminal_buffer
    if bufexists(l:terminal_buffer)
        silent execute "bwipeout! ".l:terminal_buffer
    endif
endfunction

function! g:OnTerminalExitNvim(job_id, code, event)
    let l:session = s:sessions[a:job_id]
    call s:OnTerminalExit(l:session)
    unlet s:sessions[a:job_id]
endfunction

function! g:OnTerminalExitVim(job, exit)
    let l:terminal_buffer = ch_getbufnr(a:job, "out")
    let l:session = s:sessions[l:terminal_buffer]
    call s:OnTerminalExit(l:session)
    unlet s:sessions[l:terminal_buffer]
endfunction

function! s:OpenTerminal(command, session) abort
    if has("nvim")
        " do not replace the current buffer
        enew
        let l:job_id = termopen(a:command, {
                    \ "on_exit": "g:OnTerminalExitNvim",
                    \})
        " rename the terminal buffer name to
        " something more readable than the long gibberish
        execute "file ".s:config.settings.vym_command." ".l:job_id
        let a:session.terminal_buffer = bufnr()
        let s:sessions[l:job_id] = a:session
        " for a clean terminal (the TermOpen autocmd does not work when
        " starting nvim with a directory)
        startinsert
        setlocal nonumber norelativenumber signcolumn=no colorcolumn=0
    else
        let l:terminal_buffer = term_start(a:command, {
                    \ "term_name": s:config.settings.vym_command,
                    \ "curwin": 1,
                    \ "exit_cb": "g:OnTerminalExitVim",
                    \ "norestore": 1,
                    \})
        let a:session.terminal_buffer = l:terminal_buffer
        let s:sessions[l:terminal_buffer] = a:session
    endif
endfunction

" opens vym in the given path and in the given (split) window command
function! g:OpenVymInPathInWindow(...) abort
    let l:path = expand(get(a:, 1, s:config.settings.default_explore_path))
    let l:window = get(a:, 2, "")
    let l:session = {}
    let l:command = s:config.settings.shell_command.' "'.s:config.vym_exec." --path '".l:path."'"
    if l:window ==# ""
        let l:session.launched_in_active_window = 1
    else
        execute l:window
        let l:session.launched_in_active_window = 0
    endif
    call s:OpenTerminal(l:command, l:session)
endfunction

" opens vym in the given (split) window command and in the given path
function! g:OpenVymInWindowInPath(...) abort
    let l:window = get(a:, 1, "")
    let l:path = expand(get(a:, 2, s:config.settings.default_explore_path))
    call g:OpenVymInPathInWindow(l:path, l:window)
endfunction

command! -nargs=? -complete=command Vym           call g:OpenVymInPathInWindow(s:config.settings.default_explore_path, <f-args>)
command! -nargs=? -complete=command VymCurrentDir call g:OpenVymInPathInWindow("%:p:h", <f-args>)
command! -nargs=? -complete=command VymWorkingDir call g:OpenVymInPathInWindow(".", <f-args>)
command! -nargs=? -complete=command VymHomeDir    call g:OpenVymInPathInWindow("~", <f-args>)

" To open vym when vim loads a directory
if exists("g:vym_replace_netrw") && g:vym_replace_netrw
    augroup vym_replace_netrw
        autocmd VimEnter * silent! autocmd! FileExplorer
        " order is important for having the path properly resolved, i.e. first
        " expand the path then delete empty buffer created by vim
        autocmd BufEnter * if isdirectory(expand("%")) | call g:OpenVymInPathInWindow(expand("%"), "") | bwipeout! # | endif
    augroup END
    if exists(":Explore") != 2
        command! -nargs=? -complete=dir Explore  call g:OpenVymInWindowInPath("", <f-args>)
    endif
    if exists(":Hexplore") != 2
        command! -nargs=? -complete=dir Hexplore call g:OpenVymInWindowInPath("split", <f-args>)
    endif
    if exists(":Vexplore") != 2
        command! -nargs=? -complete=dir Vexplore call g:OpenVymInWindowInPath("vsplit", <f-args>)
    endif
    if exists(":Texplore") != 2
        command! -nargs=? -complete=dir Texplore call g:OpenVymInWindowInPath("tab split", <f-args>)
    endif
endif
