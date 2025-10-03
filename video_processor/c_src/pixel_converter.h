#pragma once

#include <libavutil/error.h>
#include <libavutil/frame.h>
#include <libavutil/imgutils.h>
#include <libswscale/swscale.h>
#include <string.h>
#include <erl_nif.h>

typedef struct {
    struct SwsContext *sws_context;
    uint64_t width;
    uint64_t height;
    enum AVPixelFormat src_format;
    enum AVPixelFormat dst_format;
    uint8_t *dst_data[4];
    int dst_linesize[4];
    uint8_t *src_data[4];
    int src_linesize[4];
} ConverterState;

ERL_NIF_TERM nif_process(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]);

ERL_NIF_TERM nif_create(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]);

void pixel_converter_resource_structor(ErlNifEnv *env, void *obj);
extern ErlNifResourceType *converter_state_type;

#define ALIGNMENT 32
#define NO_ALIGNMENT 1


