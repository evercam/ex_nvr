#include "mp4_depayloader.h"

#define FILTERED_PACKET_ERROR 0

void handle_destroy_state(UnifexEnv *env, State *state) {
  UNIFEX_UNUSED(env);

  if (state->format_ctx != NULL) {
    avformat_free_context(state->format_ctx);
  }

  if (state->bsf_ctx != NULL) {
    av_bsf_free(&state->bsf_ctx);
  }
}

UNIFEX_TERM open_file(UnifexEnv* env, char* filename) {
    UNIFEX_TERM res;

    State* state = unifex_alloc_state(env);
    state->format_ctx = avformat_alloc_context();

    if(avformat_open_input(&state->format_ctx, filename, NULL, NULL)) {
        res = open_file_result_error(env, "open_error");
        goto exit_open_file;
    }

    int stream_index;
    AVCodec *codec;
    if((stream_index = av_find_best_stream(state->format_ctx, AVMEDIA_TYPE_VIDEO, -1, -1, &codec, 0)) < 0) {
        res = open_file_result_error(env, "nostream");
        goto exit_open_file;
    }

    const AVBitStreamFilter *bsf_filter = av_bsf_get_by_name("h264_mp4toannexb");
    av_bsf_alloc(bsf_filter, &state->bsf_ctx);
    avcodec_parameters_copy(state->bsf_ctx->par_in, state->format_ctx->streams[stream_index]->codecpar);
    av_bsf_init(state->bsf_ctx);

    AVRational time_base = state->format_ctx->streams[stream_index]->time_base;
    res = open_file_result_ok(env, state, time_base.num, time_base.den);
exit_open_file:
    unifex_release_state(env, state);
    return res;
}

static int get_filtered_packets(UnifexEnv *env, UnifexPayload ***ret_frames, 
                               int64_t **ret_pts, int **ret_keyframes, int max_au, 
                               int *count, State* state) {
  AVPacket *filtered_packet = av_packet_alloc();
  filtered_packet->size = 0;
  filtered_packet->data = NULL;

  UnifexPayload **access_units = unifex_alloc((max_au) * sizeof(*access_units));
  int64_t *pts = unifex_alloc((max_au) * sizeof(*pts));
  int *keyframes = unifex_alloc((max_au) * sizeof(*keyframes));
  
  int ret = av_bsf_receive_packet(state->bsf_ctx, filtered_packet);
  while (ret != AVERROR(EAGAIN) && ret != AVERROR_EOF)
  {
    if (ret < 0) {
      ret = FILTERED_PACKET_ERROR;
      goto exit_get_filtered_packets;
    }

    access_units[*count] = unifex_alloc(sizeof(UnifexPayload));
    unifex_payload_alloc(env, UNIFEX_PAYLOAD_BINARY, filtered_packet->size, access_units[*count]);
    memcpy(access_units[*count]->data, filtered_packet->data, filtered_packet->size);
    pts[*count] = filtered_packet->pts;
    keyframes[*count] = filtered_packet->flags & AV_PKT_FLAG_KEY;

    (*count)++;

    ret = av_bsf_receive_packet(state->bsf_ctx, filtered_packet);
  }

exit_get_filtered_packets:
  *ret_frames = access_units;
  *ret_pts = pts;
  *ret_keyframes = keyframes;
  av_packet_unref(filtered_packet);
  return ret;
}

UNIFEX_TERM read_access_unit(UnifexEnv* env, State* state) {
  UNIFEX_TERM res;
  AVPacket *packet = av_packet_alloc();

  UnifexPayload **out_access_units = NULL;
  int64_t *out_pts = NULL;
  int *out_keyframes = NULL;
  int count = 0;

  if (av_read_frame(state->format_ctx, packet) == 0) {
    if (av_bsf_send_packet(state->bsf_ctx, packet) < 0) {
      res = read_access_unit_result_error(env, "send_packet");
      goto exit_read_access_unit;
    }

    int ret = get_filtered_packets(env, &out_access_units, &out_pts, &out_keyframes, 16, &count, state);

    if (ret == FILTERED_PACKET_ERROR) {
      res = read_access_unit_result_error(env, "parse_error");
      goto exit_read_access_unit;
    }

    res = read_access_unit_result_ok(env, out_access_units, count, out_pts, count, out_keyframes, count);

    if (out_access_units != NULL) {
      for (int i = 0; i < count; i++) {
        if (out_access_units[i] != NULL) {
          unifex_payload_release(out_access_units[i]);
          unifex_free(out_access_units[i]);
        }
      }
      unifex_free(out_access_units);
    }

    if (out_pts != NULL) {
      unifex_free(out_pts);
      unifex_free(out_keyframes);
    }
  } else {
    res = read_access_unit_result_error(env, "eof");
  }

exit_read_access_unit:
  av_packet_unref(packet);
  return res;
}
