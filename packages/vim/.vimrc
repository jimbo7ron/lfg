" .vimrc -- managed by lfg

syntax on
set number
set background=dark
colorscheme dracula
autocmd FileType python setlocal expandtab shiftwidth=4 tabstop=4 softtabstop=4

" Local overrides
if filereadable(expand("~/.vimrc.local"))
    source ~/.vimrc.local
endif
