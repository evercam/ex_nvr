
#include <libavutil/frame.h>
#include <libavutil/imgutils.h>
#include <libswscale/swscale.h>

typedef struct VideoConverter VideoConverter;

struct VideoConverter {
  struct SwsContext *sws_ctx;
  AVFrame *frame;
};

VideoConverter *video_converter_alloc();

int video_converter_init(VideoConverter *converter, int in_width, int in_height,
                         enum AVPixelFormat in_format, int out_width,
                         int out_height, enum AVPixelFormat out_format);

int video_converter_convert(VideoConverter *converter, AVFrame *src_frame);

void video_converter_free(VideoConverter **converter);