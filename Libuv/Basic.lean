import Alloy.C
open scoped Alloy.C

alloy c include <stdlib.h> <uv.h> <lean/lean.h>

namespace UV

alloy c section

static void Null_foreach(void* ptr, b_lean_obj_arg f) {
}

static void* checked_malloc(size_t n) {
  uv_loop_t* ptr = malloc(n);
  if (ptr == 0) {
    fprintf(stderr, "Out of memory.\n");
    exit(-1);
  }
  return ptr;
}

static lean_object* lean_bool(bool b) {
  return lean_box(b ? 1 : 0);
}

struct lean_uv_loop_s {
  uv_loop_t uv_val;
  lean_object* lean_obj;
};

typedef struct lean_uv_loop_s lean_uv_loop_t;

static void Loop_finalize(void* ptr) {
  lean_uv_loop_t* l = (lean_uv_loop_t*) ptr;
  int r = uv_loop_close(&l->uv_val);
  if (r < 0) {
    fprintf(stderr, "libuv loop finalize called before resources free.\n");
    exit(-1);
  }
  free(ptr);
}

end

alloy c extern_type Loop => lean_uv_loop_t := {
  foreach := `Null_foreach
  finalize := `Loop_finalize
}

alloy c extern "lean_uv_mk_loop"
def mkLoop : BaseIO Loop := {
  lean_uv_loop_t* ptr = checked_malloc(sizeof(lean_uv_loop_t));
  int err = uv_loop_init(&ptr->uv_val);
  if (err < 0) {
    fprintf(stderr, "uv_loop_init failed (error = %d).\n", err);
    exit(-1);
  }
  lean_object* r = to_lean<Loop>(ptr);
  ptr->lean_obj = r;
  return lean_io_result_mk_ok(r);
}

namespace Loop

alloy c extern "lean_uv_run"
def run (l : @& Loop) : BaseIO Bool := {
  bool stillActive = uv_run(&of_lean<Loop>(l)->uv_val, UV_RUN_DEFAULT) != 0;
  return lean_io_result_mk_ok(lean_bool(stillActive));
}

alloy c extern "lean_uv_run_once"
def run_once (l : Loop) : BaseIO Unit := {
  bool callbacksExpected = uv_run(&of_lean<Loop>(l)->uv_val, UV_RUN_ONCE);
  return lean_io_result_mk_ok(lean_bool(callbacksExpected));
}

/--
Poll the event loop, but doesn't block if there are no pending callbacks.


-/
alloy c extern "lean_uv_run_nowait"
def run_nowait (l : @& Loop) : BaseIO Bool := {
  bool callbacksExpected = uv_run(&of_lean<Loop>(l)->uv_val, UV_RUN_NOWAIT);
  return lean_io_result_mk_ok(lean_bool(callbacksExpected));
}

end Loop

alloy c section

struct lean_uv_idle_s {
  uv_idle_t idle;
  lean_object* r;
};

typedef struct lean_uv_idle_s lean_uv_idle_t;

/* Return callback associated with idler */
static lean_object* idler_callback(lean_uv_idle_t* p) {
  return p->idle.data;
}

/* Return lean object representing this idler */
static lean_object* idler_object(lean_uv_idle_t* p) {
  return p->r;
}

static void Idle_foreach(void* ptr, b_lean_obj_arg f) {
  lean_uv_idle_t* idler = (lean_uv_idle_t*) ptr;
  lean_apply_1(f, idler_callback(idler));
}

static void idle_close_cb(uv_handle_t* handle) {
  lean_uv_idle_t* idler = (lean_uv_idle_t*) handle;
  lean_dec(idler_callback(idler));

  lean_uv_loop_t* loopPtr = (lean_uv_loop_t*) idler->idle.loop;
  lean_dec(loopPtr->lean_obj);

  free(handle);
}

static void Idle_finalize(void* ptr) {
  uv_close((uv_handle_t*) ptr, &idle_close_cb);
}

static void idle_invoke_callback(uv_idle_t* handle) {
  lean_uv_idle_t* idler = (lean_uv_idle_t*) handle;
  // Get callback and idler handler objects
  lean_object* cb = idler_callback(idler);
  lean_object* o = idler_object(idler);
  // Increment reference counts to both prior to application.
  lean_inc(cb);
  lean_inc(o);
  lean_object* r = lean_apply_2(cb, o, lean_box(0));
  lean_dec(r);
}

end

alloy c extern_type Idle => lean_uv_idle_t := {
  foreach := `Idle_foreach
  finalize := `Idle_finalize
}

alloy c extern "lean_uv_idle_init"
def mkIdle (loop : Loop) : BaseIO Idle := {
  lean_uv_idle_t* idler = malloc(sizeof(lean_uv_idle_t));
  idler->idle.data = 0;
  lean_object* r = to_lean<Idle>(idler);
  idler->r = r;
  lean_uv_loop_t* loopPtr = of_lean<Loop>(loop);
  uv_idle_init(&loopPtr->uv_val, &idler->idle);
  return lean_io_result_mk_ok(r);
}

namespace Idle

alloy c extern "lean_uv_idle_start"
def start (r : Idle) (cb : Idle → BaseIO Unit) : BaseIO Unit := {
  lean_uv_idle_t* idler = lean_get_external_data(r);
  idler->idle.data = cb;
  uv_idle_start(&idler->idle, &idle_invoke_callback);
  return lean_io_result_mk_ok(lean_box(0));
}

def start2 (loop : Loop) (cb : Idle → BaseIO Unit) : BaseIO Idle := do
  let r ← mkIdle loop
  r.start cb
  pure r

alloy c extern "lean_uv_idle_stop"
def stop (h : @& Idle) : BaseIO Unit := {
  lean_uv_idle_t* idler = lean_get_external_data(h);
  uv_idle_stop(&idler->idle);
  lean_dec(h);
  return lean_io_result_mk_ok(lean_box(0));
}

end Idle

end UV

def hello := "world"
