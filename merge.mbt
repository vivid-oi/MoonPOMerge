///|
pub suberror MergeError {
  Invalid(String)
}

///|
priv struct Slot {
  id : Int32
  context : String?
  message : String
  lines : Array[Int32]
  base : @po.PoEntry?
  ours : @po.PoEntry?
  theirs : @po.PoEntry?
}

///|
pub struct MergePlan {
  priv entries : Array[(@po.PoEntry?, Int32?)]
  priv conflicts : Array[Slot]
  priv fingerprints : Array[String]
  priv summary : MergeSummary
}

///|
priv struct MergeSummary {
  mut unchanged : Int32
  mut ours_only : Int32
  mut theirs_only : Int32
  mut converged : Int32
  mut removed : Int32
}

///|
fn read_catalog(
  source : String,
  side : String,
  lines~ : Array[Int32] = [],
) -> @po.PoFile raise MergeError {
  if source.length() > 4_000_000 {
    raise Invalid(side + ": catalog exceeds input limit")
  }
  check_blocks(source, side, lines)
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
  if doc.entries.length() != lines.length() {
    raise Invalid(side + ": PO parser and entry boundaries disagree")
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
fn check_blocks(
  source : String,
  side : String,
  lines : Array[Int32],
) -> Unit raise MergeError {
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
    if !occupied {
      lines.push(number + 1)
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
    } else if line.has_prefix("\"") {
      check_literal(line, side, number + 1)
    } else {
      guard line.find(" ") is Some(end) else {
        raise Invalid(side + ": expected directive and quoted value")
      }
      let field = line[:end].to_owned()
      check_literal(line[end:].trim().to_owned(), side, number + 1)
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
fn check_literal(
  value : String,
  side : String,
  line : Int32,
) -> Unit raise MergeError {
  if value.has_prefix("\"") {
    let mut escaped = false
    for i in 1..<value.length() {
      let unit = value[i]
      if unit.to_int() == 0 {
        break
      }
      if escaped {
        escaped = false
      } else if unit == '\\' {
        escaped = true
      } else if unit == '"' {
        if i == value.length() - 1 {
          return
        }
        break
      }
    }
  }
  raise Invalid(
    "\{side}:\{line}: expected exactly one quoted PO string per line",
  )
}

///|
fn index_catalog(
  doc : @po.PoFile,
  side : String,
  lines : Array[Int32],
) -> Map[(String?, String, Bool), (@po.PoEntry, Int32)] raise MergeError {
  let index = Map([])
  for i, entry in doc.entries {
    let key = (entry.context, entry.msgid, entry.obsolete)
    if index.contains(key) {
      raise Invalid(side + ": duplicate entry " + entry.msgid)
    }
    index[key] = (entry, lines[i])
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
  let bl = []
  let ol = []
  let tl = []
  let b = read_catalog(base, "base", lines=bl)
  let o = read_catalog(ours, "ours", lines=ol)
  let t = read_catalog(theirs, "theirs", lines=tl)
  for field in ["Language", "Plural-Forms", "Content-Type"] {
    let value = b.metadata().get(field)
    if o.metadata().get(field) != value || t.metadata().get(field) != value {
      raise Invalid("incompatible catalog metadata: " + field)
    }
  }
  let bi = index_catalog(b, "base", bl)
  let oi = index_catalog(o, "ours", ol)
  let ti = index_catalog(t, "theirs", tl)
  let entries : Array[(@po.PoEntry?, Int32?)] = []
  let conflicts : Array[Slot] = []
  let seen : Map[(String?, String, Bool), Bool] = Map([])
  let summary : MergeSummary = {
    unchanged: 0,
    ours_only: 0,
    theirs_only: 0,
    converged: 0,
    removed: 0,
  }
  for index in [bi, oi, ti] {
    for key, _ in index {
      if seen.contains(key) {
        continue
      }
      seen[key] = true
      let bv = bi.get(key).map(pair => pair.0)
      let ov = oi.get(key).map(pair => pair.0)
      let tv = ti.get(key).map(pair => pair.0)
      if ov == tv {
        if ov == bv {
          summary.unchanged += 1
        } else {
          summary.converged += 1
        }
        if ov is None {
          summary.removed += 1
        }
        entries.push((ov, None))
      } else if tv == bv {
        summary.ours_only += 1
        if ov is None {
          summary.removed += 1
        }
        entries.push((ov, None))
      } else if ov == bv {
        summary.theirs_only += 1
        if tv is None {
          summary.removed += 1
        }
        entries.push((tv, None))
      } else {
        let id = conflicts.length()
        let (context, message, _) = key
        let lines = [bi, oi, ti].map(idx => {
          idx.get(key).map(pair => pair.1).unwrap_or(0)
        })
        conflicts.push({
          id,
          context,
          message,
          lines,
          base: bv,
          ours: ov,
          theirs: tv,
        })
        entries.push((None, Some(id)))
      }
    }
  }
  {
    entries,
    conflicts,
    fingerprints: [base, ours, theirs].map(fingerprint),
    summary,
  }
}

///|
fn fingerprint(source : String) -> String {
  let digest = @crypto.sha256_from_iter(@utf8.encode(source).iter())
  let hex = "0123456789abcdef".to_array()
  let result = StringBuilder()
  for byte in digest {
    result.write_char(hex[byte.to_int() >> 4])
    result.write_char(hex[byte.to_int() & 15])
  }
  result.to_string()
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
    "version": 2,
    "summary": {
      "unchanged": Json(self.summary.unchanged),
      "ours_only": Json(self.summary.ours_only),
      "theirs_only": Json(self.summary.theirs_only),
      "converged": Json(self.summary.converged),
      "removed": Json(self.summary.removed),
      "conflicts": Json(self.conflicts.length()),
    },
    "input_sha256": {
      "base": Json(self.fingerprints[0]),
      "ours": Json(self.fingerprints[1]),
      "theirs": Json(self.fingerprints[2]),
    },
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
        "lines": {
          "base": location_json(slot.lines[0]),
          "ours": location_json(slot.lines[1]),
          "theirs": location_json(slot.lines[2]),
        },
      }),
    ),
  }
}

///|
/// Tell whether the plan needs decisions before it can produce a PO.
pub fn MergePlan::has_conflicts(self : MergePlan) -> Bool {
  !self.conflicts.is_empty()
}

///|
fn location_json(line : Int32) -> Json {
  if line == 0 {
    null
  } else {
    Json(line)
  }
}

///|
fn custom_translation(
  slot : Slot,
  text : String,
) -> @po.PoEntry raise MergeError {
  guard slot.ours is Some(entry) && !entry.is_header() else {
    raise Invalid("custom translation requires a non-header ours entry")
  }
  let value = @json.parse(text) catch {
    _ => raise Invalid("custom translation must contain valid JSON")
  }
  guard value is Array(items) && items.length() == entry.translations.length() else {
    raise Invalid("custom translation must supply every translation slot")
  }
  let translations : Array[String] = []
  for item in items {
    guard item is String(value) else {
      raise Invalid("custom translation slots must be strings")
    }
    translations.push(value)
  }
  { ..entry, translations, }
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
        _ if choice.has_prefix("json:") =>
          Some(custom_translation(slot, choice[5:].to_owned()))
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
