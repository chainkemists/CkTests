# Capability gallery starter

This directory is a copyable starter for an authored CkSlateLayout resource.
`GalleryStarter.ui.html` and `GalleryStarter.ui.css` are a standalone pair;
copy both files together and keep all model names and action names aligned with
the contract below. The resource uses only document-local `<template>` and
`<use>` nodes. It does not import another resource or require a new framework
API.

## Shape

The starter provides a toolbar, filter, keyed table, empty state, selected-row
details pane, and a confirmation dialog. The table is the existing collection
surface with `row-height`; production virtualization remains a runtime concern
of the table adapter and is not proved by this markup.

## Required model contract

Typed bindings are expected to be supplied by the owning view:

- Text: `starter-title`, `starter-status`, `starter-query`,
  `starter-selected-name`, `starter-selected-description`, and
  `starter-confirm-copy`.
- Boolean visibility/state: `starter-empty`, `starter-confirm-open`, and
  `starter-enabled`.
- `starter-records` is the typed table collection. Each record supplies
  `name`, `description`, `color`, and `tooltip` fields.
The collection selection callback `starter-select-record` is an
`FOnCkUiTableSelectionChanged` and receives the selected record key. The filter
change callback `starter-query` is `FOnTextChanged`. Actions are
`starter-refresh`, `starter-clear-filter`, `starter-request-delete`,
`starter-cancel-delete`, and `starter-confirm-delete`. The dialog's
`open-bind` resolves from `FDataBindings.Visibility`, `dismiss` resolves from
`FActions`, and the host must set a nonnegative `SlateUserIndex`.

## Installed shape

The document declares one `main` region with the registered dialog as its root.
The dialog has required `content` and `body` slots. `starter-root` is the
content-slot child that grows to fill the dialog mount. The record-summary
template is used by the table column, so its field bindings are evaluated in a
collection-row scope.

## Validation workflow

From the repository root, run:

```text
python Plugins/CkTests/Resources/CapabilityGallery/validate_gallery.py --standalone Plugins/CkTests/Resources/CapabilityGallery/Templates
```

This checks XML parsing, required gallery page keys only when present, and
duplicate IDs outside template scope. It does not load Slate, bind a model,
measure widgets, exercise virtualization, or prove focus/reload/ownership.
Those require a production-path consumer test and runtime acceptance.
