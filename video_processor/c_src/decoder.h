#include "utils.h"
#include <libavcodec/avcodec.h>

typedef struct Decoder Decoder;

struct Decoder {
  const AVCodec *codec;
  AVCodecContext *c;
  int max_frames;
  int count_frames;
  AVFrame **frames;
};

Decoder *decoder_alloc();
int decoder_init(Decoder *decoder, const AVCodec *codec);
int decoder_decode(Decoder *decoder, AVPacket *pkt);
int decoder_flush(Decoder *decoder);
void decoder_free_frame(Decoder *decoder);
void decoder_free(Decoder **decoder);