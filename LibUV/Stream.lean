import LibUV.Loop

open scoped Alloy.C
alloy c include <stdlib.h> <lean_uv.h>

section NonemptyProp


def NonemptyProp := Subtype fun α : Prop => Nonempty α

instance : Inhabited NonemptyProp := ⟨⟨PUnit, ⟨⟨⟩⟩⟩⟩

/-- The underlying type of a `NonemptyType`. -/
abbrev NonemptyProp.type (type : NonemptyProp) : Prop := type.val

end NonemptyProp

namespace UV

section StreamDeclaration

private opaque Stream.nonemptyProp (α : Type) : NonemptyProp

/--
The Lean `Stream` class is a marker class that holds for LibUV types
that are stream objects.
-/
class Stream (α: Type) : Prop where
  phantom : NonemptyProp.type (Stream.nonemptyProp α)

/---
Stream implementation note.

As noted in the README implementation notes, the stream API closures are
stored before the `uv_handle_t` pointer.  This is implemented in a
struct `lean_stream_callbacks_t` that is stored before the `uv_stream_t`
struct and it can be obtained via `stream_callbacks` defined below.

All types that implement the `Stream` typeclass must respect this memory
layout so that we can create polymorphic stream operations.
-/
instance : Nonempty (Stream α) :=
  match (Stream.nonemptyProp α).property with
  | Nonempty.intro v => Nonempty.intro (Stream.mk v)

namespace Stream

alloy c section


void init_stream_callbacks(lean_stream_callbacks_t* cbs) {
  memset(cbs, 0, sizeof(lean_stream_callbacks_t));
}

static inline
lean_stream_callbacks_t* stream_callbacks(uv_stream_t* stream) {
  return ((lean_stream_callbacks_t*) stream) - 1;
}

end

end Stream
end StreamDeclaration

section Shutdown

alloy c section
/*
The external data of a ShutdownReq in Lean is a lean_uv_shutdown_t req where:

  req.uv.handle is a pointer to a uv_stream_t.
  req.uv.data is a pointer to the Lean shutdown_req object.  This is set
    to null if the shutdown request memory is released.
  req.callback is a pointer to the callback to invoke when the shutdown
  completes.  This is set to null after the callback returns.
*/
struct lean_uv_shutdown_s {
  uv_shutdown_t uv;
  lean_object* callback;
};

typedef struct lean_uv_shutdown_s lean_uv_shutdown_t;

static void Shutdown_foreach(void* ptr, b_lean_obj_arg f) {
  fatal_st_only("ShutdownReq");
}

static void Shutdown_finalize(void* ptr) {
  lean_uv_shutdown_t* req = (lean_uv_shutdown_t*) ptr;
  // Release counter on handle.
  lean_dec_ref(req->uv.handle->data);
  if (req->callback) {
    req->uv.data = 0;
  } else {
    free(req);
  }
}

static lean_external_class * shutdown_class = NULL;

static void shutdown_cb(uv_shutdown_t *req, int status) {
  lean_object* success = lean_bool(status == 0);
  lean_uv_shutdown_t* lreq = (lean_uv_shutdown_t*) req;

  uv_loop_t* loop = req->handle->loop;

  lean_object* cb = lreq->callback;
  // If the request object has been freed, then we can free the request
  // object as well.
  if (lreq->uv.data) {
    lreq->callback = 0;
  } else {
    free(lreq);
  }
  // N.B. We intentionally have not incremented reference count to
  // `cb` so it may get finalized when returning from lean_apply.
  check_callback_result(loop, lean_apply_1(cb, success));
}
end

/-- References -/
opaque ShutdownReqPointed : NonemptyType.{0}

/--
A shutdown rewquest
-/
structure ShutdownReq (α : Type) : Type where
  ref : ShutdownReqPointed.type

instance : Nonempty (ShutdownReq α) :=
  Nonempty.intro { ref := Classical.choice ShutdownReqPointed.property }

namespace ShutdownReq

/--
This returns the handle associated with the shutdown request.
-/
@[extern "lean_uv_shutdown_req_handle"]
opaque handle [Inhabited α] (req : @&ShutdownReq α) : α

alloy c section
lean_obj_res lean_uv_shutdown_req_handle(b_lean_obj_arg reqObj, b_lean_obj_arg _rw) {
  lean_uv_shutdown_t* req = lean_get_external_data(reqObj);
  lean_object* hdl = req->uv.handle->data;
  lean_inc(hdl);
  return hdl;
}
end

end ShutdownReq

namespace Stream
/--
Shutdown the outgoing (write) side of a duplex stream.
It waits for pending write requests to complete.
The cb is called after shutdown is complete.
-/
@[extern "lean_uv_shutdown"]
opaque shutdown [Stream α] (handle : α) (cb : Bool → BaseIO Unit) : UV.IO (ShutdownReq α)

alloy c section
lean_obj_res lean_uv_shutdown(lean_obj_arg handle, lean_obj_arg cb, b_lean_obj_arg _rw) {
  uv_stream_t* hdl = lean_get_external_data(handle);
  lean_uv_shutdown_t* req = malloc(sizeof(lean_uv_shutdown_t));
  req->callback = cb;

  if (shutdown_class == NULL) {
    shutdown_class = lean_register_external_class(Shutdown_finalize, Shutdown_foreach);
  }
  lean_object* reqObj = lean_alloc_external(shutdown_class, req);
  req->uv.data = reqObj;
  int ec = uv_shutdown(&req->uv, hdl, &shutdown_cb);
  if (ec < 0) {
    // Release callback
    lean_dec(cb);
    req->callback = 0;
    // Make sure handle is initialized to avoid special case in Shutdown_finalize.
    req->uv.handle = hdl;
    // This will free reqObj and decrement hdl and then free reqObj and req.
    lean_free_object(reqObj);
    fatal_error("uv_shutdown_req failed (error = %d)", ec);
  }
  return lean_io_result_mk_ok(reqObj);
}

