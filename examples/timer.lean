import LibUV

def main : IO Unit := do
  let l ← UV.mkLoop
  let t ← l.mkTimer
  let start ← l.now
  let e := start + 100
  let last ← IO.mkRef start
  IO.println s!"Timer started"
  t.start 10 10 do
    let now ← l.now
    let dur := now - (←last.get)
    last.set now
    IO.println s!"Elapsed {dur}"
    if dur < 10 || dur > 15 then
      throw (IO.userError s!"Unexpected duration {dur}.")
    if now ≥ e then
      t.stop
  let _ ← l.run
  if (←last.get) < e then
    throw (IO.userError "Loop stopped early!")
