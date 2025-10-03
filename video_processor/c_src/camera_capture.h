#pragma once

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wall" 
#pragma GCC diagnostic ignored "-Wextra" 
#include <libavdevice/avdevice.h>
#include <libavformat/avformat.h>
#include <libavutil/pixdesc.h>

#include <string.h>
#include "utils.h"

#pragma GCC diagnostic pop

typedef struct {
    AVFormatContext *input_ctx;
} CameraCaptureState;



ERL_NIF_TERM open_camera(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]);
ERL_NIF_TERM read_camera_frame(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]); 
ERL_NIF_TERM camera_stream_props(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]);
void camera_capture_destructor(ErlNifEnv *env, void *obj);
extern ErlNifResourceType* camera_capture_resource_type;
extern const char *driver;

