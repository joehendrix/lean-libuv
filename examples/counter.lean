/-
This is a Lean implementation of `idle-basic/main.c` with a smaller counter in

  https://nikhilm.github.io/uvbook/basics.html

-/
import LibUV

def ex1 : UV.IO Unit := do
  let l ← UV.mkLoop
  let counter ← UV.mkRef 0
  let idle ← l.mkIdle
  UV.log s!"Active {←(UV.Handle.idle idle).isActive}"
  let stop := 7
  idle.start do
    counter.modify (λc => c + 1)
    if (←counter.get) ≥ 7 then
      idle.stop
  UV.log s!"Active {←(UV.Handle.idle idle).isActive}"
  UV.log "Idling..."
  let stillActive ← l.run
  if stillActive then
    UV.fatal "Loop stopped while handle still active."
  if (←counter.get) ≠ stop then
    UV.fatal s!"Loop stopped early (counter = {←counter.get})"
  UV.log "Done"


def main : IO Unit := UV.IO.run do
  let l ← UV.mkLoop
  let counter ← IO.mkRef 0
  let idle ← l.mkIdle
  UV.log s!"Active {←(UV.Handle.idle idle).isActive}"
  let stop := 7
  idle.start do
    counter.modify (λc => c + 1)
    if (←counter.get) ≥ 7 then
      idle.stop
  UV.log s!"Active {←(UV.Handle.idle idle).isActive}"
  UV.log "Idling..."
  let stillActive ← l.run
  if stillActive then
    UV.fatal "Loop stopped while handle still active."
  if (←counter.get) ≠ stop then
    UV.fatal s!"Loop stopped early (counter = {←counter.get})"
  UV.log "Done"
