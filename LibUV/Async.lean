import LibUV.Loop

open scoped Alloy.C
alloy c include <lean_uv.h>

namespace UV

alloy c section

struct lean_uv_async_s {
  uv_async_t async;
  // Lean function to invoke callback on.
  // Initialized to be valid object.
  lean_object* callback;
};

typedef struct lean_uv_async_s lean_uv_async_t;

/* Return lean object representing this idler */
static uv_handle_t* async_handle(lean_uv_async_t* p) {
  return (uv_handle_t*) &(p->async);
}

static void Async_foreach(void* ptr, b_lean_obj_arg f) {
  lean_uv_async_t* async = (lean_uv_async_t*) ptr;
  lean_apply_1(f, async->callback);
}

static void async_close_cb(lean_uv_async_t* async) {
  lean_dec(async->callback);
  free_handle(async_handle(async));
}

static void Async_finalize(void* ptr) {
  uv_close((uv_handle_t*) ptr, (uv_close_cb) &async_close_cb);
}

static void async_invoke_callback(lean_uv_async_t* async) {
  // Get callback and async handler objects
  lean_object* cb = async->callback;
  lean_object* o = *handle_object(async_handle(async));
  // Increment reference counts to both prior to application.
  lean_inc(cb);
  lean_inc(o);
  // Invoke and discard result.
  lean_object* r = lean_apply_2(cb, o, lean_box(0));
  check_callback_result(async_handle(async), r);
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
def Loop.mkAsync (loop : Loop) (callback : Async → IO Unit) : BaseIO Async := {
  lean_uv_async_t* async = checked_malloc(sizeof(lean_uv_async_t));
  lean_object* r = to_lean<Async>(async);
  *handle_object(async_handle(async)) = r;
  async->callback = callback;
  uv_async_init(of_loop(loop), &async->async, (uv_async_cb) &async_invoke_callback);
  return lean_io_result_mk_ok(r);
}

namespace Async

alloy c extern "lean_uv_async_send"
def send (async : @& Async) : IO Unit := {
  lean_uv_async_t* lasync = of_lean<Async>(async);

  if (uv_is_closing(async_handle(lasync))) {
    return invalid_argument("Async.send called on a closing handle.");
  }
  int r = uv_async_send(&lasync->async);
  if (r != 0) {
    fatal_error("uv_async_send failed (error = %d)\n", r);
  }
  return lean_io_unit_result_ok();
}
