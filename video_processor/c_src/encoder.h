#ifndef ENCODER_H
#define ENCODER_H

#include <erl_nif.h>
#include <libavcodec/avcodec.h>
#include <libavutil/pixdesc.h>

typedef struct Encoder Encoder;

struct Encoder {
  const AVCodec *codec;
  AVCodecContext *c;
  AVPacket **packets;
  int num_packets;
  int max_num_packets;
};

struct EncoderConfig {
  enum AVMediaType media_type;
  const AVCodec *codec;
  int width;
  int height;
  enum AVPixelFormat format;
  AVRational time_base;
  int gop_size;
  int max_b_frames;
  int profile;
};

#ifdef NVR_DEBUG
#define NVR_LOG_DEBUG(X, ...)                                                  \
  fprintf(stderr, "[XAV DEBUG %s] %s:%d " X "\n", __TIME__, __FILE__,          \
          __LINE__, ##__VA_ARGS__)
#else
#define NVR_LOG_DEBUG(...)
#endif

Encoder *encoder_alloc();
int encoder_init(Encoder *encoder, struct EncoderConfig *config);
int encoder_encode(Encoder *encoder, AVFrame *frame);
void encoder_free(Encoder *encoder);

ERL_NIF_TERM nif_ok(ErlNifEnv *env, ERL_NIF_TERM data_term);
ERL_NIF_TERM nif_error(ErlNifEnv *env, char *reason);
ERL_NIF_TERM nif_raise(ErlNifEnv *env, char *msg);
int nif_get_atom(ErlNifEnv *env, ERL_NIF_TERM term, char **value);
int nif_get_string(ErlNifEnv *env, ERL_NIF_TERM term, char **value);

#endif // ENCODER_H