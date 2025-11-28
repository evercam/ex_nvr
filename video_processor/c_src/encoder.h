#ifndef ENCODER_H
#define ENCODER_H

#include "utils.h"
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
  char *preset;
  char *tune;
};

Encoder *encoder_alloc();
int encoder_init(Encoder *encoder, struct EncoderConfig *config);
int encoder_encode(Encoder *encoder, AVFrame *frame);
void encoder_free(Encoder *encoder);

#endif // ENCODER_H