import Alloy.C

open scoped Alloy.C
alloy c include <lean_uv.h>

namespace UV


private def EINVAL : UInt32 := 22

/--
Report an error that occurred because a function was passed an argument
that was in a unsupported state.

These always represent program bugs.  The function condition could have
been checked beforehand.
-/
@[export lean_uv_raise_invalid_argument]
private def raiseInvalidArgument (message:String) : IO Unit :=
  throw <| IO.Error.invalidArgument none EINVAL message

alloy c section

static void Loop_foreach(void* ptr, b_lean_obj_arg f) {
}

static void Loop_finalize(void* ptr) {
  uv_loop_t* l = (uv_loop_t*) ptr;
  int err = uv_loop_close(l);
  if (err < 0)
    fatal_error("libuv loop finalize called before resources free.\n");
  free(ptr);
}

end

alloy c extern_type Loop => lean_uv_loop_t := {
  foreach := `Loop_foreach
  finalize := `Loop_finalize
}

/--
Options to control configure Loop at startup.
-/
structure Loop.Options where
  /--
  Loop metrics will accumulate idle time for reporting later.
  -/
  accumulateIdleTime : Bool := False
  /--
  Block SIGProf signal when polling for new events.
  -/
  blockSigProfSignal : Bool := False

alloy c extern "lean_uv_mk_loop"
def mkLoop (options : Loop.Options := {}) : BaseIO Loop := {
  lean_uv_loop_t* loop = checked_malloc(sizeof(lean_uv_loop_t));
  uv_loop_t* uv_loop = &loop->uv;
  int err = uv_loop_init(uv_loop);
  if (err < 0)
    fatal_error("uv_loop_init failed (error = %d).\n", err);
  lean_object* r = to_lean<Loop>(loop);
  *loop_object(uv_loop) = r;
  loop->io_error = 0;

  bool accum = lean_ctor_get_uint8(options, 0);
  bool block = lean_ctor_get_uint8(options, 1);

  if (accum) {
    int err = uv_loop_configure(uv_loop, UV_METRICS_IDLE_TIME);
    if (err != 0) {
      fatal_error("uv_loop_configure failed (error = %d).\n", err);
    }
  }
  if (block) {
    int err = uv_loop_configure(uv_loop, UV_LOOP_BLOCK_SIGNAL, SIGPROF);
    if (err != 0) {
      fatal_error("uv_loop_configure failed (error = %d).\n", err);
    }
  }
  return lean_io_result_mk_ok(r);
}

alloy c enum
  RunMode => uv_run_mode
  | Default => UV_RUN_DEFAULT
  | Once   => UV_RUN_ONCE
  | NoWait => UV_RUN_NOWAIT
  deriving Inhabited

namespace Loop

/--
This runs the loop until `stop` is called or there are no
more active and referenced handles or requests.  Returns true if there are still
active and referenced handles or requests.
-/
alloy c extern "lean_uv_run"
def run_aux (loop : @& Loop) (mode : RunMode) : IO Bool := {
  uv_run_mode lmode = of_lean<RunMode>(mode);
  lean_uv_loop_t* l = of_loop_ext(loop);
  bool stillActive = uv_run(&l->uv, lmode) != 0;
  lean_object* io_error = l->io_error;
  if (io_error) {
    l->io_error = 0;
    return io_error;
  } else {
    return lean_io_result_mk_ok(lean_bool(stillActive));
  }
}

def run (l : Loop) (mode : RunMode := RunMode.Default) : IO Bool := run_aux l mode

/--
Return true if the
-/
alloy c extern "lean_uv_alive"
def isAlive (l : @& Loop) : BaseIO Bool := {
  bool alive = uv_loop_alive(of_loop(l)) != 0;
  return lean_io_result_mk_ok(lean_bool(alive));
}

alloy c extern "lean_uv_stop"
def stop (l : @& Loop) : BaseIO Unit := {
  uv_stop(of_loop(l));
  return lean_io_unit_result_ok();
}

alloy c extern "lean_uv_now"
def now (l : @& Loop) : BaseIO UInt64 := {
  uint64_t now = uv_now(of_loop(l));
  return lean_io_result_mk_ok(lean_box_uint64(now));
}
