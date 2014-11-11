" vim: foldmethod=marker

" Echo, prompt and throw helpers {{{1
function! snapshot#Echo(msg, ...)
  redraw
  let header = "| Snapshot |"
  try
    call snapshot#CreateHeaderHl()
    echohl SnapshotHeader
    execute "echo '" . header . " '"
    if exists('a:1')
      execute "echohl " . a:1
    endif
    execute "echon '" . a:msg . "'"
  finally
    echohl None
  endtry
  " redraw to avoid multiple lines of messages
  redraw
endfunction

function! snapshot#CreateHeaderHl()
  if !hlID('SnapshotHeader')
    let title_id = hlID('Title')
    let fg = synIDattr(title_id, 'fg')
    execute "hi! SnapshotHeader guifg=" . fg . " gui=bold"
  endif
endfunction

function! snapshot#Prompt(msg)
  call snapshot#Echo(a:msg, 'Question')
  let input = getchar()
  if input =~ '\v^\d+$'
    let input = nr2char(input)
  endif
  if input !~? '[yn]'
    return snapshot#Prompt(a:msg)
  endif
  return input =~? 'y' ? 1 : 0
endfunction

function! snapshot#Message(msg)
  call snapshot#Echo(a:msg, 'None')
endfunction

function! snapshot#Warning(msg)
  call snapshot#Echo(a:msg, 'WarningMsg')
endfunction

function! snapshot#MessageRegion(msg)
  call snapshot#Echo(a:msg, 'None')
endfunction

function! snapshot#WarningRegion(msg)
  call snapshot#Echo(a:msg, 'WarningMsg')
endfunction

function! snapshot#Throw(msg)
  call snapshot#Echo(a:msg, 'ErrorMsg')
  throw "SnapshotError"
endfunction

"}}}1

" Snapshot Region object and functions {{{1
function! snapshot#SnapshotRegionNew(args)
  let newRegion = {}
  let defaults = {
        \ 'start': 0,
        \ 'end': 0,
        \ 'snapshots': [],
        \ }
  let settings = extend(defaults, a:args, 'force')
  for key in keys(settings)
    let newRegion[key] = settings[key]
  endfor
  let newRegion.old_start = newRegion.start
  let newRegion.old_end = newRegion.end
  return newRegion
endfunction

function! snapshot#RegionAddSnapshot(region, snapshot)
  call add(a:region.snapshots, a:snapshot)
endfunction

function! snapshot#RegionDeleteSnapshot(region, index)
  call remove(a:region.snapshots, a:index)
endfunction

function! snapshot#RegionSetStart(region, start)
  let a:region.start = a:start
endfunction

function! snapshot#RegionSetEnd(region, end)
  let a:region.end = a:end
endfunction

"}}}1

" Creating, adding and removing regions {{{1
function! snapshot#AddRegion(region)
  if !exists('b:Snapshot_regions')
    let b:Snapshot_regions = []
  endif
  call add(b:Snapshot_regions, a:region)
endfunction

function! snapshot#DeleteRegion(region)
  if !exists('b:Snapshot_regions')
    call snapshot#Throw("No Snapshot regions exist")
  endif
  let index = index(b:Snapshot_regions, a:region)
  if index >= 0
    call remove(b:Snapshot_regions, index)
  else
    call snapshot#Throw("Region is not in buffer")
  endif
endfunction

function! snapshot#CreateRegion(start, end)
  call snapshot#CheckRegionConflict(a:start, a:end)
  let args = {}
  let args.start = a:start
  let args.end = a:end
  let newRegion = snapshot#SnapshotRegionNew(args)
  call snapshot#AddRegion(newRegion)
  call snapshot#AddSnapshotFromRegion(newRegion)
endfunction

