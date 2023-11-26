import LibUV.Basic

open scoped Alloy.C
alloy c include <lean_uv.h>

namespace UV

alloy c section

struct lean_uv_timer_s {
  uv_timer_t uv;
  lean_object* callback; // Callback for timer event
};

typedef struct lean_uv_timer_s lean_uv_timer_t;

/* Return lean object representing this check */
static uv_handle_t* timer_handle(lean_uv_timer_t* p) {
  return (uv_handle_t*) p;
}

static void Timer_foreach(void* ptr, b_lean_obj_arg f) {
  lean_uv_timer_t* l = (lean_uv_timer_t*) ptr;
  if (l->callback)
    lean_apply_1(f, l->callback);
}

static void timer_close_cb(uv_handle_t* h) {
  lean_uv_timer_t* l = (lean_uv_timer_t*) h;
  if (l->callback != 0)
    lean_dec(l->callback);
  free_handle(h);
}

static void Timer_finalize(void* ptr) {
  uv_close((uv_handle_t*) ptr, &timer_close_cb);
}

static void timer_callback(uv_timer_t* timer) {
  lean_uv_timer_t* l = (lean_uv_timer_t*) timer;
  assert(l->callback != 0);
  lean_apply_1(l->callback, lean_box(0));
}

lean_obj_res lean_uv_raise_invalid_argument(lean_obj_arg msg, lean_obj_arg _s);

static
lean_obj_res invalid_argument(const char* msg) {
  return lean_uv_raise_invalid_argument(lean_mk_string(msg), lean_unit());
}

end

alloy c extern_type Timer => lean_uv_timer_t := {
  foreach  := `Timer_foreach
  finalize := `Timer_finalize
}

alloy c extern "lean_uv_timer_init"
def Loop.mkTimer (loop : Loop) : BaseIO Timer := {
  lean_uv_timer_t* timer = malloc(sizeof(lean_uv_timer_t));
  lean_object* r = to_lean<Timer>(timer);
  *handle_object(timer_handle(timer)) = r;
  timer->callback = 0;

  uv_timer_init(of_loop(loop), &timer->uv);
  return lean_io_result_mk_ok(r);
}

namespace Timer

alloy c extern "lean_uv_timer_start"
def start (timer : Timer) (callback : BaseIO Unit) (timeout repeat_timeout : UInt64) : BaseIO Unit := {
  lean_uv_timer_t* l = of_lean<Timer>(timer);
  if (l->callback)
    fatal_error("Timer.start already called¬");
  l->callback = callback;
  if (uv_timer_start(&l->uv, &timer_callback, timeout, repeat_timeout) != 0)
    fatal_error("uv_timer_start failed\n");
  return lean_io_unit_result_ok();
}

alloy c extern "lean_uv_timer_stop"
def stop (timer : @&Timer) : BaseIO Unit := {
  lean_uv_timer_t* l = of_lean<Timer>(timer);
  if (uv_timer_stop(&l->uv) != 0) {
    fatal_error("uv_timer_stop failed¬");
  }
  if (l->callback) {
    lean_dec(l->callback);
    lean_dec(*handle_object(timer_handle(l)));
    l->callback = 0;
  }
  return lean_io_unit_result_ok();
}

/--
Stop the timer, and if it is repeating restart it using the
repeat value as the timeout. If the timer has never been
started before it returns UV_EINVAL.
-/
alloy c extern "lean_uv_timer_again"
def again (timer : @&Timer) : IO Unit := {
  lean_uv_timer_t* l = of_lean<Timer>(timer);
  if (l->callback == 0)
    return invalid_argument("again called on timer that has not been invoked.");

  if (uv_timer_again(&l->uv) != 0) {
    fatal_error("uv_timer_again failed.¬");
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
def setRepeat (timer : @&Timer) (repeat_timeout : UInt64) : IO Unit := {
  lean_uv_timer_t* l = of_lean<Timer>(timer);
  uv_timer_set_repeat(&l->uv, repeat_timeout);
  return lean_io_unit_result_ok();
}

/-- Get the timer repeat value. -/
alloy c extern "lean_uv_get_repeat"
def getRepeat (timer : @&Timer) : BaseIO UInt64 := {
  lean_uv_timer_t* l = of_lean<Timer>(timer);
  uint64_t r = uv_timer_get_repeat(&l->uv);
  return lean_io_result_mk_ok(lean_uint64_to_nat(r));
}

/-- Get the timer repeat value. -/
alloy c extern "lean_uv_get_due_in"
def getDueIn (timer : @&Timer) : BaseIO UInt64 := {
  lean_uv_timer_t* l = of_lean<Timer>(timer);
  uint64_t r = uv_timer_get_due_in(&l->uv);
  return lean_io_result_mk_ok(lean_uint64_to_nat(r));
}
