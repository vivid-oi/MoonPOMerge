///|
async fn read_po(path : String) -> String {
  let f = @fs.open(path[:], mode=ReadOnly)
  defer f.close()
  if f.kind() != Regular || f.size() > 4_000_000L {
    fail("expected regular file of at most 4 MB: " + path)
  }
  let data : Array[Byte] = []
  while f.read_some(max_len=65536) is Some(chunk) {
    if chunk.length() > 4_000_000 - data.length() {
      fail("input exceeds 4 MB: " + path)
    }
    for byte in chunk {
      data.push(byte)
    }
  }
  @utf8.decode(Bytes::from_array(data[:])[:])
}

///|
async fn execute() -> Unit {
  let args = @env.args()
  if args.length() < 5 {
    fail(
      "usage: plan|check|git-driver BASE OURS THEIRS | apply BASE OURS THEIRS REVIEW.json [choices ...] | apply-file BASE OURS THEIRS REVIEW.json DECISIONS.json",
    )
  }
  let base = read_po(args[2])
  let ours = read_po(args[3])
  let theirs = read_po(args[4])
  let plan = @merge.plan_merge(base, ours, theirs)
  match args[1] {
    "git-driver" => {
      if args.length() != 5 {
        fail("git-driver requires BASE OURS THEIRS")
      }
      if plan.has_conflicts() {
        @stdio.stderr.write(plan.report().stringify() + "\n")
        exit_process(1)
      } else {
        let output = plan.apply([])
        if read_po(args[3]) != ours {
          fail("ours changed during merge")
        }
        replace_ours(args[3], @utf8.encode(output))
      }
    }
    "plan" | "check" => {
      if args.length() != 5 {
        fail("plan and check take exactly three inputs")
      }
      let report = plan.report().stringify() + "\n"
      if @utf8.encode(report).length() > 4_000_000 {
        fail("review exceeds the 4 MB CLI input limit")
      }
      if args[1] == "check" && !plan.has_conflicts() {
        ignore(plan.apply([]))
      }
      @stdio.stdout.write(report)
      if args[1] == "check" && plan.has_conflicts() {
        exit_process(1)
      }
    }
    "apply" | "apply-file" => {
      if args.length() < 6 {
        fail("apply requires the reviewed plan JSON file")
      }
      if read_po(args[5]).trim().to_owned() != plan.report().stringify() {
        fail("reviewed report differs from current input. Run plan again.")
      }
      let choices = if args[1] == "apply-file" {
        if args.length() != 7 {
          fail("apply-file requires REVIEW.json and DECISIONS.json")
        }
        read_decisions(args[6])
      } else {
        args[6:].to_owned()
      }
      @stdio.stdout.write(plan.apply(choices))
    }
    _ => fail("unknown command: " + args[1])
  }
}

///|
async fn read_decisions(path : String) -> Array[String] {
  let text = read_po(path)
  let value = @json.parse(text) catch {
    _ => fail("decisions file is not valid JSON")
  }
  guard value is Array(items) else {
    fail("decisions file must contain an array")
  }
  let choices = []
  for item in items {
    match item {
      String(choice) => choices.push(choice)
      Array(_) => choices.push("json:" + item.stringify())
      _ =>
        fail("each decision must be a branch name or an array of translations")
    }
  }
  choices
}

///|
#cfg(target="native")
extern "C" fn exit_process(code : Int32) -> Unit = "exit"

///|
#cfg(target="wasm")
#unsafe_skip_stub_check
fn exit_process(code : Int32) -> Unit = "moonbitlang/async" "runtime/exit"

///|
async fn main {
  execute() catch {
    @merge.Invalid(message) => {
      @stdio.stderr.write(message + "\n")
      exit_process(2)
    }
    error => {
      @stdio.stderr.write(error.to_string() + "\n")
      exit_process(2)
    }
  }
}
