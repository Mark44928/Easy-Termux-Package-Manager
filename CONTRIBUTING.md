# Contributing to Easy Termux Package Manager

Thanks for improving ETPM. This project is two shell files (`manager.sh`,
`install.sh`) plus docs — size and self-containment are features, not bugs.

## Hard rules

1. **Two-file core stays two files.** No new source files in the repo root;
   room for content lands in `manager.sh` (UI and menu logic) or
   `install.sh` (bootstrap). Text assets (`fonts/`) are the exception.
2. **Bash + gum only.** `gum` is optional at runtime — every gum call must
   degrade gracefully when it is absent (tests cover the fallback paths).
3. **Version bump discipline.** Bumping the version means updating every
   place the name appears: the README badges, both ASCII art lines, the menu
   snapshot, the installer banner in `install.sh`, and the fallback string
   in `manager.sh` — then regenerate the compressed banner blob.
4. **Keep docs in sync.**
   - README menu-map tables must match the `OPTION_*` definitions in
     `manager.sh` (icons are swapped via the `ICONS` setting).
   - New icons: pick a Nerd Fonts v3 glyph, verify the codepoint exists in a
     patched font (all glyphs must exist in `fonts/`), add it to **both**
     branches of `init_icons()` in `manager.sh`.
   - Bash escapes: `$'\uXXXX'` accepts 4 hex digits only; use
     `$'\U000XXXXX'` (8 digits, zero-padded) above U+FFFF, e.g.
     `md-hand_wave` is `$'\U000F1821'`.

## Getting started

1. Fork and clone; run inside a real Termux session on device.
2. Try the UI: `bash manager.sh` — first in bare Termux, then with `gum`
   installed (`pkg install gum`).
3. Run the test suite: `bash tests/run-tests.sh` — fakebin stubs for
   `apt`/`dpkg`/`gum` plus 169 scenario tests. All must pass before a PR.
4. Lint if available: `make lint` (or `shellcheck` on changed files; CI runs
   the test suite).

## Pull requests

- One feature/fix per PR; keep the diff small and localized.
- Menu changes: update the README menu map **and** the menu snapshot in the
  same PR (CI checks them).
- Commit style: one imperative line (`add cleanup option for pip cache`,
  `fix gum fallback in update flow`).

## Reporting issues

Open an issue with: Termux version (`termux-info`), whether `gum` was
installed, the exact menu path taken, and full terminal output.
