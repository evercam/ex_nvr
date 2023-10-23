#include "video_assembler.h"

#define FILTERED_PACKET_ERROR 0

void handle_destroy_state(UnifexEnv *env, State *state) {
  UNIFEX_UNUSED(env);
  UNIFEX_UNUSED(state);
}

void init_stream(AVFormatContext* dest_ctx, AVFormatContext* source_ctx, int stream_index) {
  AVCodecParameters *codec_par = source_ctx->streams[stream_index]->codecpar;
  AVStream* stream = avformat_new_stream(dest_ctx, NULL);
  avcodec_parameters_copy(stream->codecpar, codec_par);
  stream->time_base = source_ctx->streams[stream_index]->time_base;
}

UNIFEX_TERM assemble_recordings(UnifexEnv* env, recording* recordings, unsigned int recordings_size, 
    int64_t start_date, int64_t end_date, int64_t target_duration, char* dest) {
  UNIFEX_TERM res;
  AVPacket *packet = av_packet_alloc();
  AVFormatContext *read_ctx = avformat_alloc_context();
  AVFormatContext *write_ctx = avformat_alloc_context();

  int64_t last_dts = -1;
  int64_t duration = 0, offset = 0;

  // init write context
  if (avformat_alloc_output_context2(&write_ctx, NULL, "mp4", NULL) < 0) {
      res = assemble_recordings_result_error(env, "alloc_error");
      goto exit_assemble_files;
  }

  if (avio_open2(&write_ctx->pb, dest, AVIO_FLAG_WRITE, NULL, NULL) < 0) {
      res = assemble_recordings_result_error(env, "avio_open");
      goto exit_assemble_files;
  }

  for (unsigned int i = 0; i < recordings_size; i++) {
    if (avformat_open_input(&read_ctx, recordings[i].path, NULL, NULL)) {
      res = assemble_recordings_result_error(env, "open_read");
      goto exit_assemble_files;
    }

    int stream_index;
    const AVCodec *codec;
    if((stream_index = av_find_best_stream(read_ctx, AVMEDIA_TYPE_VIDEO, -1, -1, &codec, 0)) < 0) {
        res = assemble_recordings_result_error(env, "nostream");
        goto exit_assemble_files;
    }

    if (i == 0) {
      AVRational time_base = read_ctx->streams[stream_index]->time_base;
      offset = av_rescale(start_date - recordings[0].start_date, time_base.den, 1000 * time_base.num);
      avformat_seek_file(read_ctx, stream_index, INT64_MIN, offset, INT64_MAX, AVSEEK_FLAG_BACKWARD);
     
      init_stream(write_ctx, read_ctx, stream_index);

      target_duration = av_rescale(target_duration, time_base.den, time_base.num);
      start_date = av_rescale(start_date, time_base.den, 1000 * time_base.num);
      end_date = av_rescale(end_date, time_base.den, 1000 * time_base.num);

      if(avformat_write_header(write_ctx, NULL)) {
        res = assemble_recordings_result_error(env, "write_header");
        goto exit_assemble_files;
      }
    }

    av_read_frame(read_ctx, packet);
    
    if (last_dts == -1) {
      last_dts = -packet->dts;
      offset -= packet->dts; 

      if (target_duration != 0) target_duration += offset;
      start_date -= offset;
    }    

    do {
      packet->dts += last_dts;
      packet->pts += last_dts;
      duration += packet->duration;

      av_interleaved_write_frame(write_ctx, packet);

      if ((target_duration != 0 && duration >= target_duration) || start_date + duration >= end_date) 
        goto exit_loop;
    } while (av_read_frame(read_ctx, packet) == 0);

    last_dts += read_ctx->streams[stream_index]->duration;
    avformat_close_input(&read_ctx);
  }

exit_loop:
  av_write_trailer(write_ctx);
  res = assemble_recordings_result(env);

exit_assemble_files:
  av_packet_unref(packet);
  avformat_free_context(read_ctx);
  avformat_free_context(write_ctx);
  return res;
}
