import LibUV

def main : IO Unit := UV.IO.run do
  let l ← UV.mkLoop
  let _ ← l.queue_work (UV.log s!"Hello" >>= fun _ => pure 1) fun (r : Except _ Nat) => do
    match r with
    | .error e => UV.log s!"Error {repr e}"
    | .ok v => UV.log s!"Returned {v}"
  let _ ← l.run
  pure ()