end

end Stream
end Shutdown

namespace Stream

opaque ConnectReq (α : Type) : Type

opaque WriteReq : Type


@[extern "lean_uv_accept"]
opaque accept [Stream α] [Stream β] (server : α) (client : β) : BaseIO Unit

alloy c section
lean_obj_res lean_uv_accept(b_lean_obj_arg server, lean_obj_arg client) {
  // FIXME.  Ensure accept can be called.
  uv_stream_t* uv_server = lean_get_external_data(server);
  uv_stream_t* uv_client = lean_get_external_data(client);
  int err = uv_accept(uv_server, uv_client);
  if (err < 0)
    fatal_error("uv_accept failed (error = %d).\n", err);
  return lean_io_unit_result_ok();
}
end

/--
This starts reading data from the stream by invoking the callback when data is
available.

It throws `EALREADY` if a reader is already reading from the stream and `EINVAL
if the stream is closing.
-/
@[extern "lean_uv_read_start"]
opaque read_start [Stream α] (stream : α) (callback : ByteArray -> BaseIO Unit) : UV.IO Unit

alloy c section
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

lean_object* lean_uv_read_start(lean_object* stream_obj, lean_object* cb) {
  uv_stream_t* stream = lean_get_external_data(stream_obj);
  lean_stream_callbacks_t* cbs = stream_callbacks(stream);
  if (cbs->read_callback) {
    lean_dec(stream_obj);
    lean_dec(cb);
    return lean_uv_io_error(UV_EALREADY);
  }
  cbs->read_callback = cb;
  int err = uv_read_start(stream, &alloc_callback, &read_callback);
  if (err < 0) {
    lean_dec(stream_obj);
    lean_dec(cb);
    return lean_uv_io_error(err);
  }
  return lean_io_unit_result_ok();
}
end

/--
This stops reading data from the stream.

It always succeeds even if data is not being read from stream.
-/
@[extern "lean_uv_read_stop"]
opaque read_stop [Stream α] (stream : α) : BaseIO Unit

alloy c section
lean_object* lean_uv_read_stop(lean_object* stream_obj) {
  uv_stream_t* stream = lean_get_external_data(stream_obj);

  // Only need to do things if stream is active.
  if (uv_is_active((uv_handle_t*) stream)) {
    uv_read_stop(stream);

    // Clear stream read callback.
    lean_stream_callbacks_t* cbs = stream_callbacks(stream);
    if (cbs->read_callback) {
      lean_dec(cbs->read_callback);
      cbs->read_callback = 0;
    }

    // If stream is no longer active, release it from implicit ownership by loop.
    if (!uv_is_active((uv_handle_t*) stream)) {
      lean_dec(stream_obj);
    }
  }

  // Release stream object
  lean_dec(stream_obj);
  return lean_io_unit_result_ok();
}
end

/-
@[extern "lean_uv_write"]
opaque write [Stream α] (stream : α) : BaseIO Unit
-/

end Stream

section SockAddr

alloy c section

static void SockAddr_foreach(void* ptr, b_lean_obj_arg f) {
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
  struct sockaddr_in* r = checked_malloc(sizeof(struct sockaddr_in));
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
  struct sockaddr_in6* r = checked_malloc(sizeof(struct sockaddr_in6));
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
  fatal_st_only("TCP");
}

static void tcp_close_cb(uv_handle_t* h) {
  lean_uv_tcp_t* tcp = tcp_from_handle(h);
  lean_stream_callbacks_t* callbacks = &tcp->callbacks;
  if (callbacks->listen_callback != 0)
    lean_dec(callbacks->listen_callback);
  free_handle(h);
}

static void TCP_finalize(void* ptr) {
  lean_uv_tcp_t* tcp = tcp_from_handle(ptr);
  lean_stream_callbacks_t* callbacks = &tcp->callbacks;
  if (callbacks->read_callback != 0)
    lean_dec(callbacks->read_callback);
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
  lean_uv_tcp_t* tcp = checked_malloc(sizeof(lean_uv_tcp_t));
  init_stream_callbacks(&tcp->callbacks);
  lean_object* r = to_lean<TCP>(tcp_handle(tcp));
  *handle_object(tcp_handle(tcp)) = r;
  uv_tcp_init(of_loop(loop), &tcp->uv);
  return lean_io_result_mk_ok(r);
}

namespace TCP

opaque instStreamTCP : Stream TCP

instance : Stream TCP := instStreamTCP

alloy c extern "lean_uv_tcp_bind"
def bind (tcp : TCP) (addr : SockAddr) : BaseIO Unit := {
  int err = uv_tcp_bind(lean_get_external_data(tcp), of_lean<SockAddr>(addr), 0);
  if (err != 0) {
    fatal_error("uv_tcp_bind failed (error = %d)\n", err);
  }
  return lean_io_unit_result_ok();
}

--def listen (tcp : TCP) (backlog : UInt32) (cb : BaseIO Unit) : UV.IO Unit :=
--  Stream.listen tcp backlog cb

def accept (server : TCP) (client : TCP) : BaseIO Unit :=
  Stream.accept server client

def read_start (tcp : TCP) (callback : ByteArray -> BaseIO Unit) : UV.IO Unit :=
  Stream.read_start tcp callback

def read_stop (tcp : TCP) : BaseIO Unit := Stream.read_stop tcp

end TCP

end TCP