function! snapshot#CheckRegionConflict(start, end)
  call snapshot#UpdateMarks()
  if exists('b:Snapshot_regions')
    for region in b:Snapshot_regions
      if 0                 " g:snapshot_allow_nested
        if region.start == a:start && region.end == a:end
          " region start and end match
          call snapshot#Throw("Region already exists")
        endif
      elseif (a:start >= region.start && a:start <= region.end)
            \ || (a:end >= region.start && a:end <= region.end)
        " start or end is within region
        call snapshot#Throw("Region conflict")
      elseif (region.start >= a:start && region.end <= a:end)
            \ || (region.start >= a:end && region.end <= a:end)
        " region is within start and end
        call snapshot#Throw("Region conflict")
      endif
    endfor
  endif
endfunction

function! snapshot#CreateRegionFromVisual()
  try
    call snapshot#SaveCursor()
    normal! `<
    let start = line('.')
    normal! `>
    let end = line('.')
    call snapshot#CreateRegion(start, end)
  catch /SnapshotError/
    " do nothing
  endtry
endfunction

function! snapshot#SelectRegion(line)
  call snapshot#UpdateMarks()
  if !exists('b:Snapshot_regions')
    return -1
  endif
  let candidates = []
  for region in b:Snapshot_regions
    if (region.start <= a:line && region.end >= a:line)
      call add(candidates, region)
    endif
  endfor
  if len(candidates) == 0
    return -1
  elseif len(candidates) == 1
    return candidates[0]
  else
    return snapshot#ResolveConflict(candidates)
  endif
endfunction

function! snapshot#SelectRegionFromCursor()
  return snapshot#SelectRegion(b:Snapshot_cursor[0])
endfunction

function! snapshot#CreateRegionOpFunc(type, ...)
  try
    call snapshot#UpdateMarks()
    normal! `[
    let start = getpos('.')[1]
    normal! `]
    let end = getpos('.')[1]
    call snapshot#CreateRegion(start, end)
    call cursor(b:Snapshot_cursor[0], b:Snapshot_cursor[1])
  catch /SnapshotError/
    " do nothing
  endtry
endfunction

function! snapshot#CheckRegion(region)
  if string(a:region) == -1
    call snapshot#Throw("Snapshot region not found")
  endif
  if a:region.start == -1 || a:region.end == -1
    if !snapshot#RepairRegionMarks(a:region)
      call snapshot#Throw("Region marks could not be restored")
    endif
  endif
endfunction

"}}}1

" Creating, adding and removing snapshots {{{1
function! snapshot#GetContents(start, end)
  return getline(a:start, a:end)
endfunction

function! snapshot#CreateSnapshot(start, end)
  let contents = snapshot#GetContents(a:start, a:end)
  " line offset = start - lnum
  let line = b:Snapshot_cursor[0] - a:start
  let col = b:Snapshot_cursor[1]
  return {
        \ 'contents': contents,
        \ 'line': line,
        \ 'col': col,
        \ }
endfunction

function! snapshot#CreateSnapshotFromCursor()
  let region = snapshot#SelectRegionFromCursor()
  return snapshot#CreateSnapshotFromRegion(region)
endfunction

function! snapshot#CreateSnapshotFromRegion(region)
  call snapshot#CheckRegion(a:region)
  return snapshot#CreateSnapshot(a:region.start, a:region.end)
endfunction

function! snapshot#AddSnapshotFromCursor()
  try
    call snapshot#SaveCursor()
    call snapshot#UpdateMarks()
    let region = snapshot#SelectRegionFromCursor()
    return snapshot#AddSnapshotFromRegion(region)
  catch /SnapshotError/
    " do nothing
  endtry
endfunction

function! snapshot#AddSnapshotFromRegion(region)
  call snapshot#CheckRegion(a:region)
  let snapshot = snapshot#CreateSnapshot(a:region.start, a:region.end)
  call snapshot#RegionAddSnapshot(a:region, snapshot)
  call snapshot#Message("Snapshot created")
endfunction

" }}}1

