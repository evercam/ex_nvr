#include "video_converter.h"
#include "utils.h"

VideoConverter *video_converter_alloc() {
  VideoConverter *converter =
      (VideoConverter *)enif_alloc(sizeof(VideoConverter));
  converter->sws_ctx = NULL;
  converter->frame = av_frame_alloc();
  return converter;
}

int video_converter_init(VideoConverter *converter, int in_width, int in_height,
                         enum AVPixelFormat in_format, int out_width,
                         int out_height, enum AVPixelFormat out_format) {
  AVFrame *dst_frame = converter->frame;
  av_frame_unref(dst_frame);

  dst_frame->format = out_format;

  if (out_width == -1 && out_height == -1) {
    dst_frame->width = in_width;
    dst_frame->height = in_height;
  } else if (out_width == -1) {
    int width = in_width * out_height / in_height;
    width = width + (width % 2);

    dst_frame->width = width;
    dst_frame->height = out_height;
  } else if (out_height == -1) {
    int height = in_height * out_width / in_width;
    height = height + (height % 2);

    dst_frame->width = out_width;
    dst_frame->height = height;
  } else {
    dst_frame->width = out_width;
    dst_frame->height = out_height;
  }

  int ret = av_frame_get_buffer(dst_frame, 0);
  if (ret < 0) {
    return ret;
  }

  converter->sws_ctx = sws_getContext(
      in_width, in_height, in_format, dst_frame->width, dst_frame->height,
      dst_frame->format, SWS_BILINEAR, NULL, NULL, NULL);

  if (!converter->sws_ctx) {
    NVR_LOG_DEBUG("Couldn't get sws context");
    return -1;
  }

  return 0;
}

int video_converter_convert(VideoConverter *converter, AVFrame *frame) {
  int ret;
  converter->frame->pts = frame->pts;

  // is this (const uint8_t * const*) cast really correct?
  return sws_scale(converter->sws_ctx, (const uint8_t *const *)frame->data,
                   frame->linesize, 0, frame->height, converter->frame->data,
                   converter->frame->linesize);
}

void video_converter_free(struct VideoConverter **converter) {
  struct VideoConverter *vc = *converter;
  if (vc != NULL) {
    if (vc->sws_ctx != NULL) {
      sws_freeContext((*converter)->sws_ctx);
    }

    if (vc->frame != NULL) {
      av_frame_free(&(*converter)->frame);
    }

    enif_free(vc);
    *converter = NULL;
  }
}