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
  return lean_stream_base((uv_handle_t*) stream);
}

end

end Stream
end StreamDeclaration

section Shutdown

/-- References -/
opaque ShutdownReqPointed : NonemptyType.{0}

/-- A shutdown request -/
structure ShutdownReq (α : Type) : Type where
  ref : ShutdownReqPointed.type

instance : Nonempty (ShutdownReq α) :=
  Nonempty.intro { ref := Classical.choice ShutdownReqPointed.property }

alloy c section
/*
The external data of a ShutdownReq in Lean is a lean_uv_shutdown_t req where:

  req.uv.handle is a pointer to a uv_stream_t.
  req.uv.data is a pointer to the Lean shutdown_req object.  This is set
    to null if the shutdown request memory is released.
  req.callback is a pointer to the callback to invoke when the shutdown completes.
  This is set to null after the callback returns.
*/
struct lean_uv_shutdown_s {
  uv_shutdown_t uv;
  lean_object* callback;
};

typedef struct lean_uv_shutdown_s lean_uv_shutdown_t;

static void Req_foreach(void* ptr, b_lean_obj_arg f) {
  fatal_st_only("Req");
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
end

/--
This returns the handle associated with the shutdown request.
-/
@[extern "lean_uv_shutdown_req_handle"]
opaque ShutdownReq.handle [Inhabited α] (req : @&ShutdownReq α) : α

alloy c section
lean_obj_res lean_uv_shutdown_req_handle(b_lean_obj_arg reqObj, b_lean_obj_arg _rw) {
  lean_uv_shutdown_t* req = lean_get_external_data(reqObj);
  lean_object* hdl = req->uv.handle->data;
  lean_inc(hdl);
  return hdl;
}
end

/--
Shutdown the outgoing (write) side of a duplex stream.
It waits for pending write requests to complete.
The cb is called after shutdown is complete.
-/
@[extern "lean_uv_shutdown"]
opaque Stream.shutdown [Stream α] (handle : α) (cb : Bool → BaseIO Unit) : UV.IO (ShutdownReq α)

alloy c section

static void invoke_rec_callback(uv_loop_t* loop, uv_req_t* req, lean_object** cbp, lean_object* status) {
  // If the request object has been freed, then we can free the request
  // object as well.
  lean_object* cb = *cbp;
  if (req->data) {
    *cbp = 0;
  } else {
    free(req);
  }
  check_callback_result(loop, lean_apply_2(cb, status, lean_io_mk_world()));
}

static lean_obj_res mk_req(lean_external_class* cl, void* req) {
  lean_object* reqObj = lean_alloc_external(cl, req);
  ((uv_req_t*) req)->data = reqObj;
  return reqObj;
}

static void shutdown_cb(uv_shutdown_t *req, int status) {
  lean_uv_shutdown_t* lreq = (lean_uv_shutdown_t*) req;
  invoke_rec_callback(req->handle->loop, (uv_req_t*) req, &lreq->callback, lean_bool(status == 0));
}

lean_obj_res lean_uv_shutdown(b_lean_obj_arg handle, lean_obj_arg cb, b_lean_obj_arg _rw) {
  lean_uv_shutdown_t* req = malloc(sizeof(lean_uv_shutdown_t));
  if (shutdown_class == NULL)
    shutdown_class = lean_register_external_class(Shutdown_finalize, Req_foreach);
  lean_object* reqObj = mk_req(shutdown_class, req);
  uv_stream_t* hdl = lean_get_external_data(handle);
  int ec = uv_shutdown(&req->uv, hdl, &shutdown_cb);
  if (ec < 0) {
    // Release callback
    lean_dec_ref(cb);
    req->callback = 0;
    // Make sure handle is initialized to avoid special case in Shutdown_finalize.
    req->uv.handle = hdl;
    lean_free_object(reqObj);
    fatal_error("uv_shutdown_req failed (error = %d)", ec);
  }
  req->callback = cb;
  return lean_io_result_mk_ok(reqObj);
}

end

end Shutdown

section Listen
namespace Stream

alloy c section

static void listen_callback(uv_stream_t* server, int status) {
  if (status != 0)
    fatal_error("listen callback status != 0");
  // Get callback and increment
  lean_object* cb = stream_callbacks(server)->listen_callback;
  lean_inc(cb);
  check_callback_result(server->loop, lean_apply_1(cb, lean_io_mk_world()));
}

end

/--
Start listening for incoming connections.

`backlog` indicates the number of connections the kernel might queue,
same as `listen(2)`.

When a new incoming connection is received the connection callback is called.
-/
@[extern "lean_uv_listen"]
opaque listen {α : Type} [Stream α] (server : @&α) (backlog : UInt32) (cb : UV.IO Unit) : UV.IO Unit

end Stream

alloy c section
/** Return true if this is closed or closing. */
static bool lean_uv_is_closing(uv_stream_t* stream) {
  return stream->loop == 0
      || uv_is_closing((uv_handle_t*) stream);
}

lean_obj_res lean_uv_listen(b_lean_obj_arg socketObj, uint32_t backlog, lean_obj_arg cb, b_lean_obj_arg _rw) {
  uv_stream_t* socket = lean_get_external_data(socketObj);
  if (lean_uv_is_closing(socket)) {
    lean_dec_ref(cb);
    return lean_uv_io_error(UV_EINVAL);
  }

  lean_stream_callbacks_t* cbs = stream_callbacks(socket);
  if (cbs->listen_callback) {
    lean_dec_ref(cb);
    return lean_uv_io_error(UV_EALREADY);
  }
  int err = uv_listen(socket, backlog, &listen_callback);
  if (err < 0) {
    lean_dec_ref(cb);
    fatal_error("uv_listen failed (error = %d).\n", err);
  }
  cbs->listen_callback = cb;
  return lean_io_unit_result_ok();
}
end

@[extern "lean_uv_stream_stop"]
opaque Stream.stop {α : Type} [Stream α] (server : @&α) : UV.IO Unit

alloy c section

static void close_stream_stop(uv_handle_t* h) {
  // If finalize has already deleted object then free memory,
  // otherwise we set loop and rely on it to free memory.
  if (h->data == 0) {
    free(lean_stream_base(h));
  } else {
    h->loop = 0;
  }
}

lean_obj_res lean_uv_stream_stop(b_lean_obj_arg socketObj, b_lean_obj_arg _rw) {
  uv_stream_t* socket = lean_get_external_data(socketObj);

  if (lean_uv_is_closing(socket))
    return lean_uv_io_error(UV_EINVAL);

  lean_stream_callbacks_t* cbs = stream_callbacks(socket);
  if (cbs->listen_callback == 0)
    return lean_uv_io_error(UV_EINVAL);

  lean_dec_ref(cbs->listen_callback);
  cbs->listen_callback = 0;

  // Stop read callback.
  if (cbs->read_callback) {
    lean_dec_ref(cbs->read_callback);
    cbs->read_callback = 0;
  }
  uv_close((uv_handle_t*) socket, close_stream_stop);
  return lean_io_unit_result_ok();
}
end


end Listen

section Accept

@[extern "lean_uv_accept"]
opaque Stream.accept [Stream α] [Stream β] (server : @&α) (client : @&β) : UV.IO Unit

alloy c section
lean_obj_res lean_uv_accept(b_lean_obj_arg serverObj, lean_obj_arg clientObj, b_lean_obj_arg rw) {
  uv_stream_t* server = lean_get_external_data(serverObj);
  uv_stream_t* client = lean_get_external_data(clientObj);
  if (lean_uv_is_closing(server) || lean_uv_is_closing(client)) {
    return lean_uv_io_error(UV_EINVAL);
  }

  int err = uv_accept(server, client);
  if (err < 0)
    fatal_error("uv_accept failed (error = %d).\n", err);
  return lean_io_unit_result_ok();
}
end
end Accept

section Read

inductive ReadResult where
| ok : ByteArray → ReadResult
| eof : ReadResult
| error : ErrorCode → ReadResult

@[export lean_uv_read_ok]
def ReadResult.ok_c := ReadResult.ok

@[export lean_uv_read_eof]
def ReadResult.eof_c := ReadResult.eof

@[export lean_uv_read_error]
def ReadResult.error_c := ReadResult.error

/--
This starts reading data from the stream by invoking the callback when data is
available.

It throws `EALREADY` if a reader is already reading from the stream and `EINVAL
if the stream is closing.
-/
@[extern "lean_uv_read_start"]
opaque Stream.read_start [Stream α] (stream : @&α) (callback : ReadResult -> UV.IO Unit) : UV.IO Unit

alloy c section

static inline void init_buf(uv_buf_t *buf, lean_object* byteArray) {
  buf->base = (char*) lean_sarray_cptr(byteArray);
  buf->len = lean_sarray_size(byteArray);
}

static
void alloc_callback(uv_handle_t *handle, size_t suggested_size, uv_buf_t *buf) {
  lean_object* sarray = lean_alloc_sarray(1, 0, suggested_size);
  buf->base = (char*) lean_sarray_cptr(sarray);
  buf->len = suggested_size;
}

lean_object* lean_uv_read_ok(lean_obj_arg bytes);
extern lean_object* lean_uv_read_eof;
lean_object* lean_uv_read_error(lean_obj_arg e);

static lean_object* bufArrayObj(const uv_buf_t* buf) {
  return (lean_object*) (buf->base - offsetof(lean_sarray_object, m_data));
}

static void dec_buf_array(const uv_buf_t* buf) {
  lean_dec_ref(bufArrayObj(buf));
}

static
void read_callback(uv_stream_t *stream, ssize_t nread, const uv_buf_t *buf) {
  lean_object* cb = stream_callbacks(stream)->read_callback;
  lean_inc(cb);

  lean_object* arg;

  if (nread > 0) {
    // Recover the array object created by alloc_callback from buf.
    lean_object* array_obj = bufArrayObj(buf);
    // Set size
    lean_sarray_set_size(array_obj, nread);
    arg = lean_uv_read_ok(array_obj);
  } else {
    if (buf->base != 0)
      dec_buf_array(buf);
    if (nread == UV_EOF) {
      arg = lean_uv_read_eof;
    } else if (nread == UV_ENOBUFS) {
      // This should never occur alloc_callback either allocates
      // the required amount of memory or fails.
      fatal_error("Internal error - out of memory.\n");
    } else {
      arg = lean_uv_read_error(lean_uv_error_mk(nread));
    }
  }

  // Pass array into callback.
  check_callback_result(stream->loop, lean_apply_2(cb, arg, lean_io_mk_world()));
}

lean_object* lean_uv_read_start(b_lean_obj_arg stream_obj, lean_obj_arg cb, b_lean_obj_arg _rw) {
  uv_stream_t* stream = lean_get_external_data(stream_obj);
  if (lean_uv_is_closing(stream)) {
    lean_dec_ref(cb);
    return lean_uv_io_error(UV_EINVAL);
  }

  lean_stream_callbacks_t* cbs = stream_callbacks(stream);
  if (cbs->read_callback) {
    lean_dec_ref(cb);
    return lean_uv_io_error(UV_EALREADY);
  }
  cbs->read_callback = cb;
  int err = uv_read_start(stream, &alloc_callback, &read_callback);
  if (err < 0) {
    lean_dec_ref(cb);
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
opaque Stream.read_stop [Stream α] (stream : @&α) : BaseIO Unit

alloy c section
lean_object* lean_uv_read_stop(lean_object* stream_obj) {
  uv_stream_t* stream = lean_get_external_data(stream_obj);

  lean_stream_callbacks_t* cbs = stream_callbacks(stream);

  // Only need to do things if stream is reading.
  if (cbs->read_callback) {
    uv_read_stop(stream);

    // Clear stream read callback.
    lean_dec_ref(cbs->read_callback);
    cbs->read_callback = 0;
  }

  return lean_io_unit_result_ok();
}
end

end Read

section Write

/-- References -/
opaque WriteReqPointed : NonemptyType.{0}

/-- A shutdown request -/
structure WriteReq (α : Type) : Type where
  ref : WriteReqPointed.type

instance : Nonempty (WriteReq α) :=
  Nonempty.intro { ref := Classical.choice WriteReqPointed.property }

alloy c section
/*
The external data of a ShutdownReq in Lean is a lean_uv_shutdown_t req where:

  req.uv.handle is a pointer to a uv_stream_t.
  req.uv.data is a pointer to the Lean shutdown_req object.  This is set
    to null if the shutdown request memory is released.
  req.callback is a pointer to the callback to invoke when the shutdown completes.
  This is set to null after the callback returns.
*/
struct lean_uv_write_s {
  uv_write_t uv;
  lean_object* callback;
  uv_buf_t* bufs;
  size_t bufcnt;
};

typedef struct lean_uv_write_s lean_uv_write_t;

static void Write_finalize(void* ptr) {
  lean_uv_write_t* req = (lean_uv_write_t*) ptr;
  // Release counter on handle.
  lean_dec_ref(req->uv.handle->data);
  if (req->callback) {
    req->uv.data = 0;
  } else {
    free(req);
  }
}

static lean_external_class * write_class = NULL;
end

/--
This returns the handle associated with the shutdown request.
-/
@[extern "lean_uv_write_handle"]
opaque WriteReq.handle [Inhabited α] (req : @&WriteReq α) : α

alloy c section
lean_obj_res lean_uv_write_handle(b_lean_obj_arg reqObj, b_lean_obj_arg _rw) {
  uv_write_t* req = lean_get_external_data(reqObj);
  lean_object* hdl = req->handle->data;
  lean_inc_ref(hdl);
  return hdl;
}
end

end Write

@[extern "lean_uv_write"]
opaque Stream.write [Stream α] (stream : α) (bufs : @&Array ByteArray)
  (callback : Bool → UV.IO Unit) : UV.IO (WriteReq α)

alloy c section
static void write_cb(uv_write_t *req, int status) {
  lean_uv_write_t* lreq = (lean_uv_write_t*) req;
  uv_loop_t* loop = req->handle->loop;
  lean_object* success = lean_bool(status == 0);
  // If the request object has been freed, then we can free the request
  // object as well.
  lean_object* cb = lreq->callback;
  if (req->data) {
    lreq->callback = 0;
    uv_buf_t* bufs = lreq->bufs;
    uv_buf_t* bufEnd = bufs + lreq->bufcnt;
    for (uv_buf_t* buf = bufs; buf != bufEnd; ++buf)
      dec_buf_array(buf);
    free(bufs);
  } else {
    free(req);
  }
  check_callback_result(loop, lean_apply_2(cb, success, lean_io_mk_world()));
}

lean_obj_res lean_uv_write(b_lean_obj_arg streamObj, b_lean_obj_arg bufObj,
  lean_obj_arg callback, b_lean_obj_arg _rw) {
  size_t nbufs = lean_array_size(bufObj);
  if (nbufs == 0) {
    return lean_uv_io_error(UV_EINVAL);
  }

  lean_uv_write_t* req = checked_malloc(sizeof(lean_uv_write_t));
  if (write_class == NULL)
    write_class = lean_register_external_class(Write_finalize, Req_foreach);
  lean_object* reqObj = mk_req(write_class, req);
  uv_stream_t* hdl = lean_get_external_data(streamObj);

  lean_object** bufObjs = lean_array_cptr(bufObj);

  uv_buf_t* bufArray = malloc(sizeof(uv_buf_t) * nbufs);
  for (size_t i = 0; i != nbufs; ++i) {
    init_buf(bufArray + i, bufObjs[i]);
  }

  int ec = uv_write(&req->uv, hdl, bufArray, nbufs, &write_cb);
  if (ec < 0) {
    lean_dec_ref(callback);
    req->callback = 0;
    req->uv.handle = hdl;
    lean_free_object(req->uv.data);
    fatal_error("uv_write failed (error = %d)", ec);
  } else {
    req->callback = callback;
    return lean_io_result_mk_ok(reqObj);
  }
}

end


section SockAddr

alloy c section

static void SockAddr_finalize(void* ptr) {
  free(ptr);
}

static void SockAddr_foreach(void* ptr, b_lean_obj_arg f) {
}

end

/--
A IPV4 or IPv6 socket address
-/
alloy c extern_type SockAddr => struct sockaddr := {
  foreach  := `SockAddr_foreach
  finalize := `SockAddr_finalize
}

namespace SockAddr

/--
Parses the string to create an IPV4 address with the given name and port.
-/
alloy c extern "lean_uv_ipv4_addr"
def mkIPv4 (addr:String) (port:UInt16) : UV.IO SockAddr := {
  struct sockaddr_in* r = checked_malloc(sizeof(struct sockaddr_in));
  if (uv_ip4_addr(lean_string_cstr(addr), port, r) != 0) {
    free(r);
    return lean_uv_io_error(UV_EINVAL);
  }
  return lean_io_result_mk_ok(to_lean<SockAddr>((struct sockaddr*) r));
}

/--
Parses the string to create an IPV6 address with the given name and port.
-/
alloy c extern "lean_uv_ipv6_addr"
def mkIPv6 (addr:String) (port:UInt16) : UV.IO SockAddr := {
  struct sockaddr_in6* r = checked_malloc(sizeof(struct sockaddr_in6));
  if (uv_ip6_addr(lean_string_cstr(addr), port, r) != 0) {
    free(r);
    return lean_uv_io_error(UV_EINVAL);
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
  bool connecting;
};

typedef struct lean_uv_tcp_s lean_uv_tcp_t;

static void TCP_foreach(void* ptr, b_lean_obj_arg f) {
  fatal_st_only("TCP");
}

void lean_uv_close_stream(uv_handle_t* h) {
  free(lean_stream_base(h));
}

// Close the check handle if the loop stops
extern void lean_uv_tcp_loop_stop(uv_handle_t* h) {
  lean_uv_tcp_t* tcp = lean_stream_base(h);
  lean_stream_callbacks_t* callbacks = &tcp->callbacks;
  lean_dec_optref(callbacks->listen_callback);
  lean_dec_optref(callbacks->read_callback);
  uv_close(h, &lean_uv_close_stream);
}

static void TCP_finalize(void* ptr) {
  lean_uv_tcp_t* tcp = lean_stream_base((uv_handle_t*) ptr);
  lean_stream_callbacks_t* callbacks = &tcp->callbacks;
  uv_handle_t* handle = (uv_handle_t*)(&tcp->uv);
  if (uv_is_closing(handle)) {
    // This indicates user called stop explicitly.  We should check if the callback
    // from stop has already run and either clear data or free memory dependending on status.
    if (handle->loop != 0) {
      tcp->uv.data = 0;
    } else {
      free(tcp);
    }
  } else if (callbacks->read_callback == 0
          && callbacks->listen_callback == 0
          && !tcp->connecting) {
    uv_close(handle, &lean_uv_close_stream);
  } else {
    tcp->uv.data = 0;
  }
  // Release loop object.  Note that this may free the loop object
  lean_dec_ref(loop_object(tcp->uv.loop));
}

end

alloy c extern_type TCP => uv_tcp_t := {
  foreach  := `TCP_foreach
  finalize := `TCP_finalize
}

alloy c extern "lean_uv_tcp_init"
def Loop.mkTCP (loop : Loop) : BaseIO TCP := {
  lean_uv_tcp_t* tcp = checked_malloc(sizeof(lean_uv_tcp_t));
  init_stream_callbacks(&tcp->callbacks);
  tcp->connecting = false;
  uv_tcp_init(of_loop(loop), &tcp->uv);
  lean_object* r = to_lean<TCP>(&tcp->uv);
  tcp->uv.data = r;
  return lean_io_result_mk_ok(r);
}

namespace TCP

opaque instStreamTCP : Stream TCP

instance : Stream TCP := instStreamTCP

alloy c extern "lean_uv_tcp_bind"
def bind (tcp : @&TCP) (addr : @&SockAddr) : UV.IO Unit := {
  uv_tcp_t* uv_tcp = lean_get_external_data(tcp);
  if (lean_uv_is_closing((uv_stream_t*) uv_tcp))
    return lean_uv_io_error(UV_EINVAL);

  int err = uv_tcp_bind(uv_tcp, of_lean<SockAddr>(addr), 0);
  if (err != 0)
    fatal_error("uv_tcp_bind failed (error = %d)\n", err);
  return lean_io_unit_result_ok();
}

/-- References -/
opaque ConnectReqPointed : NonemptyType.{0}

/-- A shutdown request -/
structure ConnectReq (α : Type) : Type where
  ref : ConnectReqPointed.type

instance : Nonempty (ConnectReq α) :=
  Nonempty.intro { ref := Classical.choice ConnectReqPointed.property }


alloy c section
/*
The external data of a ConnectReq in Lean is a lean_uv_connect_t req where:

  req.uv.handle is a pointer to a uv_stream_t.
  req.uv.data is a pointer to the Lean shutdown_req object.  This is set
    to null if the shutdown request memory is released.
  req.callback is a pointer to the callback to invoke when the shutdown completes.
  This is set to null after the callback returns.
*/
struct lean_uv_connect_s {
  uv_connect_t uv;
  lean_object* callback;
};

typedef struct lean_uv_connect_s lean_uv_connect_t;

static void Connect_finalize(void* ptr) {
  lean_uv_connect_t* req = (lean_uv_connect_t*) ptr;
  lean_dec_ref(req->uv.handle->data);
  if (req->callback) {
    req->uv.data = 0;
  } else {
    free(req);
  }
}

static lean_external_class * connect_class = NULL;
end

inductive ConnectionResult where
| ok : ConnectionResult
| canceled : ConnectionResult
| timedout : ConnectionResult
| unknown  : ConnectionResult
deriving Inhabited, Repr

alloy c section
static void tcp_connect_cb(uv_connect_t *req, int status) {
  lean_object* statusObj;
  switch (status) {
  case UV_ECANCELED:
    statusObj = lean_box(1);
    break;
  case UV_ETIMEDOUT:
    statusObj = lean_box(2);
    break;
  default:
    if (status >= 0) {
      statusObj = lean_box(0);
    } else {
      statusObj = lean_box(3);
    }
    break;
  }

  lean_uv_connect_t* lreq = (lean_uv_connect_t*) req;
  lean_uv_tcp_t* luv_tcp = lean_stream_base((uv_handle_t*) req->handle);
  luv_tcp->connecting = false;
  invoke_rec_callback(req->handle->loop, (uv_req_t*) req, &lreq->callback, statusObj);
}
end

alloy c extern "lean_uv_tcp_connect"
def connect (tcp : TCP) (addr : @&SockAddr) (callback : ConnectionResult → UV.IO Unit) : UV.IO (ConnectReq TCP) := {
  lean_uv_tcp_t* luv_tcp = lean_stream_base(lean_get_external_data(tcp));
  uv_tcp_t* uv_tcp = &luv_tcp->uv;
  uv_stream_t* hdl = (uv_stream_t*) uv_tcp;
  if (luv_tcp->connecting) {
    return lean_uv_io_error(UV_EINVAL);
  }
  lean_uv_connect_t* req = malloc(sizeof(lean_uv_connect_t));

  if (connect_class == NULL)
    connect_class = lean_register_external_class(Connect_finalize, Req_foreach);
  lean_object* reqObj = mk_req(connect_class, req);
  req->callback = callback;

  const struct sockaddr *uv_addr = of_lean<SockAddr>(addr);

  int ec = uv_tcp_connect(&req->uv, uv_tcp, uv_addr, &tcp_connect_cb);
  if (ec < 0) {
    lean_dec_ref(tcp);
    lean_dec_ref(callback);
    req->callback = 0;
    // Make sure handle is initialized to avoid special case in Shutdown_finalize.
    req->uv.handle = hdl;
    lean_free_object(reqObj);
    fatal_error("uv_tcp_connect failed (error = %d)", ec);
  }
  luv_tcp->connecting = true;
  return lean_io_result_mk_ok(reqObj);
}

def listen (tcp : TCP) (backlog : UInt32) (callback : UV.IO Unit) : UV.IO Unit :=
  Stream.listen tcp backlog callback

def stop (tcp : TCP) : UV.IO Unit :=
  Stream.stop tcp

def accept (server : TCP) (client : TCP) : UV.IO Unit :=
  Stream.accept server client

def read_start (tcp : TCP) (callback : ReadResult -> UV.IO Unit) : UV.IO Unit :=
  Stream.read_start tcp callback

@[extern "lean_uv_test_impl"]
def test_impl {α:Type} (c : @&TCP) (d : α): UV.IO Unit := pure ()

alloy c section
lean_obj_res lean_uv_test_impl(b_lean_obj_arg x, b_lean_obj_arg y, b_lean_obj_arg rw) {
  lean_dec_ref(y);
  return lean_io_result_mk_ok(lean_box(0));
}
end

@[noinline]
def test (c : TCP) (d : α) : UV.IO Unit := test_impl c d

def read_stop (tcp : TCP) : UV.IO Unit :=
  Stream.read_stop tcp

def write (stream : TCP) (bufs : @&Array ByteArray) (callback : Bool → UV.IO Unit) :=
  Stream.write stream bufs callback

end TCP

end TCP
