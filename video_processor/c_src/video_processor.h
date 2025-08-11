#pragma once

#include "decoder.h"
#include "encoder.h"
#include "video_converter.h"

struct NvrEncoder {
  Encoder *encoder;
  AVFrame *frame;
};

struct NvrDecoder {
  Decoder *decoder;
  AVPacket *packet;
  VideoConverter *video_converter;
  // output params
  int out_width;
  int out_height;
  enum AVPixelFormat out_format;
};