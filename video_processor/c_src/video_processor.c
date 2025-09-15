#ifndef NVR_ENCODER_H
#define NVR_ENCODER_H

#include "video_processor.h"
#include <libavutil/imgutils.h>

ErlNifResourceType *encoder_resource_type;
ErlNifResourceType *decoder_resource_type;

static int get_profile(enum AVCodecID, const char *);
static ERL_NIF_TERM packets_to_term(ErlNifEnv *env, Encoder *encoder);
static ERL_NIF_TERM frames_to_term(ErlNifEnv *env, Decoder *encoder);
static ERL_NIF_TERM nif_packet_to_term(ErlNifEnv *env, AVPacket *packet);
static ERL_NIF_TERM nif_frame_to_term(ErlNifEnv *env, AVFrame *frame);
static int convert_frames(struct NvrDecoder *);

ERL_NIF_TERM new_encoder(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
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

ERL_NIF_TERM new_decoder(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 5) {
    return nif_raise(env, "invalid_arg_count");
  }

  ERL_NIF_TERM ret;
  char *codec_name = NULL, *out_format = NULL;
  const AVCodec *codec = NULL;
  int out_width, out_height, pad;

  if (!nif_get_atom(env, argv[0], &codec_name)) {
    return nif_raise(env, "failed_to_get_atom");
  }

  if (strcmp(codec_name, "h264") == 0) {
    codec = avcodec_find_decoder(AV_CODEC_ID_H264);
  } else if (strcmp(codec_name, "hevc") == 0) {
    codec = avcodec_find_decoder(AV_CODEC_ID_HEVC);
  }

  if (!codec) {
    ret = nif_raise(env, "unknown_codec");
    goto clean;
  }

  if (!enif_get_int(env, argv[1], &out_width)) {
    ret = nif_raise(env, "failed_to_get_int");
    goto clean;
  }

  if (!enif_get_int(env, argv[2], &out_height)) {
    ret = nif_raise(env, "failed_to_get_int");
    goto clean;
  }

  if (!nif_get_atom(env, argv[3], &out_format)) {
    ret = nif_raise(env, "failed_to_get_atom");
    goto clean;
  }

  if (!enif_get_int(env, argv[4], &pad)) {
    ret = nif_raise(env, "failed_to_get_atom");
    goto clean;
  }

  enum AVPixelFormat out_pix_fmt = av_get_pix_fmt(out_format);

  struct NvrDecoder *nvr_decoder =
      enif_alloc_resource(decoder_resource_type, sizeof(struct NvrDecoder));

  nvr_decoder->decoder = decoder_alloc();
  nvr_decoder->packet = av_packet_alloc();
  nvr_decoder->video_converter = NULL;
  nvr_decoder->out_width = out_width;
  nvr_decoder->out_height = out_height;
  nvr_decoder->out_format = out_pix_fmt;
  nvr_decoder->pad = pad;

  if (decoder_init(nvr_decoder->decoder, codec) < 0) {
    ret = nif_raise(env, "failed_to_init_decoder");
    goto clean;
  }

  ret = enif_make_resource(env, nvr_decoder);
  enif_release_resource(nvr_decoder);

clean:
  if (!codec_name)
    enif_free(codec_name);

  if (!out_format)
    enif_free(out_format);

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

  ulong pts;
  if (!enif_get_ulong(env, argv[2], &pts)) {
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

ERL_NIF_TERM decode(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ERL_NIF_TERM frame_term;

  if (argc != 4) {
    return nif_raise(env, "invalid_arg_count");
  }

  struct NvrDecoder *nvr_decoder;
  if (!enif_get_resource(env, argv[0], decoder_resource_type,
                         (void **)&nvr_decoder)) {
    return nif_raise(env, "couldnt_get_decoder_resource");
  }

  ErlNifBinary data;
  if (!enif_inspect_binary(env, argv[1], &data)) {
    return nif_raise(env, "couldnt_inspect_binary");
  }

  ulong pts;
  if (!enif_get_ulong(env, argv[2], &pts)) {
    return nif_raise(env, "couldnt_get_int");
  }

  ulong dts;
  if (!enif_get_ulong(env, argv[3], &dts)) {
    return nif_raise(env, "couldnt_get_int");
  }

  nvr_decoder->packet->data = data.data;
  nvr_decoder->packet->size = data.size;
  nvr_decoder->packet->pts = pts;
  nvr_decoder->packet->dts = dts;

  int ret = decoder_decode(nvr_decoder->decoder, nvr_decoder->packet);
  if (ret < 0) {
    return nif_raise(env, "failed_to_decode");
  }

  if (convert_frames(nvr_decoder) < 0) {
    return nif_raise(env, "failed_to_convert");
  }

  return frames_to_term(env, nvr_decoder->decoder);
}

ERL_NIF_TERM flush_encoder(ErlNifEnv *env, int argc,
                           const ERL_NIF_TERM argv[]) {
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

ERL_NIF_TERM flush_decoder(ErlNifEnv *env, int argc,
                           const ERL_NIF_TERM argv[]) {
  if (argc != 1) {
    return nif_raise(env, "invalid_arg_count");
  }

  struct NvrDecoder *nvr_decoder;
  if (!enif_get_resource(env, argv[0], decoder_resource_type,
                         (void **)&nvr_decoder)) {
    return nif_raise(env, "couldnt_get_decoder_resource");
  }

  if (decoder_flush(nvr_decoder->decoder) < 0) {
    return nif_raise(env, "failed_to_flush");
  }

  if (convert_frames(nvr_decoder) < 0) {
    return nif_raise(env, "failed_to_convert");
  }

  return frames_to_term(env, nvr_decoder->decoder);
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

static int convert_frames(struct NvrDecoder *nvr_decoder) {
  int ret = 0;
  if (nvr_decoder->out_width != -1 || nvr_decoder->out_height != -1 ||
      nvr_decoder->out_format != AV_PIX_FMT_NONE) {
    if (nvr_decoder->video_converter == NULL) {
      AVCodecContext *c = nvr_decoder->decoder->c;
      nvr_decoder->video_converter = video_converter_alloc();
      enum AVPixelFormat out_format = nvr_decoder->out_format == AV_PIX_FMT_NONE
                                          ? c->pix_fmt
                                          : nvr_decoder->out_format;
      ret = video_converter_init(nvr_decoder->video_converter, c->width,
                                 c->height, c->pix_fmt, nvr_decoder->out_width,
                                 nvr_decoder->out_height, out_format, nvr_decoder->pad);
      if (ret < 0)
        return ret;
    }

    struct Decoder *decoder = nvr_decoder->decoder;
    for (int i = 0; i < decoder->count_frames; i++) {
      ret = video_converter_convert(nvr_decoder->video_converter,
                                    decoder->frames[i]);
      if (ret < 0) {
        return ret;
      }
      av_frame_unref(decoder->frames[i]);
      av_frame_ref(decoder->frames[i], nvr_decoder->video_converter->frame);
    }
  }

  return ret;
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

static ERL_NIF_TERM frames_to_term(ErlNifEnv *env, Decoder *decoder) {
  ERL_NIF_TERM ret;
  ERL_NIF_TERM *frames =
      enif_alloc(sizeof(ERL_NIF_TERM) * decoder->count_frames);
  for (int i = 0; i < decoder->count_frames; i++) {
    frames[i] = nif_frame_to_term(env, decoder->frames[i]);
  }

  ret = enif_make_list_from_array(env, frames, decoder->count_frames);

  for (int i = 0; i < decoder->count_frames; i++)
    av_frame_unref(decoder->frames[i]);

  enif_free(frames);

  return ret;
}

static ERL_NIF_TERM nif_packet_to_term(ErlNifEnv *env, AVPacket *packet) {
  ERL_NIF_TERM data_term;

  unsigned char *ptr = enif_make_new_binary(env, packet->size, &data_term);

  memcpy(ptr, packet->data, packet->size);

  ERL_NIF_TERM dts = enif_make_int64(env, packet->dts);
  ERL_NIF_TERM pts = enif_make_int64(env, packet->pts);
  ERL_NIF_TERM is_keyframe =
      enif_make_atom(env, packet->flags & AV_PKT_FLAG_KEY ? "true" : "false");
  return enif_make_tuple(env, 4, data_term, dts, pts, is_keyframe);
}

static ERL_NIF_TERM nif_frame_to_term(ErlNifEnv *env, AVFrame *frame) {
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

void free_encoder(ErlNifEnv *env, void *obj) {
  NVR_LOG_DEBUG("Freeing Encoder object");
  struct NvrEncoder *nvr_encoder = (struct NvrEncoder *)obj;

  encoder_free(nvr_encoder->encoder);

  if (nvr_encoder->frame != NULL) {
    av_frame_free(&nvr_encoder->frame);
  }
}

void free_decoder(ErlNifEnv *env, void *obj) {
  NVR_LOG_DEBUG("Freeing Decoder object");
  struct NvrDecoder *nvr_decoder = (struct NvrDecoder *)obj;

  decoder_free(&nvr_decoder->decoder);
  video_converter_free(&nvr_decoder->video_converter);

  if (nvr_decoder->packet != NULL) {
    av_packet_free(&nvr_decoder->packet);
  }
}

static ErlNifFunc funcs[] = {
    {"new_encoder", 2, new_encoder},
    {"new_decoder", 5, new_decoder},
    {"encode", 3, encode, ERL_DIRTY_JOB_CPU_BOUND},
    {"decode", 4, decode, ERL_DIRTY_JOB_CPU_BOUND},
    {"flush_encoder", 1, flush_encoder, ERL_DIRTY_JOB_CPU_BOUND},
    {"flush_decoder", 1, flush_decoder, ERL_DIRTY_JOB_CPU_BOUND}};

static int load(ErlNifEnv *env, void **priv, ERL_NIF_TERM load_info) {
  encoder_resource_type = enif_open_resource_type(
      env, NULL, "NvrEncoder", free_encoder, ERL_NIF_RT_CREATE, NULL);
  decoder_resource_type = enif_open_resource_type(
      env, NULL, "NvrDecoder", free_decoder, ERL_NIF_RT_CREATE, NULL);
  return 0;
}

ERL_NIF_INIT(Elixir.ExNVR.AV.VideoProcessor.NIF, funcs, &load, NULL, NULL,
             NULL);

#endif // NVR_ENCODER_H
