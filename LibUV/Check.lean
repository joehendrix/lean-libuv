import LibUV.Loop

open scoped Alloy.C
alloy c include <lean_uv.h>

namespace UV

alloy c section

/* Return lean object representing this check */
static uv_handle_t* check_handle(uv_check_t* p) {
  return (uv_handle_t*) p;
}

/* Return lean object representing this check */
static lean_object** check_callback(uv_check_t* p) {
  return handle_object(check_handle(p));
}

static void Check_foreach(void* ptr, b_lean_obj_arg f) {
  uv_check_t* check = (uv_check_t*) ptr;
  lean_object* cb = *check_callback(check);
  if (cb)
    lean_apply_1(f, cb);
}

static void check_close_cb(uv_check_t* check) {
  lean_object* cb = *check_callback(check);
  if (cb) lean_dec(cb);
  free_handle(check_handle(check));
}

static void Check_finalize(void* ptr) {
  uv_close((uv_handle_t*) ptr, (uv_close_cb) &check_close_cb);
}

static void check_invoke_callback(uv_check_t* check) {  // Get callback and handler objects
  lean_object* cb = *check_callback(check);
  lean_inc(cb);
  check_callback_result(check_handle(check), lean_apply_1(cb, lean_box(0)));
}
end

alloy c extern_type Check => uv_check_t := {
  foreach  := `Check_foreach
  finalize := `Check_finalize
}

alloy c extern "lean_uv_check_init"
def Loop.mkCheck (loop : Loop) : BaseIO Check := {
  uv_check_t* check = checked_malloc(sizeof(uv_check_t));
  lean_object* r = to_lean<Check>(check);
  uv_check_init(of_loop(loop), check);
  *check_callback(check) = 0;
  return lean_io_result_mk_ok(r);
}

/--
Start invoking the callback on the loop.
-/
alloy c extern "lean_uv_check_start"
def Check.start (r : @&Check) (callback : IO Unit) : IO Unit := {
  uv_check_t* check = lean_get_external_data(r);
  lean_object** cb = check_callback(check);
  if (*cb) {
    uv_check_stop(check);
    lean_dec(*cb);
  }
  *cb = callback;
  uv_check_start(check, &check_invoke_callback);
  return lean_io_unit_result_ok();
}

/--
Stop invoking the check handler.
-/
alloy c extern "lean_uv_check_stop"
def Check.stop (h : @&Check) : BaseIO Unit := {
  uv_check_t* check = lean_get_external_data(h);
  lean_object** cb = check_callback(check);
  if (*cb) {
    uv_check_stop(check);
    lean_dec(*cb);
    *cb = 0;
  }
  return lean_io_unit_result_ok();
}
