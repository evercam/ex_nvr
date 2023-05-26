#pragma once

#include <erl_nif.h>
#include <libavformat/avformat.h>

typedef struct _mp4_depayloader_state {
  AVFormatContext *format_ctx;
  AVBSFContext *bsf_ctx;
} 
State;

#include "_generated/mp4_depayloader.h"
