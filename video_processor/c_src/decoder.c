#include "decoder.h"

static void realloc_frames(Decoder *decoder);
static int receive_frames(Decoder *decoder, int break_code);

Decoder *decoder_alloc() {
  Decoder *decoder = (Decoder *)enif_alloc(sizeof(Decoder));

  decoder->codec = NULL;
  decoder->c = NULL;
  decoder->max_frames = 8;
  decoder->count_frames = 0;
  decoder->frames =
      (AVFrame **)enif_alloc(sizeof(AVFrame *) * decoder->max_frames);
  for (int i = 0; i < decoder->max_frames; i++) {
    decoder->frames[i] = av_frame_alloc();
  }

  return decoder;
}

int decoder_init(Decoder *decoder, const AVCodec *codec) {
  decoder->codec = codec;

  decoder->c = avcodec_alloc_context3(decoder->codec);
  if (!decoder->c) {
    return -1;
  }

  return avcodec_open2(decoder->c, decoder->codec, NULL);
}

int decoder_init_by_parameters(Decoder *decoder, const AVCodecParameters *codec_params) {
    const AVCodec *codec = avcodec_find_decoder(codec_params->codec_id);
    if (!codec) {
        return -1;
    }

    decoder->codec = codec;
    decoder->c = avcodec_alloc_context3(decoder->codec);
    if (!decoder->c) {
        return -1;
    }

    if (avcodec_parameters_to_context(decoder->c, codec_params) < 0) {
        return -1;
    }

    return avcodec_open2(decoder->c, decoder->codec, NULL);
}

int decoder_decode(Decoder *decoder, AVPacket *pkt) {
  int ret;
  if (avcodec_send_packet(decoder->c, pkt) < 0) {
    return -1;
  }

  return receive_frames(decoder, AVERROR(EAGAIN));
}

int decoder_flush(struct Decoder *decoder) {
  int ret = avcodec_send_packet(decoder->c, NULL);
  if (ret != 0) {
    return ret;
  }

  return receive_frames(decoder, AVERROR_EOF);
}

void decoder_free(Decoder **decoder) {
  NVR_LOG_DEBUG("Freeing Decoder object");
  if (*decoder != NULL) {
    Decoder *d = *decoder;

    if (d->c != NULL) {
      avcodec_free_context(&d->c);
    }

    if (d->frames != NULL) {
      for (int i = 0; i < d->max_frames; i++) {
        if (d->frames[i] != NULL) {
          av_frame_free(&d->frames[i]);
        }
      }
      enif_free(d->frames);
    }

    enif_free(d);
    *decoder = NULL;
  }
}

static int receive_frames(Decoder *decoder, int break_code) {
  int ret;
  decoder->count_frames = 0;
  while (1) {
    ret = avcodec_receive_frame(decoder->c,
                                decoder->frames[decoder->count_frames]);
    if (ret == break_code) {
      break;
    } else if (ret < 0) {
      return ret;
    }

    if (++decoder->count_frames >= decoder->max_frames) {
      realloc_frames(decoder);
    }
  }

  return 0;
}

static void realloc_frames(Decoder *decoder) {
  decoder->max_frames *= 2;
  decoder->frames = (AVFrame **)enif_realloc(
      decoder->frames, sizeof(AVFrame *) * decoder->max_frames);
  for (int i = decoder->count_frames; i < decoder->max_frames; i++) {
    decoder->frames[i] = av_frame_alloc();
  }
}
