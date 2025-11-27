#include "video_converter.h"
#include "utils.h"

int add_padding(AVFrame *scaled_frame, AVFrame *dst_frame);

VideoConverter *video_converter_alloc() {
  VideoConverter *converter =
      (VideoConverter *)enif_alloc(sizeof(VideoConverter));
  converter->sws_ctx = NULL;
  converter->frame = av_frame_alloc();
  converter->scaled_frame = av_frame_alloc();
  return converter;
}

int video_converter_init(VideoConverter *converter, int in_width, int in_height,
                         enum AVPixelFormat in_format, int out_width,
                         int out_height, enum AVPixelFormat out_format, int pad) {
  AVFrame *dst_frame = converter->frame;
  AVFrame *scaled_frame = converter->scaled_frame;

  dst_frame->format = out_format;
  scaled_frame->format = out_format;

  // only pad if output format is rgb24 and both width and height are specified
  converter->pad = pad && out_width != -1 && out_height != -1 && out_format == AV_PIX_FMT_RGB24;

  if (out_width == -1 && out_height == -1) {
    scaled_frame->width = in_width;
    scaled_frame->height = in_height;
  } else if (out_width == -1) {
    int width = in_width * out_height / in_height;
    width = width + (width % 2);

    scaled_frame->width = width;
    scaled_frame->height = out_height;
  } else if (out_height == -1) {
    int height = in_height * out_width / in_width;
    height = height + (height % 2);

    scaled_frame->width = out_width;
    scaled_frame->height = height;
  } else {
    if (converter->pad) {
      float in_aspect = (float)in_width / (float)in_height;
      float out_aspect = (float)out_width / (float)out_height;

      if (in_aspect > out_aspect) {
        int height = in_height * out_width / in_width;
        height = height + (height % 2);
        scaled_frame->width = out_width;
        scaled_frame->height = height;
      } else {
        int width = in_width * out_height / in_height;
        width = width + (width % 2);
        scaled_frame->width = width;
        scaled_frame->height = out_height;
      }
    } else {
      scaled_frame->width = out_width;
      scaled_frame->height = out_height;
    }

    dst_frame->width = out_width;
    dst_frame->height = out_height;

    int ret = av_frame_get_buffer(dst_frame, 0);
    if (ret < 0) {
      return ret;
    }
  }

  int ret = av_frame_get_buffer(scaled_frame, 0);
  if (ret < 0) {
    return ret;
  }

  converter->sws_ctx = sws_getContext(
      in_width, in_height, in_format, scaled_frame->width, scaled_frame->height,
      scaled_frame->format, SWS_BILINEAR, NULL, NULL, NULL);

  if (!converter->sws_ctx) {
    NVR_LOG_DEBUG("Couldn't get sws context");
    return -1;
  }

  return 0;
}

int video_converter_convert(VideoConverter *converter, AVFrame *frame) {
  int ret;
  converter->frame->pts = frame->pts;
  converter->scaled_frame->pts = frame->pts;

  // is this (const uint8_t * const*) cast really correct?
  ret = sws_scale(converter->sws_ctx, (const uint8_t *const *)frame->data,
                  frame->linesize, 0, frame->height,
                  converter->scaled_frame->data,
                  converter->scaled_frame->linesize);

  if (ret < 0) {
    return ret;
  }

  if (converter->pad) {
    return add_padding(converter->scaled_frame, converter->frame);
  } else {
    converter->frame = converter->scaled_frame;
    return 0;
  }
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

int add_padding(AVFrame *scaled_frame, AVFrame *dst_frame) {
  if (scaled_frame->width == dst_frame->width) {
    int top = (dst_frame->height - scaled_frame->height) / 2;
    int src_stride = dst_frame->linesize[0];

    av_image_copy_plane(dst_frame->data[0] + top * src_stride, src_stride,
                        scaled_frame->data[0], scaled_frame->linesize[0], src_stride,
                        scaled_frame->height);
  } else {
    int left = (dst_frame->width - scaled_frame->width) / 2;

    av_image_copy_plane(dst_frame->data[0] + left, dst_frame->linesize[0],
                        scaled_frame->data[0], scaled_frame->linesize[0],
                        scaled_frame->linesize[0], scaled_frame->height);
  }

  av_frame_unref(scaled_frame);

  return 0;
}
