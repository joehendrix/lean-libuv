/-
This is a Lean implementation of `idle-basic/main.c` with a smaller counter in

  https://nikhilm.github.io/uvbook/basics.html

-/
import LibUV

def main : IO Unit := UV.IO.run do
  let l ← UV.mkLoop
  let check ← l.mkCheck
  check.start do UV.log "Check"
  let idle ← l.mkIdle
  idle.start do UV.log "Idle"
  UV.log s!"Run 0"
  let _ ← l.run UV.RunMode.Once
  UV.log s!"Run 1"
  let _ ← l.run UV.RunMode.Once
  UV.log s!"Run 2"
  let _ ← l.run UV.RunMode.Once
  UV.log s!"Run 3"