" Snapshot Mode {{{1
function! snapshot#SnapshotModeFromRegion(region)
  let region = a:region
  call snapshot#CheckRegion(region)
  if len(region.snapshots) == 0
    call snapshot#Throw("Region has no snapshots")
  endif
  call snapshot#SaveCursor()
  let current_state = snapshot#CreateSnapshotFromRegion(region)
  let current = len(region.snapshots)
  if 0         " g:snapshot_auto_revert
    let current = snapshot#HandleTab(region, current, -1, current_state)
  else
    call snapshot#HighlightRegion(region)
    call snapshot#Message("Current state")
  endif
  " we have to save and restore the value of region.end
  " as the current undostate is not stable
  " there can be additional changes changing the start/end
  " hence we cannot call UpdateMarks() has this will
  " set the snapshot_undostate to the current one
  " this is solved by maintaing the old undostate
  " and restoring end to the old state and letting
  " a future call to UpdateMarks() update it
  let old_end = region.end
  let feed_keys = 0
  let exit_msg = "Exited"
  try
    while 1
      let input = getchar()
      if input =~ '\v^\d+$'
        let input = nr2char(input)
      endif
      if input == "\<Tab>"
        let current = snapshot#HandleTab(region, current, -1, current_state)
        continue
      elseif input == "\<S-Tab>"
        let current = snapshot#HandleTab(region, current, 1, current_state)
        continue
      elseif input == "\<Esc>"
        call snapshot#RenderSnapshot(current_state, region.start, region.end)
        break
      elseif input == "\<CR>"
        break
      elseif input =~# "[Dd]"
        if snapshot#Prompt("Delete current snapshot? This cannot be undone. (y|n)")
          call snapshot#RegionDeleteSnapshot(region, current)
          if len(region.snapshots)
            let current = snapshot#HandleTab(region, current + 1, -1, current_state)
            continue
          else
            " Return to current state
            call snapshot#RenderSnapshot(current_state, region.start, region.end)
            let exit_msg .= " - No more snapshots exist"
            break
          endif
        endif
        let current = snapshot#HandleTab(region, current + 1, -1, current_state)
        continue
      else
        let feed_keys = 1
        break
      endif
    endwhile
  finally
    let region.end = old_end
    if exists('b:Snapshot_undojoin')
      unlet b:Snapshot_undojoin
    endif
  endtry
  call snapshot#HighlightClear()
  call snapshot#Message(exit_msg)
  if feed_keys
    call feedkeys(input)
  endif
endfunction

function! snapshot#SnapshotModeFromCursor()
  try
    call snapshot#UpdateMarks()
    let region = snapshot#SelectRegionFromCursor()
    call snapshot#SnapshotModeFromRegion(region)
  catch /SnapshotError/
    " do nothing
  endtry
endfunction

function! snapshot#HandleTab(region, current, inc, current_state)
  let snapshot_nr = snapshot#SelectSnapshot(a:region, a:current, a:inc)
  if snapshot_nr != a:current
    let snapshot = snapshot_nr == len(a:region.snapshots) ? a:current_state
          \ : a:region.snapshots[snapshot_nr]
    call snapshot#RenderSnapshot(snapshot, a:region.start, a:region.end)
    let a:region.end = a:region.start + len(snapshot.contents) - 1
    call snapshot#HighlightRegion(a:region)
    if snapshot_nr == len(a:region.snapshots)
      call snapshot#Message("Current state")
    else
      call snapshot#Message("Snapshot " . (len(a:region.snapshots) - snapshot_nr) . " of " . len(a:region.snapshots))
    endif
  endif
  return snapshot_nr
endfunction

function! snapshot#SelectSnapshot(region, current, inc)
  let current = a:current + a:inc
  if current < 0
    call snapshot#Warning("Snapshot " . len(a:region.snapshots) . " of " . len(a:region.snapshots))
    return 0
  elseif current > len(a:region.snapshots)
    call snapshot#Warning("Current state")
    return len(a:region.snapshots)
  else
    return current
  endif
endfunction

