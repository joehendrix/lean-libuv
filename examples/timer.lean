import LibUV

def main : IO Unit := UV.IO.run do
  let l ← UV.mkLoop
  let t ← l.mkTimer
  let start ← l.now
  let inc := 10
  let maxInc := 15
  let dur := 100
  let e := start + 100
  let last ← IO.mkRef start
  UV.log s!"Timer will step every {inc}ms and stop after {dur}ms."
  t.start inc inc do
    let now ← l.now
    let dur := now - (←last.get)
    last.set now
    UV.log s!"Elapsed {now - start}ms"
    if dur < inc || dur > maxInc then
      UV.fatal s!"Unexpected duration {dur}."
    if now ≥ e then
      t.stop
  let _ ← l.run
  if (←last.get) < e then
    UV.fatal "Loop stopped early!"
