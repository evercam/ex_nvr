#pragma once

#include "decoder.h"
#include "encoder.h"

struct NvrEncoder {
  Encoder *encoder;
  AVFrame *frame;
};

struct NvrDecoder {
  Decoder *decoder;
  AVPacket *packet;
};