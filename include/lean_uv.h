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
  uv_loop_t* ptr = malloc(n);
  if (ptr == 0) {
    fatal_error("Out of memory.\n");
  }
  return ptr;
}

static lean_object* lean_unit(void) {
  return lean_box(0);
}

static lean_object* lean_bool(bool b) {
  return lean_box(b ? 1 : 0);
}

static lean_object* lean_io_unit_result_ok() {
  lean_object* r = 0;
  if (r == 0) {
    r = lean_io_result_mk_ok(lean_unit());
    lean_mark_persistent(r);
  }
  return r;
}

static uv_loop_t* of_loop(lean_object* l) {
  return lean_get_external_data(l);
}

/* Return lean object representing this handle */
static lean_object** loop_object(uv_loop_t* l) {
  return (lean_object**) &(l->data);
}


/* Return lean object representing this handle */
static lean_object** handle_object(uv_handle_t* p) {
  return (lean_object**) &(p->data);
}

// This decrements the loop object and frees the handle.
static void free_handle(uv_handle_t* handle) {
  lean_dec(*loop_object(handle->loop));
  free(handle);
}