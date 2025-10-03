#include "pixel_converter.h"
#include "utils.h"

ErlNifResourceType *converter_state_type = NULL;

enum AVPixelFormat string_to_AVPixelFormat(const char *format);

ERL_NIF_TERM nif_create(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    int width, height;
    char old_format[16], new_format[16];

    if (!enif_get_int(env, argv[0], &width) ||
        !enif_get_int(env, argv[1], &height) ||
        !enif_get_string(env, argv[2], old_format, sizeof(old_format), ERL_NIF_LATIN1) ||
        !enif_get_string(env, argv[3], new_format, sizeof(new_format), ERL_NIF_LATIN1)) {
        return nif_error(env, "bad_arguments");
    }

    enum AVPixelFormat input_fmt = string_to_AVPixelFormat(old_format);
    enum AVPixelFormat output_fmt = string_to_AVPixelFormat(new_format);

    if (input_fmt == AV_PIX_FMT_NONE) return nif_error(env, "unknown_input_format");
    if (!sws_isSupportedInput(input_fmt)) return nif_error(env, "unsupported_input_format");
    if (output_fmt == AV_PIX_FMT_NONE) return nif_error(env, "unknown_output_format");
    if (!sws_isSupportedOutput(output_fmt)) return nif_error(env, "unsupported_output_format");

    ConverterState *state = enif_alloc_resource(converter_state_type, sizeof(ConverterState));
    state->width = width;
    state->height = height;
    state->src_format = input_fmt;
    state->dst_format = output_fmt;

    state->sws_context = sws_getContext(width, height, input_fmt,
                                        width, height, output_fmt,
                                        SWS_BICUBIC, NULL, NULL, NULL);

    if (!state->sws_context) {
        enif_release_resource(state);
        return nif_error(env, "create_context_failed");
    }

    if (av_image_alloc(state->dst_data, state->dst_linesize,
                       width, height, output_fmt, ALIGNMENT) < 0) {
        sws_freeContext(state->sws_context);
        enif_release_resource(state);
        return nif_error(env, "memory_allocation_failed");
    }

    ERL_NIF_TERM term = enif_make_resource(env, state);

    return nif_ok(env, term);
}

ERL_NIF_TERM nif_process(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ConverterState *state;
    ErlNifBinary input;

    if (!enif_get_resource(env, argv[0], converter_state_type, (void **)&state)) {
        return nif_error(env, "invalid_state");
    }

    if (!enif_inspect_binary(env, argv[1], &input)) {
        return nif_error(env, "bad_input_binary");
    }

    if (av_image_fill_arrays(state->src_data, state->src_linesize, input.data,
                             state->src_format, state->width, state->height, 1) < 0) {
        return nif_error(env, "fill_arrays_failed");
    }

    if (sws_scale(state->sws_context, (const uint8_t *const *)state->src_data,
                  state->src_linesize, 0, state->height,
                  state->dst_data, state->dst_linesize) < 0) {
        return nif_error(env, "scaling_failed");
    }

    int dst_size = av_image_get_buffer_size(state->dst_format, state->width,
                                            state->height, NO_ALIGNMENT);
    ERL_NIF_TERM bin_term;
    unsigned char *dst_bin = enif_make_new_binary(env, dst_size, &bin_term);

    if (av_image_copy_to_buffer(dst_bin, dst_size,
                                (const uint8_t *const *)state->dst_data,
                                state->dst_linesize,
                                state->dst_format,
                                state->width, state->height, NO_ALIGNMENT) < 0) {
        return nif_error(env, "copy_to_buffer_failed");
    }

    return enif_make_tuple2(env, enif_make_atom(env, "ok"), bin_term);
}

void pixel_converter_resource_structor(ErlNifEnv *env, void *obj) {
    ConverterState *state = (ConverterState *)obj;
    if (state->sws_context) sws_freeContext(state->sws_context);
    av_freep(&state->dst_data[0]);
}
// only supported pixels for now

enum AVPixelFormat string_to_AVPixelFormat(const char *format) {
    if (strcmp(format, "I420") == 0) return AV_PIX_FMT_YUV420P;
    if (strcmp(format, "I422") == 0) return AV_PIX_FMT_YUV422P;
    if (strcmp(format, "I444") == 0) return AV_PIX_FMT_YUV444P;
    if (strcmp(format, "RGB") == 0) return AV_PIX_FMT_RGB24;
    if (strcmp(format, "RGBA") == 0) return AV_PIX_FMT_RGBA;
    if (strcmp(format, "NV12") == 0) return AV_PIX_FMT_NV12;
    if (strcmp(format, "NV21") == 0) return AV_PIX_FMT_NV21;
    if (strcmp(format, "YUY2") == 0) return AV_PIX_FMT_YUYV422;
    return AV_PIX_FMT_NONE;
}


