#pragma once

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wall" 
#pragma GCC diagnostic ignored "-Wextra" 
#include <erl_nif.h>
#include <libavdevice/avdevice.h>
#include <libavformat/avformat.h>
#include <libavutil/pixdesc.h>
#include <string.h>

#pragma GCC diagnostic pop

typedef struct State {
  AVFormatContext *input_ctx;
} State;

ERL_NIF_TERM do_open(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]);
ERL_NIF_TERM read_frame(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]); 
ERL_NIF_TERM stream_props(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]);
void camera_capture_destructor(ErlNifEnv *env, void *obj);
extern ErlNifResourceType* camera_capture_resource_type;
extern const char *driver;

