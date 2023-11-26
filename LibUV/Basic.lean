import Alloy.C

open scoped Alloy.C

def NonemptyProp := Subtype fun α : Prop => Nonempty α

instance : Inhabited NonemptyProp := ⟨⟨PUnit, ⟨⟨⟩⟩⟩⟩

/-- The underlying type of a `NonemptyType`. -/
abbrev NonemptyProp.type (type : NonemptyProp) : Prop := type.val

alloy c include <stdlib.h> <lean_uv.h>

namespace UV

alloy c section

static void Null_foreach(void* ptr, b_lean_obj_arg f) {
}
end

private def EINVAL : UInt32 := 22

/--
Report an error that occurred because a function was passed an argument
that was in a unsupported state.

These always represent program bugs.  The function condition could have
been checked beforehand.
-/
@[export lean_uv_raise_invalid_argument]
private def raiseInvalidArgument (message:String) : IO Unit :=
  throw <| IO.Error.invalidArgument none EINVAL message

section Loop

alloy c section

static void Loop_finalize(void* ptr) {
  uv_loop_t* l = (uv_loop_t*) ptr;
  int r = uv_loop_close(l);
  if (r < 0)
    fatal_error("libuv loop finalize called before resources free.\n");
  free(ptr);
}

end

alloy c extern_type Loop => uv_loop_t := {
  foreach := `Null_foreach
  finalize := `Loop_finalize
}

/--
Options to control configure Loop at startup.
-/
structure Loop.Options where
  /--
  Loop metrics will accumulate idle time for reporting later.
  -/
  accumulateIdleTime : Bool := False
  /--
  Block SIGProf signal when polling for new events.
  -/
  blockSigProfSignal : Bool := False

alloy c extern "lean_uv_mk_loop"
def mkLoop (options : Loop.Options := {}) : BaseIO Loop := {
  uv_loop_t* loop = checked_malloc(sizeof(uv_loop_t));
  int err = uv_loop_init(loop);
  if (err < 0)
    fatal_error("uv_loop_init failed (error = %d).\n", err);
  lean_object* r = to_lean<Loop>(loop);
  *loop_object(loop) = r;

  bool accum = lean_ctor_get_uint8(options, 0);
  bool block = lean_ctor_get_uint8(options, 1);

  if (accum) {
    printf("accum\n");
    int err = uv_loop_configure(loop, UV_METRICS_IDLE_TIME);
    if (err != 0) {
      fatal_error("uv_loop_configure failed (error = %d).\n", err);
    }
  }
  if (block) {
    printf("block\n");
    int err = uv_loop_configure(loop, UV_LOOP_BLOCK_SIGNAL, SIGPROF);
    if (err != 0) {
      fatal_error("uv_loop_configure failed (error = %d).\n", err);
    }
  }

  return lean_io_result_mk_ok(r);
}

alloy c enum
  RunMode => uv_run_mode
  | Default => UV_RUN_DEFAULT
  | Once   => UV_RUN_ONCE
  | NoWait => UV_RUN_NOWAIT
  deriving Inhabited

namespace Loop

/--
This runs the loop until `stop` is called or there are no
more active and referenced handles or requests.  Returns true if there are still
active and referenced handles or requests.
-/
alloy c extern "lean_uv_run"
def run_aux (l : @& Loop) (mode : RunMode) : BaseIO Bool := {
  printf("Run\n");
  uv_run_mode lmode = of_lean<RunMode>(mode);
  bool stillActive = uv_run(of_lean<Loop>(l), lmode) != 0;
  return lean_io_result_mk_ok(lean_bool(stillActive));
}

def run (l : Loop) (mode : RunMode := RunMode.Default): BaseIO Bool := run_aux l mode

/--
Return true if the
-/
alloy c extern "lean_uv_alive"
def isAlive (l : @& Loop) : BaseIO Bool := {
  bool alive = uv_loop_alive(of_lean<Loop>(l)) != 0;
  return lean_io_result_mk_ok(lean_bool(alive));
}

alloy c extern "lean_uv_stop"
def stop (l : @& Loop) : BaseIO Unit := {
  uv_stop(of_lean<Loop>(l));
  return lean_io_unit_result_ok();
}

end Loop

end Loop

section Async

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
  lean_dec(lean_apply_2(cb, o, lean_box(0)));
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
def Loop.mkAsync (loop : Loop) (callback : Async → BaseIO Unit) : BaseIO Async := {
  lean_uv_async_t* async = malloc(sizeof(lean_uv_async_t));
  lean_object* r = to_lean<Async>(async);
  *handle_object(async_handle(async)) = r;
  async->callback = callback;
  uv_async_init(of_lean<Loop>(loop), &async->async, (uv_async_cb) &async_invoke_callback);
  return lean_io_result_mk_ok(r);
}

