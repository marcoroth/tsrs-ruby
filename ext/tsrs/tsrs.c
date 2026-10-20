#include <ruby.h>
#include <ruby/encoding.h>
#include <ruby/thread.h>
#include "include/tsrs.h"

static VALUE rb_mTsrs;
static VALUE rb_mBackend;
static VALUE rb_eError;
static VALUE rb_eOptionError;
static VALUE rb_eTsrsEncodingError;
static VALUE rb_eTranspileError;
static VALUE rb_eInternalError;
static VALUE rb_ePanicError;
static VALUE rb_eCheckError;
static VALUE rb_cSessionHandle;

typedef struct TsrsResult (*tsrs_source_function)(const char *, const char *);
typedef struct TsrsResult (*tsrs_options_function)(const char *);

struct source_call_arguments {
  tsrs_source_function function;
  const char *source;
  const char *options;
  struct TsrsResult result;
};

struct options_call_arguments {
  tsrs_options_function function;
  const char *options;
  struct TsrsResult result;
};

static VALUE make_utf8_string(const char *cstring) {
  return rb_enc_str_new_cstr(cstring, rb_utf8_encoding());
}

static VALUE take_utf8_string(char *cstring) {
  if (!cstring) return Qnil;

  VALUE string = make_utf8_string(cstring);
  tsrs_string_free(cstring);

  return string;
}

static VALUE error_class_for(enum TsrsErrorCode code) {
  switch (code) {
    case TSRS_ERROR_CODE_OPTION: return rb_eOptionError;
    case TSRS_ERROR_CODE_ENCODING: return rb_eTsrsEncodingError;
    case TSRS_ERROR_CODE_TRANSPILE: return rb_eTranspileError;
    case TSRS_ERROR_CODE_CHECK: return rb_eCheckError;
    case TSRS_ERROR_CODE_PANIC: return rb_ePanicError;
    default: return rb_eInternalError;
  }
}

static VALUE unwrap(struct TsrsResult result) {
  if (result.error) {
    VALUE message = make_utf8_string(result.error);
    VALUE error_class = error_class_for(result.code);

    tsrs_result_free(result);

    rb_raise(error_class, "%s", StringValueCStr(message));
  }

  if (!result.value) {
    tsrs_result_free(result);

    rb_raise(rb_eInternalError, "tsrs returned no result");
  }

  VALUE value = rb_enc_str_new(result.value, (long) result.value_len, rb_utf8_encoding());

  tsrs_result_free(result);

  return value;
}

static void *source_call_without_gvl(void *data) {
  struct source_call_arguments *arguments = (struct source_call_arguments *) data;

  arguments->result = arguments->function(arguments->source, arguments->options);

  return NULL;
}

static void *options_call_without_gvl(void *data) {
  struct options_call_arguments *arguments = (struct options_call_arguments *) data;

  arguments->result = arguments->function(arguments->options);

  return NULL;
}

static VALUE source_call(tsrs_source_function function, VALUE source, VALUE options) {
  struct source_call_arguments arguments;

  arguments.function = function;
  arguments.source = StringValueCStr(source);
  arguments.options = StringValueCStr(options);

  rb_thread_call_without_gvl(source_call_without_gvl, &arguments, NULL, NULL);

  RB_GC_GUARD(source);
  RB_GC_GUARD(options);

  return unwrap(arguments.result);
}

static VALUE options_call(tsrs_options_function function, VALUE options) {
  struct options_call_arguments arguments;

  arguments.function = function;
  arguments.options = StringValueCStr(options);

  rb_thread_call_without_gvl(options_call_without_gvl, &arguments, NULL, NULL);

  RB_GC_GUARD(options);

  return unwrap(arguments.result);
}

struct session_call_arguments {
  struct TsrsSession *session;
  const char *options;
  struct TsrsResult result;
};

static void session_free(void *data) {
  tsrs_session_free((struct TsrsSession *) data);
}

static const rb_data_type_t session_type = {
  "Tsrs::Backend::SessionHandle",
  { NULL, session_free, NULL },
  NULL,
  NULL,
  RUBY_TYPED_FREE_IMMEDIATELY,
};

static struct TsrsSession *session_of(VALUE handle) {
  struct TsrsSession *session = (struct TsrsSession *) rb_check_typeddata(handle, &session_type);

