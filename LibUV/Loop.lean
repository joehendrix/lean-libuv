import Alloy.C

open scoped Alloy.C
alloy c include <lean_uv.h>

namespace UV

inductive ErrorCode where
| EALREADY
| ECANCELED
| EINVAL
| ETIMEDOUT
deriving Inhabited, Repr

alloy c section


LEAN_EXPORT lean_object* lean_uv_error_mk(int code) {
  if (code >= 0)
    fatal_error("Unexpected success code %d.\n", code);
  size_t r;
  switch (code) {
  case UV_EALREADY:
    r = LUV_EALREADY;
    break;
  case UV_ECANCELED:
    r = LUV_ECANCELED;
    break;
  case UV_EINVAL:
    r = LUV_EINVAL;
    break;
  case UV_ETIMEDOUT:
    r = LUV_ETIMEDOUT;
    break;
  default:
    fatal_error("Unexpected error code %s.\n", uv_err_name(code));
  }
  return lean_box(r);
}
end

protected inductive Error where
| errorcode : ErrorCode → UV.Error
| user : String → UV.Error
deriving Repr

@[export lean_uv_error_errorcode]
def UV.Error.errorcode_c  := Error.errorcode

alloy c section
lean_object* lean_uv_error_errorcode(lean_object* err);

/* Returns an IO error for the given error code. */
LEAN_EXPORT lean_object* lean_uv_io_error(int err) {
  return lean_io_result_mk_error(lean_uv_error_errorcode(lean_uv_error_mk(err)));
}

end


@[reducible]
protected def IO := EIO UV.Error

protected def IO.run (act : UV.IO α) : IO α := do
  match ← act.toBaseIO with
  | .error (.errorcode e) => throw (IO.userError s!"UV.IO failed (error = {repr e})")
  | .error (.user msg) => throw (IO.userError msg)
  | .ok r => pure r

@[extern "lean_uv_log"]
protected opaque log (s : @& String) : UV.IO Unit

alloy c section
lean_object* lean_uv_log(b_lean_obj_arg s, b_lean_obj_arg rw) {
  printf("%s\n", lean_string_cstr(s));
  return lean_io_result_mk_ok(lean_unit());
}
end


protected def fatal {α} (msg : String) : UV.IO α :=
  (throw (.user msg) : EIO UV.Error α)

structure Ref (α : Type) where
  val : IO.Ref α

protected def mkRef (a:α) : UV.IO (Ref α) :=
  Ref.mk <$> IO.mkRef a

protected def Ref.get (r:Ref α) : UV.IO α := r.val.get

protected def Ref.set (r:Ref α) (v : α) : UV.IO Unit := r.val.set v

protected def Ref.modify (r:Ref α) (f : α → α): UV.IO Unit := r.val.modify f

/--
Report an error that occurred because a function was passed an argument
that was in a unsupported state.

These always represent program bugs.  The function condition could have
been checked beforehand.
-/
@[export lean_uv_raise_invalid_argument]
private def raiseInvalidArgument (message:String) : UV.IO α :=
  throw (.errorcode ErrorCode.EINVAL)

alloy c section

static void uv_close_and_free(uv_handle_t* h) {
  uv_close(h, (uv_close_cb) &free);
}

// Close the check handle if the loop stops
static void lean_uv_check_loop_stop(uv_handle_t* h) {
  lean_uv_check_t* check = (lean_uv_check_t*) h;
  lean_dec_optref(check->callback);
  uv_close_and_free(h);
}

// Close the idle handle if the loop stops
static void lean_uv_idle_loop_stop(uv_handle_t* h) {
  lean_uv_idle_t* idle = (lean_uv_idle_t*) h;
  lean_dec_optref(idle->callback);
  uv_close_and_free(h);
}

// Close the check handle if the loop stops
static void lean_uv_tcp_loop_stop(uv_handle_t* h) {
  lean_uv_tcp_t* tcp = lean_stream_base(h);
  lean_stream_callbacks_t* callbacks = &tcp->callbacks;
  lean_dec_optref(callbacks->listen_callback);
  lean_dec_optref(callbacks->read_callback);
  uv_close(h, &lean_uv_close_stream);
}

static void lean_uv_timer_loop_stop(uv_handle_t* h) {
  lean_uv_timer_t* timer = (lean_uv_timer_t*) h;
  lean_dec_optref(timer->callback);
  uv_close_and_free(h);
}

static void stop_handles(uv_handle_t* h, void* arg) {
  if (uv_is_closing(h)) return;
  switch (h->type) {
  case UV_CHECK:
    lean_uv_check_loop_stop(h);
    break;
  case UV_IDLE:
    lean_uv_idle_loop_stop(h);
    break;
  case UV_TCP:
    lean_uv_tcp_loop_stop(h);
    break;
  case UV_TIMER:
    lean_uv_timer_loop_stop(h);
    break;
  default:
    fatal_error("Unsupported handle type %s", uv_handle_type_name(h->type));
    break;
  }
}

static void Loop_finalize(void* ptr) {
  printf("Loop_finalize\n");
  uv_loop_t* loop = (uv_loop_t*) ptr;
  int err = uv_loop_close(loop);
  if (err == UV_EBUSY) {
    uv_walk(loop, &stop_handles, 0);
    err = uv_run(loop, UV_RUN_NOWAIT);
    if (err != 0) {
      fatal_error("libuv loop has active handles after stopping.\n");
    }
    err = uv_loop_close(loop);
    if (err != 0) {
      fatal_error("libuv uv_loop_close failed with %d.\n", err);
    }
    free(ptr);
  } else if (err >= 0) {
    free(ptr);
  } else {
    fatal_error("uv_loop_close returned unexpected value (err = %d)\n", err);
  }
}

static void Loop_foreach(void* ptr, b_lean_obj_arg f) {
  fatal_st_only("Loop");
}

end

alloy c opaque_extern_type Loop => lean_uv_loop_t := {
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
  uv_loop->data = r;
  loop->io_error = 0;

  bool accum = lean_ctor_get_uint8(options, 0);
  bool block = lean_ctor_get_uint8(options, 1);

  if (accum) {
    int err = uv_loop_configure(uv_loop, UV_METRICS_IDLE_TIME);
    if (err != 0) {
      fatal_error("uv_loop_configure failed (error = %d).\n", err);
    }
  }
#if defined(WIN32) || defined(_WIN32)
#else
  if (block) {
    int err = uv_loop_configure(uv_loop, UV_LOOP_BLOCK_SIGNAL, SIGPROF);
    if (err != 0) {
      fatal_error("uv_loop_configure failed (error = %d).\n", err);
    }
  }
#endif
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
def run_aux (loop : @& Loop) (mode : RunMode) : UV.IO Bool := {
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

def run (l : Loop) (mode : RunMode := RunMode.Default) : UV.IO Bool := run_aux l mode

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
