///|
fn decision_catalog(value : String?) -> String {
  let header = "msgid \"\"\nmsgstr \"Language: fr\\nContent-Type: text/plain; charset=UTF-8\\n\"\n"
  match value {
    None => header
    Some(text) => header + "\nmsgid \"Open\"\nmsgstr \"" + text + "\"\n"
  }
}

///|
test "typed decisions cover additions deletions and divergent edits" {
  let values : Array[String?] = [None, Some("A"), Some("B")]
  for base in values {
    for ours in values {
      for theirs in values {
        let plan = @moonpomerge.plan_merge(
          decision_catalog(base),
          decision_catalog(ours),
          decision_catalog(theirs),
        )
        let conflict = ours != theirs && ours != base && theirs != base
        assert_eq(plan.has_conflicts(), conflict)
        if conflict {
          for
            (choice, value) in [
              (@moonpomerge.Base, base),
              (@moonpomerge.Ours, ours),
              (@moonpomerge.Theirs, theirs),
            ] {
            let expected = decision_catalog(value)
            let normalized = @moonpomerge.plan_merge(
              expected, expected, expected,
            ).apply([])
            assert_eq(plan.apply_decisions([choice]), normalized)
          }
        } else {
          let value = if ours == base { theirs } else { ours }
          let expected = decision_catalog(value)
          assert_eq(
            plan.apply_decisions([]),
            @moonpomerge.plan_merge(expected, expected, expected).apply([]),
          )
        }
      }
    }
  }
}

///|
fn plural_catalog(one : String, many : String) -> String {
  let header =
    #|msgid ""
    #|msgstr "Language: fr\nContent-Type: text/plain; charset=UTF-8\nPlural-Forms: nplurals=2; plural=(n > 1);\n"
    #|
    #|# Translator note
    #|#. Extracted note
    #|#: src/inbox.mbt:12
    #|#, fuzzy
    #|msgctxt "inbox"
    #|msgid "message"
    #|msgid_plural "messages"
  header +
  "\nmsgstr[0] \"" +
  one +
  "\"\nmsgstr[1] \"" +
  many +
  "\"\n" +
  "\nmsgctxt \"toolbar\"\nmsgid \"message\"\nmsgstr \"Message\"\n" +
  "\n#~ msgid \"message\"\n#~ msgstr \"Ancien\"\n"
}

///|
test "typed plural translations preserve metadata contexts and obsolete entries" {
  let base = plural_catalog("message", "messages")
  let ours = plural_catalog("courrier", "courriers")
  let theirs = plural_catalog("lettre", "lettres")
  let plan = @moonpomerge.plan_merge(base, ours, theirs)
  assert_true(
    (Some(plan.apply_decisions([@moonpomerge.Translations(["incomplete"])])) catch {
      _ => None
    })
    is None,
  )
  let translations = ["nouveau", "nouveaux"]
  let output = plan.apply_decisions([@moonpomerge.Translations(translations)])
  assert_eq(output, plan.apply(["json:[\"nouveau\",\"nouveaux\"]"]))
  let expected = plural_catalog("nouveau", "nouveaux")
  assert_eq(
    output,
    @moonpomerge.plan_merge(expected, expected, expected).apply([]),
  )
  translations[0] = "later mutation"
  assert_eq(plan.apply_decisions([@moonpomerge.Ours]), plan.apply(["ours"]))
  assert_eq(plan.apply_decisions([@moonpomerge.Theirs]), plan.apply(["theirs"]))
  assert_eq(plan.apply_decisions([@moonpomerge.Base]), plan.apply(["base"]))
  assert_eq(
    @moonpomerge.plan_merge(output, output, output).apply_decisions([]),
    output,
  )
}
