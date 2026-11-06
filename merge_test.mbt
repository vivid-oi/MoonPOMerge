///|
fn catalog(first : String, second : String) -> String {
  let header =
    #|msgid ""
    #|msgstr "Language: fr\nContent-Type: text/plain; charset=UTF-8\n"
  header +
  "\n\nmsgid \"Open\"\nmsgstr \"" +
  first +
  "\"\n\nmsgid \"Close\"\nmsgstr \"" +
  second +
  "\"\n"
}

///|
test "disjoint changes merge and round trip deterministically" {
  let base = catalog("Ouvrir", "Fermer")
  let ours = catalog("Ouverture", "Fermer")
  let theirs = catalog("Ouvrir", "Fermeture")
  let result = @moonpomerge.plan_merge(base, ours, theirs).apply([])
  assert_true(result.contains("Ouverture"))
  assert_true(result.contains("Fermeture"))
  assert_eq(@moonpomerge.plan_merge(result, result, result).apply([]), result)
  assert_eq(@moonpomerge.plan_merge(base, theirs, ours).apply([]), result)
}

///|
test "conflict requires explicit choice and the plan remains reusable" {
  let base = catalog("Ouvrir", "Fermer")
  let ours = catalog("Ouverture", "Fermer")
  let theirs = catalog("Ouvrez", "Fermer")
  let plan = @moonpomerge.plan_merge(base, ours, theirs)
  assert_true(plan.report().stringify().contains("Ouverture"))
  assert_true((Some(plan.apply([])) catch { _ => None }) is None)
  assert_true((Some(plan.apply(["arbitrary"])) catch { _ => None }) is None)
  assert_true(plan.apply(["theirs"]).contains("Ouvrez"))
  assert_true(plan.apply(["ours"]).contains("Ouverture"))
}

///|
test "unsupported and malformed data fail before merge" {
  let base = catalog("Ouvrir", "Fermer")
  for
    bad in [
      base + "\n# detached comment\n",
      base + "msgstr \"duplicate\"\n",
      base +
      "\nmsgid \"n\"\nmsgid_plural \"ns\"\nmsgstr[1000000000] \"large\"\n",
      base + "\nmsgid \"Open\"\nmsgstr \"duplicate key\"\n",
    ] {
    assert_true(
      (Some(@moonpomerge.plan_merge(base, bad, base)) catch { _ => None })
      is None,
    )
  }
  assert_true(
    @moonpomerge.plan_merge(base, base, base).apply([]).contains("Ouvrir"),
  )
}

///|
test "delete versus edit preserves evidence and does not attach an old translation to a new key" {
  let base = catalog("Ouvrir", "Fermer")
  let ours = catalog("", "Fermer").split("msgid \"Open\"").to_array()
  let renamed = ours[0].to_owned() + "msgid \"Open now\"" + ours[1].to_owned()
  let theirs = catalog("Ouvrez", "Fermer")
  let plan = @moonpomerge.plan_merge(base, renamed, theirs)
  assert_true(plan.report().stringify().contains("Ouvrez"))
  let output = plan.apply(["ours"])
  assert_true(output.contains("Open now"))
  assert_false(output.contains("Ouvrez"))
}
