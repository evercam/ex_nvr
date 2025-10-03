#include "camera_capture.h"

#if defined(WIN32) || defined(_WIN32) || defined(__WIN32__) || defined(__NT__)
const char *driver = "dshow";
#elif __APPLE__
const char *driver = "avfoundation";
#elif __linux__
const char *driver = "v4l2";
#endif

ErlNifResourceType *camera_capture_resource_type = NULL;

// Resource destructor
void camera_capture_destructor(ErlNifEnv *env, void *obj) {
    CameraCaptureState *state = (CameraCaptureState *)obj;
    if (state->input_ctx != NULL) {
        avformat_close_input(&state->input_ctx);
    }
}

ERL_NIF_TERM open_camera(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary url_bin, framerate_bin;
    char url[256];
    char framerate[32];
    
    if (argc != 2) {
        return enif_make_badarg(env);
    }

    // Get URL binary
    if (!enif_inspect_binary(env, argv[0], &url_bin) || url_bin.size >= sizeof(url)) {
        return enif_make_badarg(env);
    }
    memcpy(url, url_bin.data, url_bin.size);
    url[url_bin.size] = '\0';

    // Get framerate binary
    if (!enif_inspect_binary(env, argv[1], &framerate_bin) || framerate_bin.size >= sizeof(framerate)) {
        return enif_make_badarg(env);
    }
    memcpy(framerate, framerate_bin.data, framerate_bin.size);
    framerate[framerate_bin.size] = '\0';

    avdevice_register_all();

    CameraCaptureState *state = enif_alloc_resource(camera_capture_resource_type, 
                                                     sizeof(CameraCaptureState));
    state->input_ctx = NULL;

    const AVInputFormat *input_format = av_find_input_format(driver);
    if (input_format == NULL) {
        enif_release_resource(state);
        return nif_error(env, "Could not open input");
    }

    AVDictionary *options = NULL;
    av_dict_set(&options, "framerate", framerate, 0);
    // yuv420p as default -> if supported we can skip alll the pixel convertion
    av_dict_set(&options, "pixel_format", "yuv420p", 0);  

    if (avformat_open_input(&state->input_ctx, url, input_format, &options) < 0) {
        av_dict_free(&options);
        enif_release_resource(state);
        return nif_error(env, "Could not open supplied url");
    }
    av_dict_free(&options);

    if (avformat_find_stream_info(state->input_ctx, NULL) < 0) {
        avformat_close_input(&state->input_ctx);
        enif_release_resource(state);
        return nif_error(env, "Couldn't get stream info");
    }

    if (state->input_ctx->nb_streams == 0) {
        avformat_close_input(&state->input_ctx);
        enif_release_resource(state);
        return nif_error(env, "No streams found - at least one is required");
    }

    ERL_NIF_TERM resource_term = enif_make_resource(env, state);
    enif_release_resource(state);

    return nif_ok(env, resource_term);
}

ERL_NIF_TERM read_camera_frame(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    CameraCaptureState *state;
    
    if (argc != 1 || 
        !enif_get_resource(env, argv[0], camera_capture_resource_type, (void **)&state)) {
        return enif_make_badarg(env);
    }

    AVPacket *packet =(AVPacket *) malloc(sizeof(AVPacket));
    if (!packet) {
        return nif_error(env, "Could not allocate packet");
    }

    int res;
    while ((res = av_read_frame(state->input_ctx, packet)) == AVERROR(EAGAIN))
        ;

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

 ERL_NIF_TERM camera_stream_props(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    CameraCaptureState *state;
    
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


static ErlNifFunc nif_funcs[] = {
    {"open_camera", 2, open_camera, 0},
    {"read_camera_frame", 1, read_camera_frame, ERL_DIRTY_JOB_CPU_BOUND},
    {"camera_stream_props", 1, camera_stream_props, 0}
};

static int load(ErlNifEnv *env, void **priv_data, ERL_NIF_TERM load_info) {
    camera_capture_resource_type = enif_open_resource_type(
        env,
        NULL,
        "camera_capture_resource",
        camera_capture_destructor,
        ERL_NIF_RT_CREATE,
        NULL);

    if (camera_capture_resource_type == NULL) {
        return -1;
    }

    return 0;
}

ERL_NIF_INIT(Elixir.ExNVR.AV.CameraCapture.NIF, nif_funcs, load, NULL, NULL, NULL)

