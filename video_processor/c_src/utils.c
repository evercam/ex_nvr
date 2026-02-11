#include "utils.h"

ERL_NIF_TERM nif_ok(ErlNifEnv *env, ERL_NIF_TERM data_term) {
  ERL_NIF_TERM ok_term = enif_make_atom(env, "ok");
  return enif_make_tuple(env, 2, ok_term, data_term);
}

ERL_NIF_TERM nif_error(ErlNifEnv *env, char *reason) {
  ERL_NIF_TERM error_term = enif_make_atom(env, "error");
  ERL_NIF_TERM reason_term = enif_make_atom(env, reason);
  return enif_make_tuple(env, 2, error_term, reason_term);
}

ERL_NIF_TERM nif_raise(ErlNifEnv *env, char *msg) {
  ERL_NIF_TERM reason = enif_make_atom(env, msg);
  return enif_raise_exception(env, reason);
}

int nif_get_atom(ErlNifEnv *env, ERL_NIF_TERM term, char **value) {
  unsigned int atom_len;
  if (!enif_get_atom_length(env, term, &atom_len, ERL_NIF_LATIN1)) {
    return 0;
  }

  char *atom_value = (char *)enif_alloc((atom_len + 1) * sizeof(char *));
  if (!enif_get_atom(env, term, atom_value, atom_len + 1, ERL_NIF_LATIN1)) {
    enif_free(atom_value);
    return 0;
  }

  *value = atom_value;
  return 1;
}

int nif_get_string(ErlNifEnv *env, ERL_NIF_TERM term, char **value) {
  ErlNifBinary bin;
  if (!enif_inspect_binary(env, term, &bin)) {
    return 0;
  }

  char *str_value = (char *)enif_alloc((bin.size + 1) * sizeof(char *));
  memcpy(str_value, bin.data, bin.size);
  str_value[bin.size] = '\0';

  *value = str_value;
  return 1;
}

ERL_NIF_TERM nif_frame_to_term(ErlNifEnv *env, AVFrame *frame) {
  ERL_NIF_TERM data_term;

  int payload_size =
      av_image_get_buffer_size(frame->format, frame->width, frame->height, 1);
  unsigned char *ptr = enif_make_new_binary(env, payload_size, &data_term);

  av_image_copy_to_buffer(ptr, payload_size,
                          (const uint8_t *const *)frame->data,
                          (const int *)frame->linesize, frame->format,
                          frame->width, frame->height, 1);

  ERL_NIF_TERM format_term =
      enif_make_atom(env, av_get_pix_fmt_name(frame->format));
  ERL_NIF_TERM height_term = enif_make_int(env, frame->height);
  ERL_NIF_TERM width_term = enif_make_int(env, frame->width);
  ERL_NIF_TERM pts_term = enif_make_int64(env, frame->pts);
  return enif_make_tuple(env, 5, data_term, format_term, width_term,
                         height_term, pts_term);
}