  if (!session) rb_raise(rb_eInternalError, "the session is gone");

  return session;
}

static void *session_call_without_gvl(void *data) {
  struct session_call_arguments *arguments = (struct session_call_arguments *) data;

  arguments->result = tsrs_session_check(arguments->session, arguments->options);

  return NULL;
}

static VALUE rb_session_new(VALUE self, VALUE cwd) {
  (void) self;

  struct TsrsSession *session = tsrs_session_new(StringValueCStr(cwd));

  if (!session) rb_raise(rb_eInternalError, "tsrs could not start a session");

  return TypedData_Wrap_Struct(rb_cSessionHandle, &session_type, session);
}

static VALUE rb_session_check(VALUE self, VALUE handle, VALUE options) {
  (void) self;

  struct session_call_arguments arguments;

  arguments.options = StringValueCStr(options);
  arguments.session = tsrs_session_retain(session_of(handle));

  rb_thread_call_without_gvl(session_call_without_gvl, &arguments, NULL, NULL);

  tsrs_session_free(arguments.session);

  RB_GC_GUARD(handle);
  RB_GC_GUARD(options);

  return unwrap(arguments.result);
}

static VALUE rb_session_close(VALUE self, VALUE handle) {
  (void) self;

  tsrs_session_close(session_of(handle));

  return Qnil;
}

static VALUE rb_transpile(VALUE self, VALUE source, VALUE options) {
  (void) self;

  return source_call(tsrs_transpile, source, options);
}

static VALUE rb_transpile_declaration(VALUE self, VALUE source, VALUE options) {
  (void) self;

  return source_call(tsrs_transpile_declaration, source, options);
}

static VALUE rb_check(VALUE self, VALUE options) {
  (void) self;

  return options_call(tsrs_check, options);
}

static VALUE rb_panic_for_test(VALUE self) {
  (void) self;

  return unwrap(tsrs_panic_for_test());
}

static VALUE rb_native_version(VALUE self) {
  (void) self;

  return take_utf8_string(tsrs_version());
}

static VALUE rb_tsrs_version(VALUE self) {
  (void) self;

  return take_utf8_string(tsrs_tsrs_version());
}

static VALUE rb_typescript_version(VALUE self) {
  (void) self;

  return take_utf8_string(tsrs_typescript_version());
}

void Init_tsrs(void) {
  rb_mTsrs = rb_define_module("Tsrs");
  rb_mBackend = rb_define_module_under(rb_mTsrs, "Backend");

  rb_eError = rb_define_class_under(rb_mTsrs, "Error", rb_eStandardError);
  rb_eOptionError = rb_define_class_under(rb_mTsrs, "OptionError", rb_eError);
  rb_eTsrsEncodingError = rb_define_class_under(rb_mTsrs, "EncodingError", rb_eError);
  rb_eTranspileError = rb_define_class_under(rb_mTsrs, "TranspileError", rb_eError);
  rb_eInternalError = rb_define_class_under(rb_mTsrs, "InternalError", rb_eError);
  rb_ePanicError = rb_define_class_under(rb_mTsrs, "PanicError", rb_eInternalError);
  rb_eCheckError = rb_define_class_under(rb_mTsrs, "CheckError", rb_eError);

  rb_cSessionHandle = rb_define_class_under(rb_mBackend, "SessionHandle", rb_cObject);
  rb_undef_alloc_func(rb_cSessionHandle);

  rb_define_singleton_method(rb_mBackend, "transpile", rb_transpile, 2);
  rb_define_singleton_method(rb_mBackend, "transpile_declaration", rb_transpile_declaration, 2);
  rb_define_singleton_method(rb_mBackend, "check", rb_check, 1);
  rb_define_singleton_method(rb_mBackend, "session_new", rb_session_new, 1);
  rb_define_singleton_method(rb_mBackend, "session_check", rb_session_check, 2);
  rb_define_singleton_method(rb_mBackend, "session_close", rb_session_close, 1);
  rb_define_singleton_method(rb_mBackend, "panic_for_test", rb_panic_for_test, 0);
  rb_define_singleton_method(rb_mBackend, "version", rb_native_version, 0);
  rb_define_singleton_method(rb_mBackend, "tsrs_version", rb_tsrs_version, 0);
  rb_define_singleton_method(rb_mBackend, "typescript_version", rb_typescript_version, 0);
}