function! snapshot#RenderSnapshot(snapshot, start, end)
  " PRE: UpdateMarks() has already been done

  " We have to nondestructively change the start and end lines
  " since those positions are where the marks are set
  " this is done using C and normal! i

  " attempt to join the undos into one block
  " if unable to undojoin, creates new undoblock
  if exists('b:Snapshot_undojoin')
    try
      undojoin
    catch /^Vim\%((\a\+)\)\=:E790/
      " undojoin not allowed after undo
    endtry
  else
    let b:Snapshot_undojoin = 1
  endif

  " disable indentation since we will use insert mode
  " and indentation might cause the line to change
  let old_indent = snapshot#SaveIndent()

  let contents = a:snapshot.contents

  call snapshot#SaveCursor()
  call cursor(a:start, 1)
  normal! C
  let cmd = "normal! i" . contents[0]
  execute cmd

  " start == end -> there is only one line in the snapshot
  if (a:start != a:end)
    call cursor(a:end, 1)
    normal! C
    let cmd = "normal! i" . contents[-1]
    execute cmd

    " delete all lines in between
    if (a:end - a:start >= 2)
      execute (a:start + 1)","(a:end - 1)"delete _"
    endif

    " append remaining lines
    if (len(contents) >= 3)
      call append(a:start, contents[1:-2])
    endif
  endif
  " we do not need to update a:end since there will be a
  " new undo state and UpdateMarks will update it accordingly
  call cursor(a:start + a:snapshot.line, a:snapshot.col)

  call snapshot#RestoreIndent(old_indent)

  redraw
endfunction

" }}}1

" Snapshot Region Mode {{{1
function! snapshot#SnapshotRegionMode()
  try
    call snapshot#UpdateMarks()
    call snapshot#HighlightClear()
    if exists('b:Snapshot_regions') && len(b:Snapshot_regions) > 0
      let region = snapshot#RegionSelect(b:Snapshot_regions)
      if string(region) == -2
        " Cancelled
        call snapshot#Message("Region mode cancelled")
        return
      elseif string(region) == -3
        call snapshot#Message("No more Snapshot regions exist")
        return
      endif
      call snapshot#SnapshotModeFromRegion(region)
    else
      call snapshot#Throw("No Snapshot regions exist")
    endif
  catch /SnapshotError/
    " do nothing
  endtry
endfunction

function! snapshot#RegionSelect(candidates)
  " we use a shallow copy as the pointer to
  " a:candidates might be b:Snapshot_regions
  let candidates = copy(a:candidates)
  let current = 0
  call snapshot#HighlightRegion(candidates[current])
  call cursor(candidates[current].start, 1)
  call snapshot#RegionSelectMessage(current + 1, len(candidates))
  try
    while 1
      let input = getchar()
      if input =~ '\v^\d+$'
        let input = nr2char(input)
      endif
      if input == "\<Tab>"
        " Tab
        let current = snapshot#HandleRegionTab(candidates, current, 1)
        continue
      elseif input == "\<S-Tab>"
        " S-Tab
        let current = snapshot#HandleRegionTab(candidates, current, -1)
        continue
      elseif input == "\<Esc>"
        return -2
      elseif input == "\<CR>"
        break
      elseif input =~# "[Dd]"
        if snapshot#Prompt("Delete current region? This cannot be undone. (y|n)")
          call snapshot#DeleteRegion(candidates[current])
          call remove(candidates, current)
          if len(candidates)
            let current = snapshot#HandleRegionTab(candidates, current, 0)
            continue
          else
            return -3
          endif
        endif
        let current = snapshot#HandleRegionTab(candidates, current, 0)
        continue
      else
        return -2
      endif
    endwhile
  finally
    call snapshot#HighlightClear()
  endtry
  return candidates[current]
endfunction

