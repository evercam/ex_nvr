#ifndef NVR_ENCODER_H
#define NVR_ENCODER_H

#include "nvr_encoder.h"
#include <libavutil/imgutils.h>

ErlNifResourceType *encoder_resource_type;

static int get_profile(enum AVCodecID, const char *);
static ERL_NIF_TERM packets_to_term(ErlNifEnv *env, struct Encoder *encoder);
static ERL_NIF_TERM nif_packet_to_term(ErlNifEnv *env, AVPacket *packet);

ERL_NIF_TERM new (ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 2) {
    return nif_raise(env, "invalid_arg_count");
  }

  ERL_NIF_TERM ret;
  struct EncoderConfig encoder_config = {0};
  encoder_config.max_b_frames = -1;
  encoder_config.profile = FF_PROFILE_UNKNOWN;

  char *codec_name = NULL, *format = NULL, *profile = NULL;

  ErlNifMapIterator iter;
  ERL_NIF_TERM key, value;
  char *config_name = NULL;
  int err;

  if (!nif_get_atom(env, argv[0], &codec_name)) {
    return nif_raise(env, "failed_to_get_atom");
  }

  if (!enif_is_map(env, argv[1])) {
    return nif_raise(env, "failed_to_get_map");
  }

  enif_map_iterator_create(env, argv[1], &iter, ERL_NIF_MAP_ITERATOR_FIRST);

  while (enif_map_iterator_get_pair(env, &iter, &key, &value)) {
    if (!nif_get_atom(env, key, &config_name)) {
      ret = nif_raise(env, "failed_to_get_map_key");
      goto clean;
    }

    if (strcmp(config_name, "width") == 0) {
      err = enif_get_int(env, value, &encoder_config.width);
    } else if (strcmp(config_name, "height") == 0) {
      err = enif_get_int(env, value, &encoder_config.height);
    } else if (strcmp(config_name, "format") == 0) {
      err = nif_get_atom(env, value, &format);
    } else if (strcmp(config_name, "time_base_num") == 0) {
      err = enif_get_int(env, value, &encoder_config.time_base.num);
    } else if (strcmp(config_name, "time_base_den") == 0) {
      err = enif_get_int(env, value, &encoder_config.time_base.den);
    } else if (strcmp(config_name, "gop_size") == 0) {
      err = enif_get_int(env, value, &encoder_config.gop_size);
    } else if (strcmp(config_name, "max_b_frames") == 0) {
      err = enif_get_int(env, value, &encoder_config.max_b_frames);
    } else if (strcmp(config_name, "profile") == 0) {
      err = nif_get_string(env, value, &profile);
    } else {
      ret = nif_raise(env, "unknown_config_key");
      goto clean;
    }

    if (!err) {
      ret = nif_raise(env, "couldnt_read_value");
      goto clean;
    }

    enif_free(config_name);
    enif_map_iterator_next(env, &iter);
  }

  if (strcmp(codec_name, "h264") == 0) {
    encoder_config.codec = avcodec_find_encoder(AV_CODEC_ID_H264);
  } else if (strcmp(codec_name, "mjpeg") == 0) {
    encoder_config.codec = avcodec_find_encoder(AV_CODEC_ID_MJPEG);
  } else {
    ret = nif_raise(env, "unknown_codec");
    goto clean;
  }

  if (!encoder_config.codec) {
    ret = nif_raise(env, "unknown_codec");
    goto clean;
  }

  encoder_config.format = av_get_pix_fmt(format);
  if (encoder_config.format == AV_PIX_FMT_NONE) {
    ret = nif_raise(env, "unknown_format");
    goto clean;
  }

  if (profile) {
    encoder_config.profile = get_profile(encoder_config.codec->id, profile);
    if (encoder_config.profile == FF_PROFILE_UNKNOWN) {
      ret = nif_raise(env, "invalid_profile");
      goto clean;
    }
  }

  struct NvrEncoder *nvr_encoder =
      enif_alloc_resource(encoder_resource_type, sizeof(struct NvrEncoder));

  nvr_encoder->encoder = encoder_alloc();
  nvr_encoder->frame = av_frame_alloc();

  if (encoder_init(nvr_encoder->encoder, &encoder_config) < 0) {
    ret = nif_raise(env, "failed_to_init_encoder");
    goto clean;
  }

  ret = enif_make_resource(env, nvr_encoder);
  enif_release_resource(nvr_encoder);

clean:
  // clean encoder
  if (!codec_name)
    enif_free(codec_name);
  if (!format)
    enif_free(format);
  if (!config_name)
    enif_free(config_name);
  if (!profile)
    enif_free(profile);
  enif_map_iterator_destroy(env, &iter);

  return ret;
}

