#pragma once

#include "encoder.h"
#include "decoder.h"
#include "video_converter.h"
#include "utils.h"

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
  int pad;
  enum AVPixelFormat out_format;
};

struct NvrConverter {
  VideoConverter *video_converter;
  AVFrame *frame;
};
