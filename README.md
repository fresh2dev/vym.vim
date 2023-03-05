# vym.vim

Run vym in vim!

Note: *Very experimental*

Made possible by [broot.vim](https://github.com/lstwn/broot.vim) and [ranger.vim](https://github.com/francoiscabrol/ranger.vim).

## Install

With `vim-plug`:

```
Plug 'fresh2dev/vym.vim'
```

## Use

- `:Vym`
- `:Vym vsplit`
- `:Vym topleft vsplit`
- `:Vym tab split`

## Configuration

| variable name                           | description                                                                                                 | default value                                                                                |
| --------------------------------------- | ----------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| `g:vym_command`                       | vym launch command                                                                                        | `vym`                                                                                      |
| `g:vym_default_explore_path`          | default path to explore                                                                                     | `.`                                                                                          |
| `g:vym_replace_netrw`                 | set to TRUE (e.g. 1) if you want to replace netrw (see below)                                               | off                                                                                          |

### Hijacking netrw

If you set `let g:vym_replace_netrw = 1` in your `.vimrc`,
netrw will not launch anymore if you open a folder but instead launch vym.

If you _additionally_ set `let g:loaded_netrwPlugin = 1` in your `.vimrc`,
not only will netrw not be loaded anymore _at all_ but also the commands
`:Explore`, `:Texplore`, `:Vexplore` and `:Hexplore` are replaced wth vym alternatives.
