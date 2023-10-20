import LibUV

def wait_for_a_while (counter : IO.Ref Nat) (h : UV.Idle): BaseIO Unit := do
  let _ ← (IO.println s!"Counter").toBaseIO
  counter.modify (λc => c + 1)
  if (←counter.get) ≥ 5 then
    UV.Idle.stop h

def mkBool (i : Int) : Bool := if i > 7 then true else false

def main : IO Unit := do
  let l ← UV.mkLoop
  let counter ← IO.mkRef 0
  let idle ← UV.mkIdle l
  idle.start (wait_for_a_while counter)
  IO.println s!"Idling...\n"
  let allDone ← l.run
  IO.println s!"Done {allDone}\n"

#eval main