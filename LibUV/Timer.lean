import LibUV.Loop

open scoped Alloy.C
alloy c include <lean_uv.h>

namespace UV

alloy c section

struct lean_uv_timer_s {
  uv_timer_t uv;
  lean_object* callback; // Callback for timer event
};

typedef struct lean_uv_timer_s lean_uv_timer_t;

static void Timer_foreach(void* ptr, b_lean_obj_arg f) {
  fatal_st_only("Timer");
}

// Close the check handle if the loop stops
void lean_uv_timer_loop_stop(uv_handle_t* h) {
  lean_uv_timer_t* timer = (lean_uv_timer_t*) h;
  lean_dec_optref(timer->callback);
  uv_close(h, (uv_close_cb) &free);
}

static void Timer_finalize(void* ptr) {
  bool is_active = ((lean_uv_timer_t*) ptr)->callback != NULL;
  lean_uv_finalize_handle((uv_handle_t*) ptr, is_active);
}

static void timer_callback(uv_timer_t* timer) {
  lean_uv_timer_t* t = (lean_uv_timer_t*) timer;
  assert(t->callback != 0);
  lean_inc(t->callback);
  check_callback_result(t->uv.loop, lean_apply_1(t->callback, lean_io_mk_world()));
}
end

alloy c extern_type Timer => lean_uv_timer_t := {
  foreach  := `Timer_foreach
  finalize := `Timer_finalize
}

alloy c extern "lean_uv_timer_init"
def Loop.mkTimer (loop : Loop) : UV.IO Timer := {
  lean_uv_timer_t* timer = checked_malloc(sizeof(lean_uv_timer_t));
  lean_object* r = to_lean<Timer>(timer);
  timer->uv.data = r;
  timer->callback = 0;

  int ec = uv_timer_init(of_loop(loop), &timer->uv);
  if (ec < 0)
    fatal_error("uv_timer_init failed (error = ec)\n", ec);
  return lean_io_result_mk_ok(r);
}

namespace Timer

alloy c extern "lean_uv_timer_start"
def start (timer : @&Timer) (timeout repeat_timeout : UInt64) (callback : UV.IO Unit) : UV.IO Unit := {
  lean_uv_timer_t* l = of_lean<Timer>(timer);
  if (l->callback) {
    lean_dec(callback);
    return lean_uv_io_error(UV_EINVAL);
  }
  l->callback = callback;
  if (uv_timer_start(&l->uv, &timer_callback, timeout, repeat_timeout) != 0) {
    fatal_error("uv_timer_start failed\n");
  }
  return lean_io_result_mk_ok(lean_unit());
}

alloy c extern "lean_uv_timer_stop"
def stop (timer : @&Timer) : UV.IO Unit := {
  lean_uv_timer_t* l = of_lean<Timer>(timer);
  if (l->callback == 0) {
    return lean_io_unit_result_ok();
  }
  lean_dec(l->callback);
  l->callback = 0;
  if (uv_timer_stop(&l->uv) != 0) {
    fatal_error("uv_timer_stop failed¬");
  }
  return lean_io_unit_result_ok();
}

/--
Stop the timer, and if it is repeating restart it using the
repeat value as the timeout. If the timer has never been
started before it returns UV_EINVAL.
-/
alloy c extern "lean_uv_timer_again"
def again (timer : @&Timer) : UV.IO Unit := {
  lean_uv_timer_t* l = of_lean<Timer>(timer);
  if (l->callback == 0) {
    return lean_uv_io_error(UV_EINVAL);
  }

  if (uv_timer_again(&l->uv) != 0) {
    fatal_error("uv_timer_again failed.");
  }
  return lean_io_unit_result_ok();
}

/--
Set the repeat interval value in milliseconds.
The timer will be scheduled to run on the given interval,
regardless of the callback execution duration, and will follow
normal timer semantics in the case of a time-slice overrun.
-/
alloy c extern "lean_uv_set_repeat"
def setRepeat (timer : @&Timer) (repeat_timeout : UInt64) : UV.IO Unit := {
  lean_uv_timer_t* l = of_lean<Timer>(timer);
  uv_timer_set_repeat(&l->uv, repeat_timeout);
  return lean_io_unit_result_ok();
}

/-- Get the timer repeat value. -/
alloy c extern "lean_uv_get_repeat"
def getRepeat (timer : @&Timer) : UV.IO UInt64 := {
  lean_uv_timer_t* l = of_lean<Timer>(timer);
  uint64_t r = uv_timer_get_repeat(&l->uv);
  return lean_io_result_mk_ok(lean_box_uint64(r));
}

/-- Get the timer repeat value. -/
alloy c extern "lean_uv_get_due_in"
def getDueIn (timer : @&Timer) : UV.IO UInt64 := {
  lean_uv_timer_t* l = of_lean<Timer>(timer);
  uint64_t r = uv_timer_get_due_in(&l->uv);
  return lean_io_result_mk_ok(lean_box_uint64(r));
}
