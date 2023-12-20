#include <lean/lean.h>
#include <stdlib.h>
#include <uv.h>

__attribute__((noreturn))
void fatal_error(const char *format, ...) {
  va_list args;
  va_start(args, format);
  vfprintf(stderr, format, args);
  va_end(args);
  exit(-1);
}

static void* checked_malloc(size_t n) {
  void* ptr = malloc(n);
  if (ptr == 0)
    lean_internal_panic_out_of_memory();
  return ptr;
}

static lean_object* lean_unit(void) {
  return lean_box(0);
}

static lean_object* lean_bool(bool b) {
  return lean_box(b ? 1 : 0);
}

static lean_object* lean_io_unit_result_ok() {
  return lean_io_result_mk_ok(lean_unit());
}

struct lean_uv_loop_s {
  uv_loop_t uv;
  // An IO error
  lean_object* io_error;
};

typedef struct lean_uv_loop_s lean_uv_loop_t;

/** Return the Lean loop object from the */
static uv_loop_t* of_loop(lean_object* l) {
  return lean_get_external_data(l);
}

/** Return the Lean loop object from the */
static lean_uv_loop_t* of_loop_ext(lean_object* l) {
  return lean_get_external_data(l);
}

/* Return lean object representing this handle */
static lean_object* loop_object(uv_loop_t* l) {
  return (lean_object*) l->data;
}

/** Finalize a non-stream handle. */
static inline void lean_uv_finalize_handle(uv_handle_t* h, bool is_active) {
  if (is_active) {
    h->data = 0;
  } else {
    uv_close(h, (uv_close_cb) free);
  }
  lean_dec(h->loop->data);
}

/*
Check the callback result from a handle.  The callback result should
have type `IO Unit`.
*/
static void check_callback_result(uv_loop_t* loop, lean_object* io_result) {
  if (lean_io_result_is_error(io_result)) {
    lean_uv_loop_t* l = (lean_uv_loop_t*) loop;
    if (l->io_error == 0) {
      uv_stop(&l->uv);
      l->io_error = io_result;
      return;
    }
  }
  lean_dec_ref(io_result);
}

/** Decrement an object that may be null. */
static void lean_dec_optref(lean_object* o) {
  if (o != NULL) lean_dec_ref(o);
}

/*
All handles use the data field to refer to the handle for it.
*/
static lean_object** handle_object(uv_handle_t* p) {
  return (lean_object**) &(p->data);
}

lean_obj_res lean_uv_raise_invalid_argument(lean_obj_arg msg, lean_obj_arg _s);

static
lean_obj_res invalid_argument(const char* msg) {
  return lean_uv_raise_invalid_argument(lean_mk_string(msg), lean_unit());
}

/**
 * Check that the lean object has not been marked as multi-threaded or persistent.
 */
static
void lean_uv_check_st(lean_object* o) {
  if (!lean_is_st(o)) {
    if (lean_is_persistent(o)) {
      fatal_error("libuv objects cannot be marked as persistent.");
    } else {
      fatal_error("libuv objects cannot be shared across tasks.");
    }
  }
}

__attribute__((noreturn))
void fatal_st_only(const char *name) {
  fatal_error("%s cannot be made multi-threaded or persistent.", name);
}

extern lean_object* lean_uv_error_mk(int err);

extern lean_object* lean_uv_io_error(int err);

/*
This struct contains callbacks used by the stream API.

See "uv_stream_t implementation note" above for more information.
*/
struct lean_stream_callbacks_s {
  lean_object* listen_callback;
  lean_object* read_callback; // Object referencing method to call.
};

typedef struct lean_stream_callbacks_s lean_stream_callbacks_t;

static void* lean_stream_base(uv_handle_t* h) {
  lean_stream_callbacks_t* op = (lean_stream_callbacks_t*) h;
  return (op - 1);
}