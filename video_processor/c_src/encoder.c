#include "encoder.h"

Encoder *encoder_alloc() {
  Encoder *encoder = enif_alloc(sizeof(Encoder));
  encoder->c = NULL;
  encoder->codec = NULL;
  encoder->num_packets = 0;
  encoder->max_num_packets = 4;
  encoder->packets = enif_alloc(encoder->max_num_packets * sizeof(AVPacket *));

  for (int i = 0; i < encoder->max_num_packets; i++) {
    encoder->packets[i] = av_packet_alloc();
  }

  return encoder;
}

int encoder_init(Encoder *encoder, struct EncoderConfig *config) {
  encoder->codec = config->codec;

  encoder->c = avcodec_alloc_context3(encoder->codec);
  if (!encoder->c) {
    return -1;
  }

  encoder->c->width = config->width;
  encoder->c->height = config->height;
  encoder->c->pix_fmt = config->format;
  encoder->c->time_base = config->time_base;

  if (config->gop_size > 0) {
    encoder->c->gop_size = config->gop_size;
  }

  if (config->max_b_frames >= 0) {
    encoder->c->max_b_frames = config->max_b_frames;
  }

  if (config->profile != FF_PROFILE_UNKNOWN) {
    encoder->c->profile = config->profile;
  }

  return avcodec_open2(encoder->c, encoder->codec, NULL);
}

int encoder_encode(Encoder *encoder, AVFrame *frame) {
  int ret = avcodec_send_frame(encoder->c, frame);
  if (ret < 0) {
    return ret;
  }

  encoder->num_packets = 0;

  while (1) {
    ret = avcodec_receive_packet(encoder->c,
                                 encoder->packets[encoder->num_packets]);
    if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) {
      break;
    } else if (ret < 0) {
      return ret;
    }

    if (++encoder->num_packets >= encoder->max_num_packets) {
      encoder->max_num_packets *= 2;
      encoder->packets = enif_realloc(
          encoder->packets, encoder->max_num_packets * sizeof(AVPacket *));
      for (int i = encoder->num_packets; i < encoder->max_num_packets; i++) {
        encoder->packets[i] = av_packet_alloc();
      }
    }
  }

  return 0;
}

void encoder_free(Encoder *encoder) {
  if (!encoder) {
    return;
  }

  if (encoder->c != NULL) {
    avcodec_free_context(&encoder->c);
  }

  if (encoder->packets != NULL) {
    for (int i = 0; i < encoder->max_num_packets; i++) {
      av_packet_free(&encoder->packets[i]);
    }
    enif_free(encoder->packets);
  }

  enif_free(encoder);
}