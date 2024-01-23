import LibUV.Loop

open scoped Alloy.C
alloy c include <stdlib.h> <lean_uv.h>

namespace UV

/--
This is a low-level function for adding a new task to the global work
queue which maintains a list of work items where each work item has a
`value` with some type `α` and an `action` with type `α → BaseIO (Option
α)`.  When a worker thread is idle, it will wait for a work item that it
can remove from the stack, and then runs `action value`.  The worker
thread then pushes a new entry to the worker item queue containing the
value returned and original action.

The queue work function is designed to be as simple as possible while
providing high performance and a mechanism for reducing the number of
objects that must be marked as multi-threaded.  In particular, the
initial value `init` passed to `queue_work` must be marked as
multi-threaded, but subsequent values returned by `work_cb` can be
single threaded as long as they are not otherwise shared among threads.

The `action` passed into `queue_work` should ideally do enough work so
that multi-threaded overhead is insignificant, but not so much work that
worker threads get locked into a single task.  To ensure fairness,
long-running tasks should periodically return with a new state and then
resume.  We provide no mechanism for sending a single to a worker thread
with an action that takes too long.  Terminating threads in a
non-cooperative way (e.g., via a signal) is fraught since threads may be
holding arbitrary resources and unlike processes, there is no mechanism
to free those resources automatically when the thread terminates.
-/
@[extern "lean_queue_work"]
opaque queue_work {α} (init : α) (action : α → BaseIO (Array α)) : BaseIO Unit

--Init function that launches workers
--function to push new iterms
--Worker function that initializes


alloy c section


lean_obj_res lean_queue_work(lean_obj_arg initObj, lean_obj_arg actionObj,  b_lean_obj_arg _rw) {


  uv_once(&work_class_once, initWorkClass);
  uv_loop_t* loop = lean_get_external_data(loopObj);
  lean_uv_work_t* req = checked_malloc(sizeof(lean_uv_work_t));
  lean_mark_mt(work_cb);
  req->work_cb = work_cb;
  int ec = uv_queue_work(loop, &req->uv, lean_uv_work_cb, lean_uv_after_work_cb);
  if (ec < 0) {
    lean_dec_ref(work_cb);
    lean_dec_ref(after_work_cb);
    free(req);
    fatal_error("uv_shutdown_req failed (error = %d)", ec);
  }
  lean_object* reqObj = lean_alloc_external(work_class, req);
  req->after_work_cb = after_work_cb;
  req->uv.data = reqObj;
  return lean_io_result_mk_ok(reqObj);
}


end

section Collector

opaque NonemptyCollector : NonemptyType.{0}

/-- A shutdown request -/
structure Collector (α : Type) : Type where
  ref : NonemptyCollector.type

instance : Nonempty (Collector α) :=
  Nonempty.intro { ref := Classical.choice NonemptyCollector.property }

/--
A collector is a variant of a signal that allows the value stored to be updated, and
one may trigger the loop during updates.
-/
@[extern "lean_uv_mk_collector"]
opaque Loop.mkCollector (l : Loop) (init : α) (action : α → UV.IO Unit) : BaseIO (Collector α)

/- Trigger the signal with the given element. -/
@[extern "lean_uv_collector_modify"]
opaque Collector.modify (s : Collector α) (update : α → α × Bool) : UV.IO Unit

end Collector

section Signal

def Signal (α:Type) := Collector (Array α)

instance : Nonempty (Signal α) := by
  unfold Signal
  exact inferInstance

/--
Create a signal object that runs the action whenever a value is sent when the loop
is run.
-/
def Loop.mkSignal (l : Loop) (action : α → UV.IO Unit) : BaseIO (Signal α) :=
  l.mkCollector #[] (·.forM action)

/- Trigger the signal with the given element. -/
def Signal.send (s : Signal α) (v : α) : UV.IO Unit := do
  Collector.modify s (·.push v, true)

end Signal

/-- References -/
opaque WorkPointed : NonemptyType.{0}

/-- A shutdown request -/
structure Work : Type where
  ref : WorkPointed.type

instance : Nonempty Work :=
  Nonempty.intro { ref := Classical.choice WorkPointed.property }

