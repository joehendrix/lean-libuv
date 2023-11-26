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
  lean_uv_timer_t* t = (lean_uv_timer_t*) timer;
  assert(t->callback != 0);
  lean_inc(t->callback);
  lean_object* r = lean_apply_1(t->callback, lean_box(0));
  check_callback_result(timer_handle(t), r);
}
end

alloy c extern_type Timer => lean_uv_timer_t := {
  foreach  := `Timer_foreach
  finalize := `Timer_finalize
}

alloy c extern "lean_uv_timer_init"
def Loop.mkTimer (loop : Loop) : BaseIO Timer := {
  lean_uv_timer_t* timer = checked_malloc(sizeof(lean_uv_timer_t));
  lean_object* r = to_lean<Timer>(timer);
  *handle_object(timer_handle(timer)) = r;
  timer->callback = 0;
  uv_timer_init(of_loop(loop), &timer->uv);
  return lean_io_result_mk_ok(r);
}

namespace Timer

alloy c extern "lean_uv_timer_start"
def start (timer : Timer) (timeout repeat_timeout : UInt64) (callback : IO Unit) : IO Unit := {
  lean_uv_timer_t* l = of_lean<Timer>(timer);
  if (l->callback) {
    lean_dec(timer);
    lean_dec(callback);
    return invalid_argument("Timer.start already called.");
  }
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
    l->callback = 0;
    lean_dec(timer);
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
  return lean_io_result_mk_ok(lean_box_uint64(r));
}

/-- Get the timer repeat value. -/
alloy c extern "lean_uv_get_due_in"
def getDueIn (timer : @&Timer) : BaseIO UInt64 := {
  lean_uv_timer_t* l = of_lean<Timer>(timer);
  uint64_t r = uv_timer_get_due_in(&l->uv);
  return lean_io_result_mk_ok(lean_box_uint64(r));
}

def timerCB (l : UV.Loop) : IO Unit := do
  IO.println s!"In Callback {←l.now}"