alloy c extern "lean_uv_async_send"
def Async.send (async : @& Async) : BaseIO Unit := {
  int r = uv_async_send(&of_lean<Async>(async)->async);
  if (r != 0) {
    fatal_error("uv_async_send failed (error = %d)\n", r);
  }
  return lean_io_unit_result_ok();
}

end Async

section Check

alloy c section

struct lean_uv_check_s {
  uv_check_t uv;
  lean_object* callback;
};

typedef struct lean_uv_check_s lean_uv_check_t;

/* Return lean object representing this check */
static uv_handle_t* check_handle(lean_uv_check_t* p) {
  return (uv_handle_t*) &(p->uv);
}

static void Check_foreach(void* ptr, b_lean_obj_arg f) {
  lean_uv_check_t* check = (lean_uv_check_t*) ptr;
  if (check->callback)
    lean_apply_1(f, check->callback);
}

static void check_close_cb(lean_uv_check_t* check) {
  if (check->callback)
    lean_dec(check->callback);
  free_handle(check_handle(check));
}

static void Check_finalize(void* ptr) {
  uv_close((uv_handle_t*) ptr, (uv_close_cb) &check_close_cb);
}
end

alloy c extern_type Check => lean_uv_check_t := {
  foreach  := `Check_foreach
  finalize := `Check_finalize
}

alloy c extern "lean_uv_check_init"
def Loop.mkCheck (loop : Loop) : BaseIO Check := {
  lean_uv_check_t* check = malloc(sizeof(lean_uv_check_t));
  lean_object* r = to_lean<Check>(check);
  uv_check_init(of_lean<Loop>(loop), &check->uv);
  *handle_object(check_handle(check)) = r;
  check->callback = 0;
  return lean_io_result_mk_ok(r);
}

alloy c section

static void check_invoke_callback(lean_uv_check_t* check) {
  // Get callback and handler objects
  lean_object* cb = check->callback;
  lean_object* o = *handle_object(check_handle(check));
  // Increment reference counts to both prior to application.
  lean_inc(cb);
  lean_inc(o);
  // Invoke and discard result.
  lean_dec(lean_apply_2(cb, o, lean_box(0)));
}

end

/--
Start invoking the callback on the loop.
-/
alloy c extern "lean_uv_check_start"
def Check.start (r : Check) (callback : Check → BaseIO Unit) : BaseIO Unit := {
  lean_uv_check_t* check = lean_get_external_data(r);
  if (check->callback)
    fatal_error("check already started.¬");
  check->callback = callback;
  if (uv_check_start(&check->uv, (uv_check_cb) &check_invoke_callback) != 0)
    fatal_error("uv_check_start failed.");
  return lean_io_unit_result_ok();
}

/--
Stop invoking the check handler.
-/
alloy c extern "lean_uv_check_stop"
def Check.stop (h : @&Check) : BaseIO Unit := {
  lean_uv_check_t* check = lean_get_external_data(h);
  uv_check_stop(&check->uv);
  lean_dec(h);
  return lean_io_unit_result_ok();
}

end Check

section Stream

opaque Stream.nonemptyProp (α : Type) : NonemptyProp

class Stream (α: Type) : Prop where
  phantom : NonemptyProp.type (Stream.nonemptyProp α)

instance : Nonempty (Stream α) :=
  match (Stream.nonemptyProp α).property with
  | Nonempty.intro v => Nonempty.intro { phantom := v }

namespace Stream

alloy c section

/*
This struct contains callbacks used by the stream API.

All UV stream operations contain a pointer to a `uv_stream_t`
that is preceded in memory by lean_stream_callback_s.
*/
struct lean_stream_callbacks_s {
  lean_object* listen_callback; // Object referencing method to call.
  lean_object* read_callback; // Object referencing method to call.
};

typedef struct lean_stream_callbacks_s lean_stream_callbacks_t;

void init_stream_callbacks(lean_stream_callbacks_t* cbs) {
  memset(cbs, 0, sizeof(lean_stream_callbacks_t));
}

static void stream_foreach(lean_stream_callbacks_t* callbacks, b_lean_obj_arg f) {
  if (callbacks->listen_callback != 0)
    lean_apply_1(f, callbacks->listen_callback);
  if (callbacks->read_callback != 0)
    lean_apply_1(f, callbacks->read_callback);
}

