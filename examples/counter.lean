/-
This is a Lean implementation of `idle-basic/main.c` with a smaller counter in

  https://nikhilm.github.io/uvbook/basics.html

-/
import LibUV

def fatalError (msg:String): IO Unit := do
  IO.eprintln msg
  (← IO.getStderr).flush
  IO.Process.exit 1

def main : IO Unit := do
  let l ← UV.mkLoop
  let counter ← IO.mkRef 0
  let idle ← UV.mkIdle l
  let stop := 7
  idle.start fun h => do
    counter.modify (λc => c + 1)
    if (←counter.get) ≥ 7 then
      h.stop
  IO.println "Idling..."; (←IO.getStdout).flush
  let stillActive ← l.run
  if stillActive then
    fatalError "Loop stopped while handle still active."
  if (←counter.get) ≠ stop then
    fatalError s!"Loop stopped early (counter = {←counter.get})"
  IO.println "Done"
