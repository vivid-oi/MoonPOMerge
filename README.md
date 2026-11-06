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
Apply checks that the reviewed conflict report still matches and emits a
complete PO on stdout only after validation. Use a new output path for redirection.
The report gives one-based block-start lines for each side. An absent entry
has a null line. Lines refer to the actual input text, including comments.

The portable library exposes `plan_merge`, `MergePlan::report` and
`MergePlan::apply`. Entry identity uses decoded context and msgid, with active
and obsolete entries separated. Translation, plural shape, flags and comments
are compared together, so divergent edits to the same entry require review.
Equality and round trips are semantic. Output normalizes PO formatting.

Version 0.1 supports one UTF-8 language/domain per merge, explicit matching
charset/language/plural headers, blank-line separated entries and the standard
comment classes. Limits are 4 MB per CLI input and 100 plural slots per entry.
Header edits participate in the merge and the resulting catalog is validated.
The caller supplies the common ancestor and same-domain inputs. Git driver
installation, heuristic renames, POT synchronization
and non-UTF-8 conversion are outside this release.

Apache-2.0. The PO codec and validation use
[moongettext 0.1.1](https://github.com/YanFangNie/moongettext), also Apache-2.0.
MoonBit async supplies filesystem and process adapters under Apache-2.0.
The original [Django German admin catalog](https://github.com/django/django/blob/9e7cc2b628fe8fd3895986af9b7fc9525034c1b0/django/contrib/admin/locale/de/LC_MESSAGES/django.po)
is included under the [Django license](examples/DJANGO-LICENSE).
Demo changes and merge tests were authored for this project.
