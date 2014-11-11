if exists("g:loaded_snapshot") || &cp
  finish
endif

let g:loaded_snapshot = '0.1.0' " version number
let s:keepcpo          = &cpo
set cpo&vim

vnoremap <silent> <Plug>SnapshotRegionCreate :<C-U>call snapshot#CreateRegionFromVisual()<CR>
nnoremap <silent> <Plug>SnapshotAdd :<C-U>call snapshot#AddSnapshotFromCursor()<CR>
nnoremap <silent> <Plug>SnapshotMode :<C-U>call snapshot#SnapshotModeFromCursor()<CR>
nnoremap <silent> <Plug>SnapshotRegionCreateOpFunc :<C-U>call snapshot#SaveCursor()<CR>:set opfunc=snapshot#CreateRegionOpFunc<CR>g@
nnoremap <silent> <Plug>SnapshotRegion :<C-U>call snapshot#SnapshotRegionMode()<CR>

if !exists('g:snapshot_no_default_mappings')
  vmap <leader>a <Plug>SnapshotRegionCreate
  nmap <leader>a <Plug>SnapshotRegionCreateOpFunc
  nmap <leader>s <Plug>SnapshotAdd
  nmap <leader>S <Plug>SnapshotMode
  nmap <leader>A <Plug>SnapshotRegion
endif

let &cpo = s:keepcpo
unlet s:keepcpo
