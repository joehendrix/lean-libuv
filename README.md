# LibUV Bindings for Lean

This library aims to provide a Lean interface to the
[LibUV](https://libuv.org/) cross-platform library that abstracts core
operating system operations including asynchronous IO, managing
concurrent processes and threads, and monitoring files for changes.

## Overview

`libuv` has three main entities

* Handles represent resources with the potential for events an application
  may want to respond to.  Events are processed by callback functions.
  There are multiple types of handles and the set of events a handle provide
  depends on the type.

* Loops represent collection of handles and provide a function `run` for
  enabling a thread to execute all the pending callbacks efficienctly.  Each
  handle is associated with at most one loop, and loops are not designed for
  concurrent access.  One should not invoke methods on a loop or handles
  associated with a loop in multiple threads concurrently.

* Requests represent asynchronous actions that can be potentially
  cancelled if the result is no longer needed.  One can get the handle
  assocaiated with a request.

There is also a subtype of handles, called
[Streams](https://docs.libuv.org/en/v1.x/stream.html), that are used
by TCP, Pipes and TTYs via a common API for streams.

## Intentional Design Constraints

`libuv` has APIs for multi-threading that can on a broad set of platforms, but
intentionally exposes a fairly limited API for improved corrrectness and ABI
stability across a broad set of platforms.  As such we do not attempt to
wrap all `LibUV` operations as they may come with limitations.  However, we
plan to provide mechanisms for all omited functionality.

The [Async handles](https://docs.libuv.org/en/v1.x/async.html) in a loop
are stored in a single list that is iterated through anytime a wakeup
event is processed.  This is a [known performance
problem](https://github.com/libuv/libuv/issues/1866) if one creates many
async handles that aren't triggered very often.  The issue has been
reported, and will not be fixed due to ABI stability and other concerns.

The [`libuv` threadpool](https://docs.libuv.org/en/v1.x/threadpool.html)
is a global threadpool for file system operations as well as
`getaddrinfo` and `getnameinfo` requests.  `libuv` provides a function
[`uv_queue_work`](https://docs.libuv.org/en/v1.x/threadpool.html#c.uv_queue_work)
for adding user work requests to the pool as well.  However, `libuv` does
not provide mechanisms for running initialization or finalization steps in
the threadpool.  It also doesn't direct access to the push operation, but
rather exposes a more limited API that also has a callback to the loop
thread.  This means that we can't string together a sequence of smaller
tasks to run in worker threads without regularly interupting the main loop
thread.

Very few of underlying lib UV types are designed for concurrent access
by multiple threads.  All `lean-libuv` loops, handles and requests may
not be shared between Lean tasks, and creating a Lean task over a
closure that contains a `lean-libuv` type will result in a runtime
error.  We eventually plan to address this through a single-threaded
monad.

We will address these limitations in a future update with a Lean
specific work queue.

## Memory Layout

`libuv` uses a consistent scheme in which loops, handles and requests
all have an associated C struct (`uv_loop_t`, `uv_handle_t` and
`uv_req_t` respectively).  Moreover each of these has a `data` field
that allows associating a pointer with each type.  Specific types of
handles and requests all have their own structs, but the layout is
designed so that the first `sizeof(uv_handle_t)` bytes of any handle are
a valid `uv_handle_t` and a similiar constraint holds for requests.
Moreover, three of the handle subtypes `uv_tcp_t`, `uv_pipe_t` and
`uv_tty_t` are streams, and the first bytes of their data can be
interpreted as a `uv_stream_t`.

Allocation of all of these types is performed by the client library, and
so one can allocate additional memory before or after the raw `libuv`
struct to store additional information.  The Lean `libuv` bindings use
the `data` fields to store pointers to the Lean objects associated with
`libuv` structs, and allocate additional memory around the raw `libuv`
structs for callback closures.  Type specific closures (e.g., for the
Idle callback) are generally stored after the `libuv` structs.  The main
exception is that the closures needed for by the stream API are stored
before the struct so that those operations do not need to branch on the
specific type of handle.

## Reference Counting

We need to ensure that all LibUV resources are released when the Lean
program no longer refers to them.  Doing this requires that there are no
cyclic dependencies between objects. This is non-trivial in Lean because
handles need to hold a reference to their associated loops while loops
may need to retrieve their active handles when `uv_run` or `uv_walk` is
called.

We adopt the following scheme:

* Every handle object holds a reference to the associated loop object.
* Depending on their type, requests may hold references to handles or
  loops.
* Every loop, handle and requests hold their corresponding object in the
  `data` field.  The `data` field will always be non-null for `uv_loop_t`,
  but may be null for `uv_handle_t` and `uv_req_t`.
* When a Lean request object is freed, then the following steps are taken:
  1. The data field for the request object is set to null.
  2. Any references to Lean objects are released.
  3. If the request has been fulfilled, then the memory is released.  Otherwise
     we must wait for callback.
* When a Lean handle object is freed, then the following steps are taken:
  1. The data field for the handle object is set to null.
  2. If the handle is not active, then `uv_close` is called with
    a callback that will free the handle resources.  Once the callback
    is invoked, `uv_walk` will no longer return the handle.
  3. The reference to the loop is released.
* When a Lean loop object is freed, then we call `uv_loop_close` and if
  it succeeds we free the loop resources and are done.  If not, then
  we close all active handles with the following steps:
  1. The loop walks the list of handles, and invokes close on each handle
     that is not closing.
  2. If there were any handles in the loop encountered in step 1, then
     `uv_run` is called with `UV_RUN_DEFAULT` to run all closing callbacks.
    If this returns non-zero, then we exit with a fatal error since this
    reflects a bug in Lean LibUV.
  3. We call `uv_loop_close` again. If it fails again, then we report
     a fatal error since this reflects a bug in Lean LibUV code.
* Handles may need to be closed explicitly.  This is particularly
  true for streams that are listening on a port, since there is no function to
  stop listening.  We currently only allow streams to be closed, but may
  eventually allow all streams to be explicitly closed.
* If a handle or rquest data field is set to null but needed again for a
  callback, then a new Lean object of the appropriate type will be created
  and `uv_run` invokes a callback on a handle with a null `data` field, then
  a new handle object is created and assigned to `uv_handle_t.data`.

## Sockets closing

Streams have additional potential states as there is no way to stop listening
once `uv_listen` is invoked.  To work around this, we have an explicit
`Stream.close` operation that closes the socket, but does not free the underlying
`uv_stream_t` struct (until the Lean object is finalized).

LibUV does not provide a function to see if a handle has been closed, so we set
the stream handle loop field to null if the stream has fully closed, but not freed.
The finalize procedure for a stream must detect this and free the object.