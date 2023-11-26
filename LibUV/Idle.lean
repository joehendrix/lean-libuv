import LibUV.Basic

open scoped Alloy.C
alloy c include <lean_uv.h>

namespace UV

alloy c section

struct lean_uv_idle_s {
  uv_idle_t uv;
  // callback object
  lean_object* callback;
};

typedef struct lean_uv_idle_s lean_uv_idle_t;

/* Return lean object representing this idler */
static uv_handle_t* idler_handle(lean_uv_idle_t* p) {
  return (uv_handle_t*) &(p->uv);
}

/* Return callback associated with idler */
static lean_object** idler_callback(lean_uv_idle_t* p) {
  return &(p->callback);
}

static void Idle_foreach(void* ptr, b_lean_obj_arg f) {
  lean_uv_idle_t* idler = (lean_uv_idle_t*) ptr;
  if (idler->callback)
    lean_apply_1(f, idler->callback);
}

static void idle_close_cb(lean_uv_idle_t* idler) {
  if (idler->callback != 0)
    lean_dec(idler->callback);
  free_handle(idler_handle(idler));
}

static void Idle_finalize(void* ptr) {
  uv_close((uv_handle_t*) ptr, (uv_close_cb) &idle_close_cb);
}

static void idle_invoke_callback(lean_uv_idle_t* idler) {
  // Get callback and idler handler objects
  lean_object* cb = idler->callback;
  // Increment reference counts to both prior to application.
  lean_inc(cb);
  // Invoke and discard result.
  lean_dec(lean_apply_1(cb, lean_box(0)));
}

end

alloy c extern_type Idle => lean_uv_idle_t := {
  foreach := `Idle_foreach
  finalize := `Idle_finalize
}

alloy c extern "lean_uv_idle_init"
def Loop.mkIdle (loop : Loop) : BaseIO Idle := {
  lean_uv_idle_t* idler = malloc(sizeof(lean_uv_idle_t));
  uv_idle_init(of_loop(loop), &idler->uv);
  idler->callback = 0;
  lean_object* r = to_lean<Idle>(idler);
  *handle_object(idler_handle(idler)) = r;
  return lean_io_result_mk_ok(r);
}

/--
Start invoking the callback on the idle loop.
-/
alloy c extern "lean_uv_idle_start"
def Idle.start (r : Idle) (callback : BaseIO Unit) : BaseIO Unit := {
  lean_uv_idle_t* idler = lean_get_external_data(r);
  // TODO: Figure out if we should just set callback.
  if (idler->callback != 0)
    fatal_error("Idle callback already set.");
  idler->callback = callback;

  uv_idle_start(&idler->uv, (uv_idle_cb) &idle_invoke_callback);
  return lean_io_unit_result_ok();
}

/--
Stop invoking the idle handler.
-/
alloy c extern "lean_uv_idle_stop"
def Idle.stop (h : @& Idle) : BaseIO Unit := {
  lean_uv_idle_t* idler = lean_get_external_data(h);
  uv_idle_stop(&idler->uv);
  if (idler->callback != 0) {
    lean_dec(idler->callback);
    idler->callback = 0;
  }
  // Decrement handle since loop may not call it.
  lean_dec(h);
  return lean_io_unit_result_ok();
}
