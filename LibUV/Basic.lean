import Alloy.C
open scoped Alloy.C

alloy c include <stdlib.h> <uv.h> <lean/lean.h>

namespace UV

alloy c section

__attribute__((noreturn))
void fatal_error(const char *format, ...) {
  va_list args;
  va_start(args, format);
  vfprintf(stderr, format, args);
  va_end(args);
  exit(-1);
}

static void* checked_malloc(size_t n) {
  uv_loop_t* ptr = malloc(n);
  if (ptr == 0) {
    fatal_error("Out of memory.\n");
  }
  return ptr;
}

static void Null_foreach(void* ptr, b_lean_obj_arg f) {
}


static lean_object* lean_bool(bool b) {
  return lean_box(b ? 1 : 0);
}

static lean_object* lean_unit(void) {
  return lean_box(0);
}

static lean_object* lean_io_unit_result_ok() {
  lean_object* r = 0;
  if (r == 0) {
    r = lean_io_result_mk_ok(lean_unit());
    lean_mark_persistent(r);
  }
  return r;
}

end

section Loop

alloy c section

/* Return lean object representing this handle */
static lean_object** loop_object(uv_loop_t* l) {
  return (lean_object**) &(l->data);
}

static void Loop_finalize(void* ptr) {
  uv_loop_t* l = (uv_loop_t*) ptr;
  int r = uv_loop_close(l);
  if (r < 0)
    fatal_error("libuv loop finalize called before resources free.\n");
  free(ptr);
}

end

