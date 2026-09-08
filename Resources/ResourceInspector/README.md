# Resource Inspector

This test application loads these HTML-like and CSS files through the production
CkSlateLayout parser and retained view. Its data is deterministic sample data,
not a scan of project assets.

In a running game or PIE session with a ready Ck local-player input source, enter
`Ck.Tests.ResourceInspector` in the console. The command toggles the first local
player's inspector; the Close button also closes it. Each local-player subsystem
owns its mounted widget and file-polling ticker.

- Use Empty, One, Sample, 1k and 10k to change the collection size. Enter a custom Resource count to choose any size from 0 to 10000; Enter or focus loss commits the value. Counts round to whole numbers and clamp to that interval.
- Loading and Error are deterministic presentation previews. They hide the inventory while retaining its dataset, selection, search, notes, pins and activity. Show resources restores the ready presentation. These previews do not start background jobs or simulate a network request.
- Expand All resources in Categories and select a kind to filter the inventory.
  Search applies within that category; selecting All resources restores the full
  scenario without discarding the search. Scenario buttons preserve the category.
- Search filters the table. Click a column heading to sort, or a row to inspect it.
- Drag the divider to resize the inventory and details panes.
- The session note sits below the details and belongs to this inspector session, not the selected resource. Its draft remains local to the text input until Enter or focus loss commits it. Whitespace is trimmed; notes longer than 80 characters keep the previous committed note and show the authored validation text.
- Lock note uses the shared checkbox to make the session-note editor read-only. Unlock it to resume editing. The setting belongs to this inspector session and survives layout reloads.
- Activity shows the latest 100 successful session changes, newest first. Selection, dataset/category changes, note commits, and pin/remove actions feed the history. Repeating an unchanged action or rejecting invalid input adds no entry. History belongs to the open inspector session and survives authored layout reloads.
- Edit either authored file while the inspector is open. It checks the pair every
  half second. Invalid edits retain the last accepted UI and display a diagnostic;
  correcting the files permits the next reload.

The native host owns lifecycle and input, and the model owns data and actions.
The non-graph layout belongs in these resource files. Missing shared controls
must be implemented in CkSlateLayout rather than replaced by a test-only renderer
or bespoke Slate layout in this app.

This app includes shared tree navigation, forms, tabs, menus and pinned snapshots. The remaining
reference-app sections are still campaign work. Evidence and outstanding
game/package/controller/visual checks are recorded in CkFoundation's
`Source/CkYoga/PROGRESS.md` and `COVERAGE.md`.

The session note is the first implementation use of the shared `text-input` control.
It commits on Enter or focus loss; editing does not mutate the model before that commit.

## Browser reference

Open Workbench.reference.html directly in a browser for the visual reference.
It is standalone and uses deterministic sample data; its JavaScript is not part
of the native renderer. Browser visual verification is pending because automated
preview was denied by the browser tool URL policy. Native translation, component
gallery coverage, and game/package acceptance remain open campaign work.
