snapshot.vim
============
*snapshot.txt* For Vim version 7.4 Last change: 11 November 14

###Installation

Use your favourite Plugin manager (e.g. Vim-Plug, Vundle, Pathogen)

The Github repository can be found at gelguy/snapshot.vim

###Usage                

This plugin lets you create snapshots of regions of code. This allows
you to quickly switch between snapshots of code you have taken.
Suppose you need to do a quick refactoring of your code.

      foo() {
        // long code
      }

You can take a snapshot of the code and then attempt to refactor.

      foo() {
        // Code breaks now
      }

Your code breaks, and you just need to revert the snapshot to restore
your work.

Each buffer can have multiple snapshot regions, with each region
having its own list of snapshots. You can revert to any snapshot or
back to the current state.

**WARNING**: 
Please read the Bugs section before using!

Do not use Snapshot as a saving function as the snapshots can be lost.

Rather, use it for convenience for quick editing.

###Default Mappings
`<leader>a` Create Snapshot Region (defines where the snapshot starts and ends)

`<leader>s` Take snapshot

`<leader>S` View and select snapshots (using `<Tab>` and `<S-Tab>`)

`<leader>A` View and select Region