function! snapshot#HandleRegionTab(candidates, current, inc)
  let current = a:current + a:inc
  if current < 0
    call snapshot#RegionSelectWarning(1, len(a:candidates))
    return 0
  elseif current >= len(a:candidates)
    let current = len(a:candidates) - 1
    call snapshot#RegionSelectWarning(current + 1, len(a:candidates))
    return current
  endif
  call snapshot#HighlightRegion(a:candidates[current])
  call cursor(a:candidates[current].start, 1)
  call snapshot#RegionSelectMessage(current + 1, len(a:candidates))
  return current
endfunction

function! snapshot#RegionSelectMessage(current, len)
  call snapshot#MessageRegion("Region " . a:current . " of " . a:len)
endfunction

function! snapshot#RegionSelectWarning(current, len)
  call snapshot#WarningRegion("Region " . a:current . " of " . a:len)
endfunction

" }}}1

" Update Marks {{{1
" UpdateMarks() is a sensitive operation
" if the start and ends of the regions are not in sync
" with the undostate then the marks will be out of sync
function! snapshot#UpdateMarks()
  let current_state = undotree()['seq_cur']
  if !exists('b:Snapshot_state')
    " Snapshot_state has not been set
    " -> no region has been created
    " -> use the current state
    let b:Snapshot_state = current_state
    return
  endif
  if current_state == b:Snapshot_state
    return
  endif
  if !exists('b:Snapshot_regions')
    " Snapshot_regions has not been initialised
    return
  endif
  let old_view = winsaveview()
  let mark_a = snapshot#SaveMark('a')
  let mark_b = snapshot#SaveMark('b')
  delmarks a b
  for region in b:Snapshot_regions
    call snapshot#UpdateRegionMarks(region, b:Snapshot_state, current_state)
  endfor
  call snapshot#RestoreMark('a', mark_a)
  call snapshot#RestoreMark('b', mark_b)
  call winrestview(old_view)
  let b:Snapshot_state = current_state
endfunction

function! snapshot#UpdateRegionMarks(region, snapshot_state, current_state)
  let failed = 0
  " undo to old state
  execute "undo " . a:snapshot_state
  " mark start as a
  call cursor(a:region.start, 1)
  normal! ma
  " mark end as b
  call cursor(a:region.end, 1)
  normal! mb
  " redo to current state
  execute "undo " . a:current_state
  " extract marks
  try
    normal! `a
    let a:region.start = line('.')
    let a:region.old_start = a:region.start
  catch /^Vim\%((\a\+)\)\=:E20/
    let a:region.start = -1
    let failed = 1
  endtry
  try
    normal! `b
    let a:region.end = line('.')
    let a:region.old_end = a:region.end
  catch /^Vim\%((\a\+)\)\=:E20/
    let a:region.end = -1
    let failed = 1
  endtry
  delmarks a b
  if failed
    if 0 || !snapshot#RepairRegionMarks(a:region)    " g:snapshot_repair_marks
      call snapshot#Echo("Region marks could not be restored", 'ErrorMsg')
      call snapshot#DeleteRegion(a:region)
    endif
  endif
endfunction

function! snapshot#RepairMarks()
  if !exists('b:Snapshot_regions')
    " Snapshot_regions has not been initialised
    return
  endif
  let old_view = winsaveview()
  for region in b:Snapshot_regions
    call snapshot#RepairRegionMarks(region)
  endfor
  call winrestview(old_view)
endfunction

function! snapshot#RepairRegionMarks(region)
  if len(a:region.snapshots)
    if a:region.start == -1
      let line = getline(a:region.old_start)
      let @a = line
      let @b = a:region.snapshots[-1].contents[0]
      if line == a:region.snapshots[-1].contents[0]
        let a:region.start = a:region.old_start
      else
        return 0
      endif
    endif
    if a:region.end == -1
      let line = getline(a:region.old_start)
      if line == a:region.snapshots[-1].contents[-1]
        let a:region.end = a:region.old_end
      else
        return 0
      endif
    endif
    return 1
  else
    " No snapshots to help restore marks
    return 0
  endif
