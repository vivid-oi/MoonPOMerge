///|
pub suberror MergeError {
  Invalid(String)
}

///|
priv struct Slot {
  id : Int32
  context : String?
  message : String
  base : @po.PoEntry?
  ours : @po.PoEntry?
  theirs : @po.PoEntry?
}

///|
pub struct MergePlan {
  priv entries : Array[(@po.PoEntry?, Int32?)]
  priv conflicts : Array[Slot]
}

///|
fn read_catalog(source : String, side : String) -> @po.PoFile raise MergeError {
  if source.length() > 4_000_000 {
    raise Invalid(side + ": catalog exceeds input limit")
  }
  check_blocks(source, side)
  let doc = @po.parse_po(source) catch {
    @po.PoSyntax(line~, column~, message~) =>
      raise Invalid("\{side}:\{line}:\{column}: \{message}")
    _ => raise Invalid(side + ": cannot parse PO")
  }
  @po.validate_po_strict(doc) catch {
    @po.Validation(message~) => raise Invalid(side + ": " + message)
    _ => raise Invalid(side + ": invalid PO metadata or entries")
  }
  guard doc.header() is Some(_) else {
    raise Invalid(side + ": missing metadata header")
  }
  guard doc.metadata().get("Content-Type") is Some(content) &&
    content
    .to_lower()
    .split(";")
    .any(part => part.trim().to_owned() == "charset=utf-8") else {
    raise Invalid(side + ": expected explicit UTF-8 charset")
  }
  doc
}

///|
fn check_blocks(source : String, side : String) -> Unit raise MergeError {
  let fields : Map[String, Bool] = Map([])
  let mut occupied = false
  let mut obsolete : Bool? = None
  for number, raw in (source + "\n").split("\n").to_array() {
    let line = raw.trim().to_owned()
    if line.is_empty() {
      if occupied {
        let plural = fields.contains("msgid_plural")
        let count = fields.length() -
          1 -
          (if fields.contains("msgctxt") { 1 } else { 0 }) -
          (if plural { 1 } else { 0 })
        if !fields.contains("msgid") ||
          count < 1 ||
          (!plural && !fields.contains("msgstr")) {
          raise Invalid(
            side +
            ": detached comment or incomplete entry before line " +
            (number + 1).to_string(),
          )
        }
        if plural {
          for i in 0..<count {
            if !fields.contains("msgstr[" + i.to_string() + "]") {
              raise Invalid(
                side + ": plural translation slots must be contiguous",
              )
            }
          }
        }
      }
      occupied = false
      obsolete = None
      fields.clear()
      continue
    }
    occupied = true
    let line = if line.has_prefix("#~ ") { line[3:].to_owned() } else { line }
    if !line.has_prefix("#") {
      let marker = raw.has_prefix("#~ ")
      if obsolete is Some(previous) && previous != marker {
        raise Invalid(side + ": mixed active and obsolete directives")
      }
      obsolete = Some(marker)
    }
    if line.has_prefix("#") {
      if fields.contains("msgid") || line.has_prefix("#~") {
        raise Invalid(
          side +
          ": unsupported comment placement or obsolete syntax at line " +
          (number + 1).to_string(),
        )
      }
    } else if !line.has_prefix("\"") {
      guard line.find(" ") is Some(end) else {
        raise Invalid(side + ": expected directive and quoted value")
      }
      let field = line[:end].to_owned()
      if field.has_prefix("msgstr[") && field.length() > 10 {
        raise Invalid(side + ": plural slot exceeds the supported index range")
      }
      if fields.contains(field) ||
        (field == "msgstr" && fields.contains("msgstr[0]")) ||
        (field == "msgstr[0]" && fields.contains("msgstr")) {
        raise Invalid(
          side +
          ": repeated directive " +
          field +
          " at line " +
          (number + 1).to_string(),
        )
      }
      if field.has_prefix("msgstr[") && field.length() > 9 && field[7] == '0' {
        raise Invalid(side + ": noncanonical plural index")
      }
      fields[field] = true
    }
  }
}

