#include "camera_capture.h"

#if defined(WIN32) || defined(_WIN32) || defined(__WIN32__) || defined(__NT__)
const char *driver = "dshow";
#elif __APPLE__
const char *driver = "avfoundation";
#elif __linux__
const char *driver = "v4l2";
#endif

ErlNifResourceType *camera_capture_resource_type = NULL;

ERL_NIF_TERM do_open(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary url_bin, framerate_bin;
    ERL_NIF_TERM ret;
    char url[256];
    char framerate[32];

    AVDictionary *options = NULL;

    if (argc != 2) {
        return enif_make_badarg(env);
    }

    // Get URL binary
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

    avdevice_register_all();

    CameraCapture *state = enif_alloc_resource(camera_capture_resource_type, sizeof(CameraCapture));
    state->input_ctx = NULL;

    AVInputFormat *input_format = av_find_input_format(driver);
    if (input_format == NULL) {
        ret = nif_error(env, "Could not open input");
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

    ret = nif_ok(env, enif_make_resource(env, state));
clean:
    if (options != NULL) av_dict_free(&options);
    enif_release_resource(state);

    return ret;
}

ERL_NIF_TERM read_frame(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    CameraCapture *state;

    if (argc != 1 ||
        !enif_get_resource(env, argv[0], camera_capture_resource_type, (void **)&state)) {
        return enif_make_badarg(env);
    }

    AVPacket *packet = av_packet_alloc();
    if (!packet) {
        return nif_error(env, "Could not allocate packet");
    }

    int res;
    while ((res = av_read_frame(state->input_ctx, packet)) == AVERROR(EAGAIN));

    if (res < 0) {
        char error_buf[AV_ERROR_MAX_STRING_SIZE];
        av_strerror(res, error_buf, sizeof(error_buf));
        av_packet_free(&packet);
        return nif_error(env, error_buf);
    }

    ERL_NIF_TERM binary_term;
    unsigned char *binary_data = enif_make_new_binary(env, packet->size, &binary_term);
    memcpy(binary_data, packet->data, packet->size);

    av_packet_free(&packet);

    return nif_ok(env, binary_term);
}

ERL_NIF_TERM stream_props(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    CameraCapture *state;

    if (argc != 1 ||
        !enif_get_resource(env, argv[0], camera_capture_resource_type, (void **)&state)) {
        return enif_make_badarg(env);
    }

    AVCodecParameters *codec_params = state->input_ctx->streams[0]->codecpar;
    const char *pix_fmt_name = av_get_pix_fmt_name(codec_params->format);

    ERL_NIF_TERM props = enif_make_tuple3(env,
        enif_make_int(env, codec_params->width),
        enif_make_int(env, codec_params->height),
        enif_make_string(env, pix_fmt_name ? pix_fmt_name : "unknown", ERL_NIF_LATIN1));

    return nif_ok(env, props);
}

void camera_capture_destructor(ErlNifEnv *env, void *obj) {
    CameraCapture *state = (CameraCapture *)obj;
    if (state->input_ctx != NULL) {
        avformat_close_input(&state->input_ctx);
    }
}