static void stream_close(lean_stream_callbacks_t* callbacks) {
  if (callbacks->listen_callback != 0)
    lean_dec(callbacks->listen_callback);
  if (callbacks->read_callback != 0)
    lean_dec(callbacks->read_callback);
}

static inline
lean_stream_callbacks_t* stream_callbacks(uv_stream_t* stream) {
  return ((lean_stream_callbacks_t*) stream) - 1;
}

static void listen_callback(uv_stream_t* server, int status) {
  printf("listen_callback(%p, %d)\n", server, status);
  if (status != 0)
    fatal_error("listen callback status = 0");
  // Get callback and idler handler objects
  lean_object* cb = stream_callbacks(server)->listen_callback;
  lean_inc(cb);
  lean_dec(lean_apply_1(cb, lean_box(0)));
}

lean_object* lean_uv_listen(lean_object* server, uint32_t backlog, lean_object* cb) {
  uv_stream_t* stream = lean_get_external_data(server);
  printf("stream listen(%p, %d)\n", stream, backlog);
  lean_stream_callbacks_t* cbs = stream_callbacks(stream);
  if (cbs->listen_callback)
    fatal_error("listen already called.\n");
  cbs->listen_callback = cb;
  int err = uv_listen(stream, backlog, &listen_callback);
  if (err < 0)
    fatal_error("uv_listen failed (error = %d).\n", err);
  return lean_io_unit_result_ok();
}

lean_object* lean_uv_accept(lean_object* server_obj, lean_object* client_obj) {
  uv_stream_t* server = lean_get_external_data(server_obj);
  uv_stream_t* client = lean_get_external_data(client_obj);
  int err = uv_accept(server, client);
  if (err < 0)
    fatal_error("uv_accept failed (error = %d).\n", err);
  return lean_io_unit_result_ok();
}

static
void alloc_callback(uv_handle_t *handle, size_t suggested_size, uv_buf_t *buf) {
  lean_object* sarray = lean_alloc_sarray(1, 0, suggested_size);
  buf->base = (char*) lean_sarray_cptr(sarray);
  buf->len = suggested_size;
}

static
void read_callback(uv_stream_t *stream, ssize_t nread, const uv_buf_t *buf) {
  printf("read_callback(%p, %zd, %p)\n", stream, nread, buf);
  lean_object* cb = stream_callbacks(stream)->read_callback;
  lean_inc(cb);
  char* data = buf->base;
  lean_object* array_obj = (lean_object*) (buf->base - offsetof(lean_sarray_object, m_data));
  lean_dec(lean_apply_2(cb, array_obj, lean_box(0)));
}

static
lean_object* lean_uv_read_start(lean_object* stream_obj, lean_object* cb) {
  uv_stream_t* stream = lean_get_external_data(stream_obj);
  lean_stream_callbacks_t* cbs = stream_callbacks(stream);
  if (cbs->read_callback)
    fatal_error("read_start already called.\n");
  cbs->read_callback = cb;
  int err = uv_read_start(stream, &alloc_callback, &read_callback);
  if (err < 0)
    fatal_error("uv_read_start failed (error = %d).\n", err);
  return lean_io_unit_result_ok();
}

static
lean_object* lean_uv_read_stop(lean_object* stream_obj) {
  uv_stream_t* stream = lean_get_external_data(stream_obj);
  int err = uv_read_stop(stream);
  if (err < 0)
    fatal_error("uv_read_stop failed (error = %d).\n", err);
  lean_stream_callbacks_t* cbs = stream_callbacks(stream);
  cbs->read_callback = 0;
  return lean_io_unit_result_ok();
}

end

@[extern "lean_uv_listen"]
opaque listen {α : Type} [Stream α]
  (server : α) (backlog : UInt32) (cb : BaseIO Unit): BaseIO Unit

@[extern "lean_uv_accept"]
opaque accept {α β : Type} [Stream α] [Stream β]
  (server : α) (client : β) : BaseIO Unit

@[extern "lean_uv_read_start"]
opaque read_start {α : Type} [Stream α]
  (stream : α) (callback : ByteArray -> BaseIO Unit) : BaseIO Unit

@[extern "lean_uv_read_sop"]
opaque read_stop {α : Type} [Stream α]
  (stream : α) : BaseIO Unit

end Stream

end Stream

section SockAddr

alloy c section

static void SockAddr_foreach(void* ptr, b_lean_obj_arg f) {
}

static void SockAddr_finalize(void* ptr) {
  free(ptr);
}
end

