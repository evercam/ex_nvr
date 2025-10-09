#include "camera_capture.h"
#include <libavcodec/avcodec.h>
#include <stdio.h>

#if defined(WIN32) || defined(_WIN32) || defined(__WIN32__) || defined(__NT__)
const char *driver = "dshow";
#elif __APPLE__
const char *driver = "avfoundation";
#elif __linux__
const char *driver = "v4l2";
#endif

ErlNifResourceType *camera_capture_resource_type = NULL;

ERL_NIF_TERM open_camera(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary url_bin, framerate_bin;
    ERL_NIF_TERM ret;
    AVDictionary *options = NULL;
    char url[256];
    char framerate[32];

    if (argc != 2) {
        return enif_make_badarg(env);
    }

    if (!enif_inspect_binary(env, argv[0], &url_bin) || url_bin.size >= sizeof(url)) {
        return enif_make_badarg(env);
    }
    memcpy(url, url_bin.data, url_bin.size);
    url[url_bin.size] = '\0';

    if (!enif_inspect_binary(env, argv[1], &framerate_bin) || framerate_bin.size >= sizeof(framerate)) {
        return enif_make_badarg(env);
    }
    memcpy(framerate, framerate_bin.data, framerate_bin.size);
    framerate[framerate_bin.size] = '\0';

    CameraCapture *state = enif_alloc_resource(camera_capture_resource_type, sizeof(CameraCapture));
    state->input_ctx = NULL;
    state->decoder = NULL;
    state->video_converter = NULL;
    state->packet = NULL;

    avdevice_register_all();

    const AVInputFormat *input_format = av_find_input_format(driver);
    if (input_format == NULL) {
        ret = nif_error(env, "input_format_not_found");
        goto clean;
    }

    av_dict_set(&options, "framerate", framerate, 0);
    av_dict_set(&options, "pixel_format", "yuv420p", 0);

    if (avformat_open_input(&state->input_ctx, url, input_format, &options) < 0) {
        avformat_close_input(&state->input_ctx);
        ret = nif_error(env, "open_failed");
        goto clean;
    }

    if (avformat_find_stream_info(state->input_ctx, NULL) < 0) {
        avformat_close_input(&state->input_ctx);
        ret = nif_error(env, "find_stream_info_failed");
        goto clean;
    }

    if (state->input_ctx->nb_streams == 0) {
        ret = nif_error(env, "no_streams_found");
        goto clean;
    }

    // Init video converter if the pixel format is not yuv420p
    AVCodecParameters *codec_params = state->input_ctx->streams[0]->codecpar;
    state->decoder = decoder_alloc();
    if (decoder_init_by_parameters(state->decoder, codec_params) < 0) {
        ret = nif_error(env, "decoder_init_failed");
        goto clean;
    }

    if (codec_params->format != AV_PIX_FMT_YUV420P) {
        state->video_converter = video_converter_alloc();
        if (video_converter_init(state->video_converter,
                                 codec_params->width,
                                 codec_params->height,
                                 codec_params->format,
                                 codec_params->width,
                                 codec_params->height,
                                 AV_PIX_FMT_YUV420P, 0) < 0) {
            ret = nif_error(env, "video_converter_init_failed");
            goto clean;
        }
    } else {
        state->video_converter = NULL;
    }

    state->packet = av_packet_alloc();
    if (!state->packet) {
        ret = nif_error(env, "packet_alloc_failed");
        goto clean;
    }

    ret = nif_ok(env, enif_make_resource(env, state));
clean:
    if (options != NULL) av_dict_free(&options);
    enif_release_resource(state);

    return ret;
}

ERL_NIF_TERM read_camera_frame(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ERL_NIF_TERM ret;
    CameraCapture *state;
    AVFrame *frame = NULL;

    if (argc != 1 ||
        !enif_get_resource(env, argv[0], camera_capture_resource_type, (void **)&state)) {
        return enif_make_badarg(env);
    }

    int res;
    while ((res = av_read_frame(state->input_ctx, state->packet)) == AVERROR(EAGAIN));

    if (res < 0) {
        char error_buf[AV_ERROR_MAX_STRING_SIZE];
        av_strerror(res, error_buf, sizeof(error_buf));
        return nif_error(env, error_buf);
    }

    if (decoder_decode(state->decoder, state->packet) < 0) {
        ret = nif_error(env, "decode_failed");
        goto clean;
    }

    frame = state->decoder->frames[0];

    if (state->video_converter != NULL) {
        if (video_converter_convert(state->video_converter, frame) < 0) {
            ret = nif_error(env, "convert_failed");
            goto clean;
        }

        AVFrame *converted_frame = state->video_converter->frame;
        ret = nif_ok(env, nif_frame_to_term(env, converted_frame));
        av_frame_unref(converted_frame);
    } else {
        ret = nif_ok(env, nif_frame_to_term(env, frame));
    }

clean:
    av_packet_unref(state->packet);
    if (frame != NULL) av_frame_unref(frame);

    return ret;
}

void camera_capture_destructor(ErlNifEnv *env, void *obj) {
    CameraCapture *state = (CameraCapture *)obj;
    if (state->input_ctx != NULL) {
        avformat_close_input(&state->input_ctx);
    }

    if (state->packet != NULL) {
        av_packet_free(&state->packet);
    }

    if (state->decoder != NULL) {
        decoder_free(&state->decoder);
    }

    if (state->video_converter != NULL) {
        video_converter_free(&state->video_converter);
    }
}

static ErlNifFunc funcs[] = {
  {"open_camera", 2, open_camera},
  {"read_camera_frame", 1, read_camera_frame, ERL_DIRTY_JOB_CPU_BOUND}
};

static int load(ErlNifEnv *env, void **priv, ERL_NIF_TERM load_info) {
  camera_capture_resource_type = enif_open_resource_type(
    env, NULL, "camera_capture_resource", camera_capture_destructor,
    ERL_NIF_RT_CREATE, NULL);

  return 0;
}

ERL_NIF_INIT(Elixir.ExNVR.AV.CameraCapture.NIF, funcs, &load, NULL, NULL, NULL);