///|
fn index_catalog(
  doc : @po.PoFile,
  side : String,
) -> Map[(String?, String, Bool), @po.PoEntry] raise MergeError {
  let index = Map([])
  for entry in doc.entries {
    let key = (entry.context, entry.msgid, entry.obsolete)
    if index.contains(key) {
      raise Invalid(side + ": duplicate entry " + entry.msgid)
    }
    index[key] = entry
  }
  index
}

///|
/// Build a deterministic plan from three same-language PO catalogs.
pub fn plan_merge(
  base : String,
  ours : String,
  theirs : String,
) -> MergePlan raise MergeError {
  let b = read_catalog(base, "base")
  let o = read_catalog(ours, "ours")
  let t = read_catalog(theirs, "theirs")
  for field in ["Language", "Plural-Forms", "Content-Type"] {
    let value = b.metadata().get(field)
    if o.metadata().get(field) != value || t.metadata().get(field) != value {
      raise Invalid("incompatible catalog metadata: " + field)
    }
  }
  let bi = index_catalog(b, "base")
  let oi = index_catalog(o, "ours")
  let ti = index_catalog(t, "theirs")
  let entries : Array[(@po.PoEntry?, Int32?)] = []
  let conflicts : Array[Slot] = []
  let seen : Map[(String?, String, Bool), Bool] = Map([])
  for index in [bi, oi, ti] {
    for key, _ in index {
      if seen.contains(key) {
        continue
      }
      seen[key] = true
      let bv = bi.get(key)
      let ov = oi.get(key)
      let tv = ti.get(key)
      if ov == tv || tv == bv {
        entries.push((ov, None))
      } else if ov == bv {
        entries.push((tv, None))
      } else {
        let id = conflicts.length()
        let (context, message, _) = key
        conflicts.push({ id, context, message, base: bv, ours: ov, theirs: tv, })
        entries.push((None, Some(id)))
      }
    }
  }
  { entries, conflicts, }
}

///|
fn entry_json(entry : @po.PoEntry?) -> Json {
  match entry {
    None => null
    Some(value) => Json(@po.write_po(@po.PoFile::new([value])))
  }
}

///|
/// Return detached conflict evidence. Each non-null side is a PO entry.
pub fn MergePlan::report(self : MergePlan) -> Json {
  {
    "version": 1,
    "conflicts": Json::array(
      self.conflicts.map(slot => {
        "id": Json(slot.id),
        "context": match slot.context {
          Some(context) => Json(context)
          None => null
        },
        "message": Json(slot.message),
        "base": entry_json(slot.base),
        "ours": entry_json(slot.ours),
        "theirs": entry_json(slot.theirs),
      }),
    ),
  }
}

///|
/// Resolve every conflict in report order and return a complete validated PO.
pub fn MergePlan::apply(
  self : MergePlan,
  choices : Array[String],
) -> String raise MergeError {
  if choices.length() != self.conflicts.length() {
    raise Invalid(
      "provide one base, ours or theirs decision per reported conflict",
    )
  }
  let selected : Array[@po.PoEntry?] = []
  for id, choice in choices {
    let slot = self.conflicts[id]
    selected.push(
      match choice {
        "base" => slot.base
        "ours" => slot.ours
        "theirs" => slot.theirs
        _ => raise Invalid("unknown decision for conflict " + id.to_string())
      },
    )
  }
  let result : Array[@po.PoEntry] = []
  for (entry, conflict) in self.entries {
    let value = match conflict {
      Some(id) => selected[id]
      None => entry
    }
    if value is Some(item) {
      result.push(item)
    }
  }
  let doc = @po.PoFile::new(result)
  let output = @po.write_po(doc)
  let decoded = read_catalog(output, "result")
  if decoded != doc {
    raise Invalid("result cannot round trip without losing catalog data")
  }
  output
}