alloy c extern_type Loop => uv_loop_t := {
  foreach := `Null_foreach
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
  uv_loop_t* loop = checked_malloc(sizeof(uv_loop_t));
  int err = uv_loop_init(loop);
  if (err < 0)
    fatal_error("uv_loop_init failed (error = %d).\n", err);
  lean_object* r = to_lean<Loop>(loop);
  *loop_object(loop) = r;

  bool accum = lean_ctor_get_uint8(options, 0);
  bool block = lean_ctor_get_uint8(options, 1);

  if (accum) {
    printf("accum\n");
    int err = uv_loop_configure(loop, UV_METRICS_IDLE_TIME);
    if (err != 0) {
      fatal_error("uv_loop_configure failed (error = %d).\n", err);
    }
  }
  if (block) {
    printf("block\n");
    int err = uv_loop_configure(loop, UV_LOOP_BLOCK_SIGNAL, SIGPROF);
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
def run_aux (l : @& Loop) (mode : RunMode) : BaseIO Bool := {
  uv_run_mode lmode = of_lean<RunMode>(mode);
  bool stillActive = uv_run(of_lean<Loop>(l), lmode) != 0;
  return lean_io_result_mk_ok(lean_bool(stillActive));
}

def run (l : Loop) (mode : RunMode := RunMode.Default): BaseIO Bool := run_aux l mode

/--
Return true if the
-/
alloy c extern "lean_uv_alive"
def isAlive (l : @& Loop) : BaseIO Bool := {
  bool alive = uv_loop_alive(of_lean<Loop>(l)) != 0;
  return lean_io_result_mk_ok(lean_bool(alive));
}

alloy c extern "lean_uv_stop"
def stop (l : @& Loop) : BaseIO Unit := {
  uv_stop(of_lean<Loop>(l));
  return lean_io_unit_result_ok();
}

end Loop

end Loop

section HandleCommon

alloy c section

/* Return lean object representing this handle */
static lean_object** handle_object(uv_handle_t* p) {
  return (lean_object**) &(p->data);
}

static void free_handle(uv_handle_t* handle) {
  lean_dec(*loop_object(handle->loop));
  free(handle);
}

end

end HandleCommon

section Idle

alloy c section

struct lean_uv_idle_s {
  uv_idle_t idle;
  lean_object* callback; // Object referecing method to call.
};

typedef struct lean_uv_idle_s lean_uv_idle_t;

/* Return lean object representing this idler */
static uv_handle_t* idler_handle(lean_uv_idle_t* p) {
  return (uv_handle_t*) &(p->idle);
}

/* Return callback associated with idler */
static lean_object** idler_callback(lean_uv_idle_t* p) {
  return &(p->callback);
}

static void Idle_foreach(void* ptr, b_lean_obj_arg f) {
  lean_uv_idle_t* idler = (lean_uv_idle_t*) ptr;
  lean_apply_1(f, *idler_callback(idler));
}

static void idle_close_cb(lean_uv_idle_t* idler) {
  lean_dec(*idler_callback(idler));
  free_handle(idler_handle(idler));
}

static void Idle_finalize(void* ptr) {
  uv_close((uv_handle_t*) ptr, (uv_close_cb) &idle_close_cb);
}

static void idle_invoke_callback(lean_uv_idle_t* idler) {
  // Get callback and idler handler objects
  lean_object* cb = *idler_callback(idler);
  lean_object* o = *handle_object(idler_handle(idler));
  // Increment reference counts to both prior to application.
  lean_inc(cb);
  lean_inc(o);
  // Invoke and discard result.
  lean_dec(lean_apply_2(cb, o, lean_box(0)));
}

end

alloy c extern_type Idle => lean_uv_idle_t := {
  foreach := `Idle_foreach
  finalize := `Idle_finalize
}

alloy c extern "lean_uv_idle_init"
def Loop.mkIdle (loop : Loop) : BaseIO Idle := {
  lean_uv_idle_t* idler = malloc(sizeof(lean_uv_idle_t));
  *idler_callback(idler) = 0;
  lean_object* r = to_lean<Idle>(idler);
  *handle_object(idler_handle(idler)) = r;
  uv_idle_init(of_lean<Loop>(loop), &idler->idle);
  return lean_io_result_mk_ok(r);
}

/--
Start invoking the callback on the idle loop.
-/
alloy c extern "lean_uv_idle_start"
def Idle.start (r : Idle) (callback : Idle → BaseIO Unit) : BaseIO Unit := {
  lean_uv_idle_t* idler = lean_get_external_data(r);
  *idler_callback(idler) = callback;
  uv_idle_start(&idler->idle, (uv_idle_cb) &idle_invoke_callback);
  return lean_io_unit_result_ok();
}

/--
Stop invoking the idle handler.
-/
alloy c extern "lean_uv_idle_stop"
def Idle.stop (h : @& Idle) : BaseIO Unit := {
  lean_uv_idle_t* idler = lean_get_external_data(h);
  uv_idle_stop(&idler->idle);
  lean_dec(h);
  return lean_io_unit_result_ok();
}

end Idle

section Async

alloy c section

struct lean_uv_async_s {
  uv_async_t async;
  lean_object* callback; // Object referecing method to call.
};

typedef struct lean_uv_async_s lean_uv_async_t;

/* Return lean object representing this idler */
static uv_handle_t* async_handle(lean_uv_async_t* p) {
  return (uv_handle_t*) &(p->async);
}

/* Return callback associated with idler */
static lean_object** async_callback(lean_uv_async_t* p) {
  return &(p->callback);
}

static void Async_foreach(void* ptr, b_lean_obj_arg f) {
  lean_uv_async_t* uv_ptr = (lean_uv_async_t*) ptr;
  lean_apply_1(f, *async_callback(uv_ptr));
}

static void async_close_cb(lean_uv_async_t* async) {
  lean_dec(*async_callback(async));
  free_handle(async_handle(async));
}

static void Async_finalize(void* ptr) {
  uv_close((uv_handle_t*) ptr, (uv_close_cb) &async_close_cb);
}

static void async_invoke_callback(lean_uv_async_t* async) {
  // Get callback and async handler objects
  lean_object* cb = *async_callback(async);
  lean_object* o = *handle_object(async_handle(async));
  // Increment reference counts to both prior to application.
  lean_inc(cb);
  lean_inc(o);
  // Invoke and discard result.
  lean_dec(lean_apply_2(cb, o, lean_box(0)));
}


end

alloy c extern_type Async => lean_uv_async_t := {
  foreach := `Async_foreach
  finalize := `Async_finalize
}

/--
This create an asynchronous handle
-/
alloy c extern "lean_uv_async_init"
def Loop.mkAsync (loop : Loop) (callback : Async → BaseIO Unit) : BaseIO Async := {
  lean_uv_async_t* async = malloc(sizeof(lean_uv_async_t));
  lean_object* r = to_lean<Async>(async);
  *handle_object(async_handle(async)) = r;
  *async_callback(async) = callback;
  uv_async_init(of_lean<Loop>(loop), &async->async, (uv_async_cb) &async_invoke_callback);
  return lean_io_result_mk_ok(r);
}

alloy c extern "lean_uv_async_send"
def Async.send (async : @& Async) : BaseIO Unit := {
  int r = uv_async_send(&of_lean<Async>(async)->async);
  if (r != 0) {
    fatal_error("uv_async_send failed (error = %d)\n", r);
  }
  return lean_io_unit_result_ok();
}

end Async

section Check

alloy c section

struct lean_uv_check_s {
  uv_check_t uv;
  lean_object* callback; // Object referecing method to call.
};

typedef struct lean_uv_check_s lean_uv_check_t;

/* Return lean object representing this check */
static uv_handle_t* check_handle(lean_uv_check_t* p) {
  return (uv_handle_t*) &(p->uv);
}

/* Return callback associated with check */
static lean_object** check_callback(lean_uv_check_t* p) {
  return &(p->callback);
}

static void Check_foreach(void* ptr, b_lean_obj_arg f) {
  lean_uv_check_t* check = (lean_uv_check_t*) ptr;
  lean_apply_1(f, *check_callback(check));
}

static void check_close_cb(lean_uv_check_t* check) {
  lean_dec(*check_callback(check));
  free_handle(check_handle(check));
}

static void Check_finalize(void* ptr) {
  uv_close((uv_handle_t*) ptr, (uv_close_cb) &check_close_cb);
}

static void check_invoke_callback(lean_uv_check_t* check) {
  // Get callback and handler objects
  lean_object* cb = *check_callback(check);
  lean_object* o = *handle_object(check_handle(check));
  // Increment reference counts to both prior to application.
  lean_inc(cb);
  lean_inc(o);
  // Invoke and discard result.
  lean_dec(lean_apply_2(cb, o, lean_box(0)));
}

end

alloy c extern_type Check => lean_uv_check_t := {
  foreach  := `Check_foreach
  finalize := `Check_finalize
}

alloy c extern "lean_uv_check_init"
def Loop.mkCheck (loop : Loop) : BaseIO Check := {
  lean_uv_check_t* check = malloc(sizeof(lean_uv_check_t));
  *check_callback(check) = 0;
  lean_object* r = to_lean<Check>(check);
  *handle_object(check_handle(check)) = r;
  uv_check_init(of_lean<Loop>(loop), &check->uv);
  return lean_io_result_mk_ok(r);
}

/--
Start invoking the callback on the loop.
-/
alloy c extern "lean_uv_check_start"
def Check.start (r : Check) (callback : Check → BaseIO Unit) : BaseIO Unit := {
  lean_uv_check_t* check = lean_get_external_data(r);
  *check_callback(check) = callback;
  uv_check_start(&check->uv, (uv_check_cb) &check_invoke_callback);
  return lean_io_unit_result_ok();
}

/--
Stop invoking the check handler.
-/
alloy c extern "lean_uv_check_stop"
def Check.stop (h : @&Check) : BaseIO Unit := {
  lean_uv_check_t* check = lean_get_external_data(h);
  uv_check_stop(&check->uv);
  lean_dec(h);
  return lean_io_unit_result_ok();
}

end Check

section Handle

inductive Handle where
  | async : Async -> Handle
  | check : Check -> Handle
  | idle : Idle -> Handle

alloy c section

extern lean_object* lean_uv_handle_id(lean_object* h) {
  return h;
}

static lean_object* lean_uv_handle_rec(
    lean_object* async,
    lean_object* check,
    lean_object* idle,
    lean_object* h) {
  uv_handle_t* hdl = (uv_handle_t *) lean_get_external_data(h);
  switch (hdl->type) {
  case  UV_ASYNC:
    return lean_apply_1(async, h);
  case  UV_CHECK:
    return lean_apply_1(check, h);
  case UV_IDLE:
    return lean_apply_1(idle, h);
  default:
    fatal_error("Unsupported type %d\n", hdl->type);
  }
}

end

attribute [extern "lean_uv_handle_id"] Handle.async
attribute [extern "lean_uv_handle_id"] Handle.check
attribute [extern "lean_uv_handle_id"] Handle.idle
attribute [extern "lean_uv_handle_rec"] Handle.rec

namespace Handle

/--
Returns true if handle is active.

See [uv_is_active](https://docs.libuv.org/en/v1.x/handle.html#c.uv_is_active).
-/
alloy c extern "lean_uv_handle_is_active"
def isActive (h : Handle) : BaseIO Bool := {
  uv_handle_t* hdl = (uv_handle_t *) lean_get_external_data(h);
  bool b = uv_is_active(hdl) != 0;
  return lean_io_result_mk_ok(lean_bool(b));
}

/--
Returns true if handle is closing.

See [uv_is_closing](https://docs.libuv.org/en/v1.x/handle.html#c.uv_is_closing).
-/
alloy c extern "lean_uv_handle_is_closing"
def isClosing (h : Handle) : BaseIO Bool := {
  uv_handle_t* hdl = (uv_handle_t *) lean_get_external_data(h);
  bool b = uv_is_closing(hdl) != 0;
  return lean_io_result_mk_ok(lean_bool(b));
}

end Handle

/-
  UV_FS_EVENT,
  UV_FS_POLL,
  UV_HANDLE,
  UV_IDLE,
  UV_NAMED_PIPE,
  UV_POLL,
  UV_PREPARE,
  UV_PROCESS,
  UV_STREAM,
  UV_TCP,
  UV_TIMER,
  UV_TTY,
  UV_UDP,
  UV_SIGNAL,
  UV_FILE,
-/

end Handle

end UV
