///|
// SPDX-License-Identifier: Apache-2.0
// Temporary-file publication follows the FontPin / MBTRelMask pattern.
async fn publish(path : String, bytes : Bytes, replace~ : Bool) -> Unit {
  guard @env.rand(16) is Some(random) else {
    fail("cannot allocate temporary name")
  }
  let hex = "0123456789abcdef".to_array()
  let suffix = StringBuilder()
  for b in random {
    suffix.write_char(hex[b.to_int() >> 4])
    suffix.write_char(hex[b.to_int() & 15])
  }
  let temp = path + "." + suffix.to_string() + ".pending"
  @async.protect_from_cancel(() => {
    let file = @fs.create(temp[:], allow_existing=false, permission=0o644)
    let mut installed = false
    defer (if !installed {
      @fs.remove(temp[:]) catch {
        _ => @stdio.stderr.write("cannot remove " + temp + "\n")
      }
    })
    {
      defer file.close()
      file.write(bytes)
      file.sync()
    }
    @fs.rename(temp[:], path[:], replace~)
    installed = true
  })
}