/--
A IPV4 or IPv6 socket address
-/
alloy c extern_type SockAddr => struct sockaddr := {
  foreach  := `SockAddr_foreach
  finalize := `free
}

namespace SockAddr

/--
Parses the string to create an IPV4 address with the given name and port.
-/
alloy c extern "lean_uv_ipv4_addr"
def mkIPv4 (addr:String) (port:UInt16) : IO SockAddr := {
  struct sockaddr_in* r = malloc(sizeof(struct sockaddr_in));
  if (uv_ip4_addr(lean_string_cstr(addr), port, r) != 0) {
    free(r);
    return lean_io_result_mk_error(lean_mk_io_user_error(
      lean_mk_string("Could not parse IPV4 address")));
  }
  return lean_io_result_mk_ok(to_lean<SockAddr>((struct sockaddr*) r));
}

/--
Parses the string to create an IPV6 address with the given name and port.
-/
alloy c extern "lean_uv_ipv6_addr"
def mkIPv6 (addr:String) (port:UInt16) : IO SockAddr := {
  struct sockaddr_in6* r = malloc(sizeof(struct sockaddr_in6));
  if (uv_ip6_addr(lean_string_cstr(addr), port, r) != 0) {
    free(r);
    return lean_io_result_mk_error(lean_mk_io_user_error(
      lean_mk_string("Could not parse IPV6 address")));
  }
  return lean_io_result_mk_ok(to_lean<SockAddr>((struct sockaddr*) r));
}

end SockAddr

end SockAddr

section TCP

alloy c section

struct lean_uv_tcp_s {
  lean_stream_callbacks_t callbacks;
  uv_tcp_t uv;
};

typedef struct lean_uv_tcp_s lean_uv_tcp_t;

static lean_uv_tcp_t* tcp_from_handle(uv_handle_t* h) {
  lean_stream_callbacks_t* op = (lean_stream_callbacks_t*) h;
  return (lean_uv_tcp_t*) (op - 1);
}

/* Return lean object representing this check */
static uv_handle_t* tcp_handle(lean_uv_tcp_t* p) {
  return (uv_handle_t*) &(p->uv);
}

static void TCP_foreach(void* ptr, b_lean_obj_arg f) {
  lean_uv_tcp_t* tcp = tcp_from_handle((uv_handle_t*) ptr);
  stream_foreach(&tcp->callbacks, f);
}

static void tcp_close_cb(uv_handle_t* h) {
  lean_uv_tcp_t* tcp = tcp_from_handle(h);
  stream_close(&tcp->callbacks);
  free_handle(h);
}

static void TCP_finalize(void* ptr) {
  uv_close((uv_handle_t*) ptr, &tcp_close_cb);
}

end

alloy c extern_type TCP => uv_handle_t := {
  foreach  := `TCP_foreach
  finalize := `TCP_finalize
}

-- FIXME: Support uv_tcp_init_ex
alloy c extern "lean_uv_tcp_init"
def Loop.mkTCP (loop : Loop) : BaseIO TCP := {
  lean_uv_tcp_t* tcp = malloc(sizeof(lean_uv_tcp_t));
  init_stream_callbacks(&tcp->callbacks);
  lean_object* r = to_lean<TCP>(tcp_handle(tcp));
  *handle_object(tcp_handle(tcp)) = r;
  uv_tcp_init(of_lean<Loop>(loop), &tcp->uv);
  return lean_io_result_mk_ok(r);
}

namespace TCP

opaque instStreamTCP : Stream TCP

instance : Stream TCP := instStreamTCP

alloy c extern "lean_uv_tcp_bind"
def bind (tcp : TCP) (addr : SockAddr) : BaseIO Unit := {
  printf("bind(hdl = %p, %p)\n", lean_get_external_data(tcp), addr);
  int err = uv_tcp_bind(lean_get_external_data(tcp), of_lean<SockAddr>(addr), 0);
  if (err != 0) {
    fatal_error("uv_tcp_bind failed (error = %d)\n", err);
  }
  return lean_io_unit_result_ok();
}

def listen (tcp : TCP) (backlog : UInt32) (cb : BaseIO Unit) : BaseIO Unit :=
  Stream.listen tcp backlog cb

def accept (server : TCP) (client : TCP) : BaseIO Unit :=
  Stream.accept server client

def read_start (tcp : TCP) (callback : ByteArray -> BaseIO Unit) : BaseIO Unit :=
  Stream.read_start tcp callback

def read_stop (tcp : TCP) : BaseIO Unit := Stream.read_stop tcp

end TCP

end TCP