alloy c section
/*
The external data of a ShutdownReq in Lean is a lean_uv_shutdown_t req where:

  req.uv.handle is a pointer to a uv_stream_t.
  req.uv.data is a pointer to the Lean shutdown_req object.  This is set
    to null if the shutdown request memory is released.
  req.callback is a pointer to the callback to invoke when the shutdown completes.
  This is set to null after the callback returns.
*/
struct lean_uv_work_s {
  uv_work_t uv;
  // Callback until work_cb is called and work result to pass to after_work_cb if it is done.
  lean_object* work_cb;
  // Callback to run after work completes or null after work is all done.
  lean_object* after_work_cb;
};

typedef struct lean_uv_work_s lean_uv_work_t;

static void Work_foreach(void* ptr, b_lean_obj_arg f) {
}

static void Work_finalize(void* ptr) {
  lean_uv_work_t* req = (lean_uv_work_t*) ptr;
  if (req->after_work_cb) {
    req->uv.data = 0;
  } else {
    free(req);
  }
}

static uv_once_t work_class_once = UV_ONCE_INIT;
static lean_external_class* work_class = NULL;

static void initWorkClass(void) {
  work_class = lean_register_external_class(Work_finalize, Work_foreach);
}
end


@[extern "lean_uv_work_cancel"]
opaque Work.cancel (work : @&Work) : UV.IO Unit
-- TODO: Implement me



/--
Queue a work item
-/
@[extern "lean_uv_queue_work2"]
opaque Loop.queue_work (loop : @&Loop) (work_cb : UV.IO α) (after_work_cb : Except UV.Error α → UV.IO Unit) : UV.IO Work

alloy c section

LEAN_EXPORT void lean_init_thread_heap(void);

static void lean_uv_work_cb(uv_work_t *req) {
  lean_init_thread_heap();
  lean_uv_work_t* lreq = (lean_uv_work_t*) req;
  lean_object* cb = lreq->work_cb;
  lreq->work_cb = lean_apply_1(cb, lean_io_mk_world());
}

static void lean_uv_after_work_cb(uv_work_t *req, int status) {
  lean_uv_work_t* lreq = (lean_uv_work_t*) req;
  uv_loop_t* loop = req->loop;
  lean_object* cb = lreq->after_work_cb;
  lean_object* result;
  if (status >= 0) {
    lean_object* res = lreq->work_cb;
    unsigned tag = 1 - lean_ptr_tag(res);
    result = lean_alloc_ctor(tag, 1, 0);
    lean_object* val = lean_ctor_get(res, 0);
    lean_inc(val);
    lean_dec_ref(res);
    lean_ctor_set(result, 0, val);
  } else if (status == UV_ECANCELED) {
    result = lean_alloc_ctor(0, 1, 0);
    lean_ctor_set(result, 0, lean_box(LUV_ECANCELED));
  } else {
    fatal_error("lean_uv_after_work_cb had unexpected failure %d.\n", status);
  }
  if (req->data != 0) {
    req->after_work_cb = 0;
  } else {
    free(req);
  }
  check_callback_result(loop, lean_apply_2(cb, result, lean_io_mk_world()));
}

lean_obj_res lean_uv_queue_work2(b_lean_obj_arg loopObj, lean_obj_arg work_cb, lean_obj_arg after_work_cb, b_lean_obj_arg _rw) {
  uv_once(&work_class_once, initWorkClass);
  uv_loop_t* loop = lean_get_external_data(loopObj);
  lean_uv_work_t* req = checked_malloc(sizeof(lean_uv_work_t));
  lean_mark_mt(work_cb);
  req->work_cb = work_cb;
  int ec = uv_queue_work(loop, &req->uv, lean_uv_work_cb, lean_uv_after_work_cb);
  if (ec < 0) {
    lean_dec_ref(work_cb);
    lean_dec_ref(after_work_cb);
    free(req);
    fatal_error("uv_shutdown_req failed (error = %d)", ec);
  }
  lean_object* reqObj = lean_alloc_external(work_class, req);
  req->after_work_cb = after_work_cb;
  req->uv.data = reqObj;
  return lean_io_result_mk_ok(reqObj);
}
end
