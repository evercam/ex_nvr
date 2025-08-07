#pragma once

#include "encoder.h"

struct NvrEncoder {
  Encoder *encoder;
  int num_packets;
  int max_num_packets;
  AVPacket **packets;
  AVFrame *frame;
};