import LibUV

def main : IO Unit := UV.IO.run do
  let l ← UV.mkLoop
  let t ← l.mkTimer
  let start ← l.now
  let e := start + 100
  let last ← IO.mkRef start
  UV.log s!"Timer started"
  t.start 10 10 do
    let now ← l.now
    let dur := now - (←last.get)
    last.set now
    UV.log s!"Elapsed {dur}"
    if dur < 10 || dur > 15 then
      UV.fatal s!"Unexpected duration {dur}."
    if now ≥ e then
      t.stop
  let _ ← l.run
  if (←last.get) < e then
    UV.fatal "Loop stopped early!"
