# MoonPOMerge

MoonBit library and CLI for semantic three-way merges of GNU gettext PO catalogs.
Use a common ancestor and two branches to merge disjoint changes and review
divergent changes by message, including delete versus edit.

```sh
moon update
moon run checks/demo.mbtx -- moon wasm
```

The demo uses the pinned Django 5.2 German admin catalog, creates two competing
edits in a temporary directory, verifies refusal before resolution, and checks
every entry after applying a choice. Pass `msgfmt` as the third argument to run
GNU gettext's independent output validation.

```sh
moon run --target wasm cmd/main -- plan base.po ours.po theirs.po > review.json
moon run --target wasm cmd/main -- apply base.po ours.po theirs.po review.json theirs > merged.po
```

Supply one choice (`base`, `ours` or `theirs`) per reported conflict in ID order.
For an entry present in ours, `'json:["New translation"]'` supplies a custom
translation. Provide every slot in plural order. The decision retains the ours
entry's identity, comments and flags, and is unavailable for the catalog header.
For reviews with many decisions, use `apply-file BASE OURS THEIRS REVIEW.json DECISIONS.json`.
The decisions file is a JSON array in conflict ID order, for example
`["theirs", ["Revised translation"]]`. The inner array holds all translation slots.
Apply checks that the reviewed report still matches and emits a
complete PO on stdout only after validation. Use a new output path for redirection.
For file delivery, run `apply-to BASE OURS THEIRS REVIEW.json DECISIONS.json OUTPUT.po`.
It validates the review and all choices before writing a sibling temporary file,
syncs and closes it, then publishes it with replacement disabled. An existing
destination, including any input path, is refused. Success produces no stdout.
Failed publication cleans up its temporary file. Filesystem errors exit 2.
The Django demo checks successful publication, existing destinations, stale
reviews and invalid decisions. This provides process-level publication safety.
Directory crash durability and hostile concurrent filesystem changes are outside
the current contract.
Version 2 binds decisions to SHA-256 hashes of all three decoded input texts,
including changes outside conflicts. Regenerate earlier review files.
The report gives one-based block-start lines for each side. An absent entry
has a null line. Lines refer to the actual input text, including comments.
The summary counts unchanged entries, single-branch edits, identical edits
from both branches, and conflicts. The header counts as an entry. Automatic
removals are a subset of automatic changes. Regenerate saved reviews to include
the summary before applying them.

For CI, run `check BASE OURS THEIRS`. It prints the review JSON and exits 0 for
a validated clean merge, 1 for conflicts, or 2 for invalid input or I/O errors.
The command does not write the merge result.

## Git merge driver

Build the native CLI with `moon build --target native --release`. Configure
the driver with the absolute path to the resulting CLI binary:

```ini
[merge "moonpomerge"]
    name = Semantic gettext catalog merge
    driver = "/absolute/path/to/moonpomerge" git-driver %O %A %B
```

Set `*.po merge=moonpomerge` in the consuming repository's `.gitattributes`.
The driver replaces Git's ours file only after a clean merge and validation.
It exits 1 and prints the conflict report to stderr for a divergent entry,
leaving the ours file intact. Read the three unmerged Git index stages and
use `plan` / `apply` to resolve. Invalid input and I/O failures exit 2.

Run `moon run checks/git.mbtx -- moon wasm` to exercise actual Git integration.
The script creates a disposable repository using the Django catalog, configures
the driver, merges disjoint branch edits, verifies a divergent merge leaves
ours intact and keeps all three index stages, then exports those stages for
review and applies the decision with `apply-to`. It verifies every resulting
entry and completes the merge commit. Temporary paths and the PO filename
include spaces. All fixture commits remain in that temporary repository.
Pass `native` instead of `wasm` to exercise the native CLI. CI runs this workflow
with the native CLI on Linux, macOS and Windows, plus Wasm on Linux.

The portable library exposes `plan_merge`, `MergePlan::report`,
`MergePlan::apply_decisions` and the string-based `MergePlan::apply`.
Typed callers use `Base`, `Ours`, `Theirs` or `Translations(Array[String])`
in report order. Translation arrays must contain every plural slot. The plan
remains reusable after rejected decisions. For example, after reviewing a plan
with one conflict, `plan.apply_decisions([@merge.Theirs])` selects that entry
from theirs, including deletion when that side is absent.
Entry identity uses decoded context and msgid, with active
and obsolete entries separated. Translation, plural shape, flags and comments
are compared together, so divergent edits to the same entry require review.
Equality and round trips are semantic. Output normalizes PO formatting.

Version 0.1 supports one UTF-8 language/domain per merge, explicit matching
charset/language/plural headers, blank-line separated entries and the standard
comment classes. Limits are 4 MB per CLI input and 100 plural slots per entry.
Each physical directive or continuation line must carry a single quoted string.
An unescaped interior quote or text after a closing quote is rejected.
Header edits participate in the merge and the resulting catalog is validated.
The caller supplies the common ancestor and same-domain inputs. Heuristic renames, POT synchronization
and non-UTF-8 conversion are outside this release.

Apache-2.0. The PO codec and validation use
[moongettext 0.1.1](https://github.com/YanFangNie/moongettext), also Apache-2.0.
MoonBit async supplies filesystem and process adapters under Apache-2.0.
The driver's temporary-file replacement follows the Apache-2.0 publication
pattern in [FontPin](https://github.com/vivid-oi/FontPin/blob/fcab696f80bd5a259cce7d19e01e50b79616ef04/src/command/files.mbt),
which credits MBTRelMask.
SHA-256 uses Apache-2.0 `moonbitlang/x/crypto`.
The original [Django German admin catalog](https://github.com/django/django/blob/9e7cc2b628fe8fd3895986af9b7fc9525034c1b0/django/contrib/admin/locale/de/LC_MESSAGES/django.po)
is included under the [Django license](examples/DJANGO-LICENSE).
Demo changes and merge tests were authored for this project.