ERL_NIF_TERM encode(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  int ret;

  if (argc != 3) {
    return nif_raise(env, "invalid_arg_count");
  }

  struct NvrEncoder *nvr_encoder;
  if (!enif_get_resource(env, argv[0], encoder_resource_type,
                         (void **)&nvr_encoder)) {
    return nif_raise(env, "invalid_resource");
  }

  ErlNifBinary input;
  if (!enif_inspect_binary(env, argv[1], &input)) {
    return nif_raise(env, "failed_to_inspect_binary");
  }

  int pts;
  if (!enif_get_int(env, argv[2], &pts)) {
    return nif_raise(env, "failed_to_get_int");
  }

  AVFrame *frame = nvr_encoder->frame;
  frame->width = nvr_encoder->encoder->c->width;
  frame->height = nvr_encoder->encoder->c->height;
  frame->format = nvr_encoder->encoder->c->pix_fmt;
  frame->pts = pts;

  ret = av_image_fill_arrays(frame->data, frame->linesize, input.data,
                             frame->format, frame->width, frame->height, 1);
  if (ret < 0) {
    return nif_raise(env, "failed_to_fill_arrays");
  }

  if (encoder_encode(nvr_encoder->encoder, frame) < 0) {
    return nif_raise(env, "failed_to_encode");
  }

  return packets_to_term(env, nvr_encoder->encoder);
}

ERL_NIF_TERM flush(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 1) {
    return nif_raise(env, "invalid_arg_count");
  }

  struct NvrEncoder *nvr_encoder;
  if (!enif_get_resource(env, argv[0], encoder_resource_type,
                         (void **)&nvr_encoder)) {
    return nif_raise(env, "invalid_resource");
  }

  int ret = encoder_encode(nvr_encoder->encoder, NULL);
  if (ret < 0) {
    return nif_raise(env, "failed_to_encode");
  }

  return packets_to_term(env, nvr_encoder->encoder);
}

static int get_profile(enum AVCodecID codec, const char *profile_name) {
  const AVCodecDescriptor *desc = avcodec_descriptor_get(codec);
  const AVProfile *profile = desc->profiles;

  if (profile == NULL) {
    return FF_PROFILE_UNKNOWN;
  }

  while (profile->profile != FF_PROFILE_UNKNOWN) {
    if (strcmp(profile->name, profile_name) == 0) {
      break;
    }

    profile++;
  }

  return profile->profile;
}

static ERL_NIF_TERM packets_to_term(ErlNifEnv *env, Encoder *encoder) {
  ERL_NIF_TERM ret;
  ERL_NIF_TERM *packets =
      enif_alloc(sizeof(ERL_NIF_TERM) * encoder->num_packets);
  for (int i = 0; i < encoder->num_packets; i++) {
    packets[i] = nif_packet_to_term(env, encoder->packets[i]);
  }

  ret = enif_make_list_from_array(env, packets, encoder->num_packets);

  for (int i = 0; i < encoder->num_packets; i++)
    av_packet_unref(encoder->packets[i]);
  enif_free(packets);

  return ret;
}

static ERL_NIF_TERM nif_packet_to_term(ErlNifEnv *env, AVPacket *packet) {
  ERL_NIF_TERM data_term;

  unsigned char *ptr = enif_make_new_binary(env, packet->size, &data_term);

  memcpy(ptr, packet->data, packet->size);

  ERL_NIF_TERM dts = enif_make_int(env, packet->dts);
  ERL_NIF_TERM pts = enif_make_int(env, packet->pts);
  ERL_NIF_TERM is_keyframe =
      enif_make_atom(env, packet->flags & AV_PKT_FLAG_KEY ? "true" : "false");
  return enif_make_tuple(env, 4, data_term, dts, pts, is_keyframe);
}

void free_encoder(ErlNifEnv *env, void *obj) {
  NVR_LOG_DEBUG("Freeing Encoder object");
  struct NvrEncoder *nvr_encoder = (struct NvrEncoder *)obj;

  encoder_free(nvr_encoder->encoder);

  if (nvr_encoder->frame != NULL) {
    av_frame_free(&nvr_encoder->frame);
  }
}

static ErlNifFunc funcs[] = {{"new", 2, new},
                             {"encode", 3, encode, ERL_DIRTY_JOB_CPU_BOUND},
                             {"flush", 1, flush, ERL_DIRTY_JOB_CPU_BOUND}};

static int load(ErlNifEnv *env, void **priv, ERL_NIF_TERM load_info) {
  encoder_resource_type = enif_open_resource_type(
      env, NULL, "NvrEncoder", free_encoder, ERL_NIF_RT_CREATE, NULL);
  return 0;
}

ERL_NIF_INIT(Elixir.ExNVR.AV.Encoder.NIF, funcs, &load, NULL, NULL, NULL);

#endif // NVR_ENCODER_H