endfunction

function! snapshot#ResolveNested(candidates)
  let nested = a:candidates[0]
  let fail = 0
  for region in a:candidates[1:-1]
    if nested.start >= region.start && nested.end <= region.end
      " is nested region
      continue
    elseif nested.start <= region.start && nested.end >= region.end
      " region is nested
      let nested = region
      continue
    else
      let fail = 1
      break
    endif
  endfor
  if fail
    return [0, 0]
  else
    return [1, nested]
  endif
endfunction

"}}}1

" Highlighting and dimming {{{1
function! snapshot#HighlightRegion(region)
  call snapshot#HighlightClear()
  call snapshot#HighlightCreate()
  if !exists('b:Snapshot_matchids')
    let b:Snapshot_matchids = []
  endif
  if a:region.start != -1 && a:region.end != -1
    call add(b:Snapshot_matchids, matchadd('SnapshotDim', '\%<' . a:region.start . 'l'))
    call add(b:Snapshot_matchids, matchadd('SnapshotDim', '\%>' . a:region.end . 'l'))
  endif
endfunction

function! snapshot#HighlightClear()
  if exists('b:Snapshot_matchids')
    while !empty(b:Snapshot_matchids)
      silent! call matchdelete(remove(b:Snapshot_matchids, -1))
    endwhile
  endif
endfunction

function! snapshot#HighlightCreate()
  if !hlID('SnapshotDim')
    execute 'hi SnapshotDim guifg=' . snapshot#GetDimColor()
  endif
endfunction

function! snapshot#GetDimColor()
  let normal_id = hlID('Normal')
  let fg = snapshot#Hex2rgb(synIDattr(normal_id, 'fg'))
  let bg = snapshot#Hex2rgb(synIDattr(normal_id, 'bg'))
  let coeff = 0.8
  let dim_rgb = [
        \ bg[0] * coeff + fg[0] * (1 - coeff),
        \ bg[1] * coeff + fg[1] * (1 - coeff),
        \ bg[2] * coeff + fg[2] * (1 - coeff)]
  return '#'.join(map(dim_rgb, 'printf("%x", float2nr(v:val))'), '')
endfunction

function! snapshot#Hex2rgb(str)
  let str = substitute(a:str, '^#', '', '')
  return [eval('0x'.str[0:1]), eval('0x'.str[2:3]), eval('0x'.str[4:5])]
endfunction

"}}}1

" Helpers {{{1
function! snapshot#SaveCursor()
  let line = getpos('.')[1]
  let col = getpos('.')[2]
  let b:Snapshot_cursor = [line, col]
endfunction

function! snapshot#SaveMark(mark)
  try
    execute "normal! `" . a:mark
    return [getpos('.')[1], getpos('.')[2]]
  catch /^Vim\%((\a\+)\)\=:E20/
    return [-1, -1]
  endtry
endfunction

function! snapshot#RestoreMark(mark, pos)
  if a:pos[0] != -1 && a:pos[1] != -1
    call cursor(a:pos[0], a:pos[1])
    execute "normal! m" . a:mark
  endif
endfunction

function! snapshot#SaveIndent()
  let old_indent = [&autoindent, &smartindent, &cindent, &shiftwidth, &softtabstop, &expandtab]
  set noautoindent
  set nosmartindent
  set nocindent
  set shiftwidth&vim
  set softtabstop=0
  set expandtab
  return old_indent
endfunction

function! snapshot#RestoreIndent(old_indent)
  execute "set " . (a:old_indent[0] ? "" : "no") . "autoindent"
  execute "set " . (a:old_indent[1] ? "" : "no") . "smartindent"
  execute "set " . (a:old_indent[2] ? "" : "no") . "cindent"
  execute "set shiftwidth=" . a:old_indent[3]
  execute "set softtabstop=" . a:old_indent[4]
  execute "set " . (a:old_indent[5] ? "" : "no") . "expandtab"
endfunction
"}}}1

