if exists("g:loaded_broot") || &compatible
    finish
endif
let g:loaded_broot = 1

function! s:IsCompatible()
    if has("nvim")
        return has("nvim-0.3.0")
    else
        return has("terminal")
    endif
endfunction

if !s:IsCompatible()
    echoerr "[Broot.vim] Error: (n)VIM version not compatible due to lack of terminal support."
    finish
endif

let s:broot_default_conf_path = get(g:, "broot_default_conf_path", expand("~/.config/broot/conf.toml"))
let s:broot_vim_conf_path = fnamemodify(resolve(expand("<sfile>:p")), ":h:h") . "/broot.toml"
let s:broot_conf_paths = s:broot_default_conf_path . ";" . s:broot_vim_conf_path
let s:broot_vim_conf = get(g:, "broot_vim_conf", [
            \ '[[verbs]]',
            \ 'key = "enter"',
            \ 'execution = ":print_path"',
            \ 'apply_to = "file"',
            \ ])
call writefile(s:broot_vim_conf, s:broot_vim_conf_path)
let s:broot_open_commmand = get(g:, "broot_open_commmand", "xdg-open")
let s:broot_external_open_file_extensions = get(g:, "broot_external_open_file_extensions", ["pdf"])
let s:broot_command = get(g:, "broot_command", "broot")
let s:broot_shell_command = get(g:, "broot_shell_command", "sh -c")
let s:broot_redirect_command = get(g:, "broot_redirect_command", ">")
let s:broot_exec = s:broot_command . " --conf '" . s:broot_conf_paths . "'"
let s:broot_default_explore_path = get(g:, "broot_default_explore_path", ".")

" type BrootSession = Record<JobId (nvim) | BufNr (vim), { 
"   out_file: string,
"   terminal_buffer: int,
"   current_buffer: int,
"   alternate_buffer: int,
"   launched_in_active_window: bool
" }>;
let s:sessions = {}

function! s:OnTerminalExit(session)
    let l:out_file = a:session.out_file
    let l:aborted = 1
    try
        if (filereadable(l:out_file))
            for l:file in readfile(l:out_file)
                let l:file = fnamemodify(l:file, ":~:.")
                let l:file_extension = fnamemodify(l:file, ":e")
                if index(s:broot_external_open_file_extensions, l:file_extension) >= 0
                    silent execute "!".s:broot_open_commmand." '".l:file."' 2>/dev/null"
                    redraw!
                else
                    execute "edit " . l:file
                    let l:aborted = 0
                endif
            endfor
            call delete(l:out_file)
        endif
    catch
        echoerr "[Broot.vim] Error: ".v:exception
    finally
        let l:terminal_buffer = a:session.terminal_buffer
        let l:current_buffer = a:session.current_buffer
        let l:alternate_buffer = a:session.alternate_buffer
        let l:launched_in_active_window = a:session.launched_in_active_window
        if l:aborted
            " order is important: first switch to old buffer, *then* update
            " alternate buffer
            if l:launched_in_active_window && bufexists(l:current_buffer)
                silent execute "buffer ".l:current_buffer
            endif
            if bufexists(l:alternate_buffer)
                let @# = l:alternate_buffer
            endif
        else
            if bufexists(l:current_buffer)
                let @# = l:current_buffer
            endif
        endif
        if bufexists(l:terminal_buffer)
            silent execute "bwipeout! ".l:terminal_buffer
        endif
    endtry
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

function! s:OpenTerminal(cmd, session) abort
    if has("nvim")
        " do not replace the current buffer
        enew
        let l:job_id = termopen(a:cmd, {
                    \ "on_exit": "g:OnTerminalExitNvim",
                    \})
        " rename the terminal buffer name to
        " something more readable than the long gibberish
        execute "file ".s:broot_command." ".l:job_id
        let a:session.terminal_buffer = bufnr()
        let s:sessions[l:job_id] = a:session
        " for a clean terminal (the TermOpen autocmd does not work when
        " starting nvim with a directory)
        startinsert
        setlocal nonumber norelativenumber signcolumn=no colorcolumn=0
    else
        let l:terminal_buffer = term_start(a:cmd, {
                    \ "term_name": s:broot_command,
                    \ "curwin": 1,
                    \ "exit_cb": "g:OnTerminalExitVim",
                    \ "norestore": 1,
                    \})
        let a:session.terminal_buffer = l:terminal_buffer
        let s:sessions[l:terminal_buffer] = a:session
    endif
endfunction

" opens broot in the given path and in the given (split) window command
function! g:OpenBrootInPathInWindow(...) abort
    let l:path = expand(get(a:, 1, s:broot_default_explore_path))
    let l:window = get(a:, 2, "")
    let l:session = { "out_file": tempname() }
    let l:broot_exec = s:broot_shell_command.' "'.s:broot_exec." '".l:path."' ".s:broot_redirect_command." ".l:session.out_file.'"'
    if l:window ==# ""
        let l:session.launched_in_active_window = 1
    else
        execute l:window
        let l:session.launched_in_active_window = 0
    endif
    let l:session.current_buffer = bufnr(@%)
    let l:session.alternate_buffer = bufnr(@#)
    " keepalt does not work here apparently
    " (due to function call instead of a command, c.f. :h alternate-file)
    call s:OpenTerminal(l:broot_exec, l:session)
endfunction

" opens broot in the given (split) window command and in the given path
function! g:OpenBrootInWindowInPath(...) abort
    let l:window = get(a:, 1, "")
    let l:path = expand(get(a:, 2, s:broot_default_explore_path))
    call g:OpenBrootInPathInWindow(l:path, l:window)
endfunction

command! -nargs=? -complete=command Broot           call g:OpenBrootInPathInWindow(s:broot_default_explore_path, <f-args>)
command! -nargs=? -complete=command BrootCurrentDir call g:OpenBrootInPathInWindow("%:p:h", <f-args>)
command! -nargs=? -complete=command BrootWorkingDir call g:OpenBrootInPathInWindow(".", <f-args>)
command! -nargs=? -complete=command BrootHomeDir    call g:OpenBrootInPathInWindow("~", <f-args>)

" To open broot when vim loads a directory
if exists("g:broot_replace_netrw") && g:broot_replace_netrw
    augroup broot_replace_netrw
        autocmd VimEnter * silent! autocmd! FileExplorer
        " order is important for having the path properly resolved, i.e. first
        " expand the path then delete empty buffer created by vim
        autocmd BufEnter * if isdirectory(expand("%")) | call g:OpenBrootInPathInWindow(expand("%"), "") | bwipeout! # | endif
    augroup END
    if exists(":Explore") != 2
        command! -nargs=? -complete=dir Explore  call g:OpenBrootInWindowInPath("", <f-args>)
    endif
    if exists(":Hexplore") != 2
        command! -nargs=? -complete=dir Hexplore call g:OpenBrootInWindowInPath("split", <f-args>)
    endif
    if exists(":Vexplore") != 2
        command! -nargs=? -complete=dir Vexplore call g:OpenBrootInWindowInPath("vsplit", <f-args>)
    endif
    if exists(":Texplore") != 2
        command! -nargs=? -complete=dir Texplore call g:OpenBrootInWindowInPath("tab split", <f-args>)
    endif
endif
