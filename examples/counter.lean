/-
This is a Lean implementation of `idle-basic/main.c` with a smaller counter in

  https://nikhilm.github.io/uvbook/basics.html

-/
import LibUV

def main : IO Unit := UV.IO.run do
  let l ← UV.mkLoop
  let counter ← IO.mkRef 0
  let idle ← l.mkIdle
  let stop := 7
  idle.start do
    counter.modify (·+1)
    UV.log s!"Step {←counter.get}"
    if (←counter.get) ≥ stop then
      idle.stop
  let stillActive ← l.run
  if stillActive then
    UV.fatal "Loop stopped while handle still active."
  if (←counter.get) ≠ stop then
    UV.fatal s!"Loop stopped early (counter = {←counter.get})"
  UV.log "Done"
