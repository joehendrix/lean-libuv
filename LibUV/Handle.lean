import LibUV.Check
import LibUV.Idle
import LibUV.Stream
import LibUV.Timer

open scoped Alloy.C
alloy c include <stdlib.h> <uv.h> <lean/lean.h> <lean_uv.h>

namespace UV

inductive Handle where
  | check : Check -> Handle
  | idle  : Idle  -> Handle
  | tcp   : TCP   -> Handle
  | timer : Timer -> Handle

alloy c section

extern lean_object* lean_uv_handle_id(lean_object* h) {
  return h;
}

static lean_object* lean_uv_handle_rec(
    lean_object* check,
    lean_object* idle,
    lean_object* tcp,
    lean_object* timer,
    lean_object* h) {
  uv_handle_t* hdl = (uv_handle_t *) lean_get_external_data(h);
  switch (hdl->type) {
  case  UV_CHECK:
    return lean_apply_1(check, h);
  case UV_IDLE:
    return lean_apply_1(idle, h);
  case UV_TCP:
    return lean_apply_1(tcp, h);
  case UV_TIMER:
    return lean_apply_1(timer, h);
  default:
    fatal_error("Unsupported type %d\n", hdl->type);
  }
}

end

attribute [extern "lean_uv_handle_id"] Handle.check
attribute [extern "lean_uv_handle_id"] Handle.idle
attribute [extern "lean_uv_handle_id"] Handle.tcp
attribute [extern "lean_uv_handle_id"] Handle.timer
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
