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
      "usage: plan BASE OURS THEIRS | apply BASE OURS THEIRS REVIEW.json [base|ours|theirs ...]",
    )
  }
  let plan = @merge.plan_merge(
    read_po(args[2]),
    read_po(args[3]),
    read_po(args[4]),
  )
  match args[1] {
    "plan" => {
      if args.length() != 5 {
        fail("plan takes exactly three inputs")
      }
      let report = plan.report().stringify() + "\n"
      if @utf8.encode(report).length() > 4_000_000 {
        fail("review exceeds the 4 MB CLI input limit")
      }
      @stdio.stdout.write(report)
    }
    "apply" => {
      if args.length() < 6 {
        fail("apply requires the reviewed plan JSON file")
      }
      if read_po(args[5]).trim().to_owned() != plan.report().stringify() {
        fail("reviewed report differs from current input. Run plan again.")
      }
      @stdio.stdout.write(plan.apply(args[6:].to_owned()))
    }
    _ => fail("unknown command: " + args[1])
  }
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
