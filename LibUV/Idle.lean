import LibUV.Loop

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
static uv_handle_t* idle_handle(lean_uv_idle_t* p) {
  return (uv_handle_t*) &(p->uv);
}

/* Return callback associated with idler */
static lean_object** idle_callback(lean_uv_idle_t* p) {
  return &(p->callback);
}

static void Idle_foreach(void* ptr, b_lean_obj_arg f) {
  fatal_st_only("Idle");
}

static void Idle_finalize(void* ptr) {
  lean_uv_idle_t* idle = ptr;
  assert((idle->callback != null) == uv_is_active((uv_handle_t*) idle));
  if (idle->callback) {
    idle->uv.data = 0;
  } else {
    uv_close((uv_handle_t*) ptr, (uv_close_cb) free);
  }
  // Release loop object.  Note that this may free the loop object
  lean_dec(loop_object(idle->uv.loop));
}

static void idle_invoke_callback(uv_idle_t* idle) {
  lean_uv_idle_t* luv_idle = (lean_uv_idle_t*) idle;
  lean_object* cb = luv_idle->callback;
  lean_inc(cb);
  check_callback_result(luv_idle->uv.loop, lean_apply_1(cb, lean_box(0)));
}

end

alloy c extern_type Idle => lean_uv_idle_t := {
  foreach := `Idle_foreach
  finalize := `Idle_finalize
}

alloy c extern "lean_uv_idle_init"
def Loop.mkIdle (loop : Loop) : UV.IO Idle := {
  lean_uv_idle_t* idle = checked_malloc(sizeof(lean_uv_idle_t));
  uv_idle_init(of_loop(loop), &idle->uv);
  idle->callback = 0;
  lean_object* r = to_lean<Idle>(idle);
  idle->uv.data = r;
  return lean_io_result_mk_ok(r);
}

/--
Start invoking the callback on the idle loop.
-/
alloy c extern "lean_uv_idle_start"
def Idle.start (idle : @&Idle) (callback : UV.IO Unit) : UV.IO Unit := {
  lean_uv_idle_t* luv_idle = lean_get_external_data(idle);
  if (luv_idle->callback != 0) {
    lean_dec(luv_idle->callback);
  } else {
    uv_idle_start(&luv_idle->uv, (uv_idle_cb) &idle_invoke_callback);
  }
  luv_idle->callback = callback;
  return lean_io_unit_result_ok();
}

/--
Stop invoking the idle handler.
-/
alloy c extern "lean_uv_idle_stop"
def Idle.stop (idle : @& Idle) : BaseIO Unit := {
  lean_uv_idle_t* luv_idle = lean_get_external_data(idle);
  if (luv_idle->callback != 0) {
    uv_idle_stop(&luv_idle->uv);
    lean_dec(luv_idle->callback);
    luv_idle->callback = 0;
  }
  return lean_io_unit_result_ok();
}
