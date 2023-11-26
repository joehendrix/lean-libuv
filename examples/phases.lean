/-
This is a Lean implementation of `idle-basic/main.c` with a smaller counter in

  https://nikhilm.github.io/uvbook/basics.html

-/
import LibUV

def fatalError (msg:String) : IO Unit := do
  IO.eprintln msg
  (← IO.getStderr).flush
  IO.Process.exit 1

def main : IO Unit := do
  let pp (s:String) := IO.println s
  let l ← UV.mkLoop
  let async ← l.mkAsync fun _ => pp "Async"
  let check ← l.mkCheck
  check.start do pp "Check"
  let idle ← l.mkIdle
  idle.start do pp "Idle"
  IO.println s!"Run 0"
  let _ ← l.run UV.RunMode.Once
  IO.println s!"Run 1"
  async.send
  let _ ← l.run UV.RunMode.Once
  IO.println s!"Run 2"
  async.send
  let _ ← l.run UV.RunMode.Once
  IO.println s!"Run 3"
