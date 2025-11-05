ARCH := $(or $(TARGET_ARCH), $(shell uname -m))
OS := $(or $(TARGET_OS), $(shell uname -s))
ABI ?= gnu

TEMP ?= $(HOME)/.cache

PRECOMPILED = false
VERSION := 0.2.0
FFMPEG_VERSION := 7.1.1
FFMPEG_DIR ?= $(TEMP)/ex_nvr/$(VERSION)/$(ARCH)/ffmpeg-$(FFMPEG_VERSION)
PRECOMPILED_FFMPEG_LINK ?= https://github.com/evercam/ex_nvr_precompiled/releases/download/v$(VERSION)/ffmpeg-$(OS)-$(ARCH)-$(FFMPEG_VERSION).tar.xz
PRECOMPILED_FFMPEG_NAME ?= ffmpeg-linux-$(ARCH)-$(FFMPEG_VERSION).tar.xz

DIR := c_src
PRIV_DIR := $(MIX_APP_PATH)/priv

BYTE_TRACK_DIR = $(DIR)/byte_track
BYTE_TRACK_BUILD = $(BYTE_TRACK_DIR)/build

VIDEO_PROCESSOR_SO := $(PRIV_DIR)/libvideoprocessor.so
CAMERA_CAPTURE_SO := $(PRIV_DIR)/libcameracapture.so
BYTE_TRACKER_SO := $(PRIV_DIR)/libbytetracker.so
HAILO_SO = $(PRIV_DIR)/libhailo.so

# uncomment to compile with debug logs
# DEBUG_LOGS = -DNVR_DEBUG=1

COMMON_HEADERS = $(DIR)/encoder.h $(DIR)/decoder.h $(DIR)/video_converter.h $(DIR)/utils.h
COMMON_SOURCES = $(DIR)/encoder.c $(DIR)/decoder.c $(DIR)/video_converter.c $(DIR)/utils.c

HEADERS = $(DIR)/video_processor.h $(COMMON_HEADERS)
SOURCES = $(DIR)/video_processor.c $(COMMON_SOURCES)

CAMERA_CAPTURE_HEADERS = $(DIR)/camera/camera_capture.h $(COMMON_HEADERS)
CAMERA_CAPTURE_SOURCES = $(DIR)/camera/camera_capture.c $(COMMON_SOURCES)

HAILO_SOURCES = $(DIR)/hailo/hailo.cpp

HAILO_CFLAGS := $(CFLAGS) -fPIC -I$(FINE_INCLUDE_DIR) -fvisibility=hidden -I$(ERTS_INCLUDE_DIR) -Wall -std=c++17
HAILO_LDFLAGS := $(LDFLAGS) -shared -lhailort

VP_CFLAGS += $(DEBUG_LOGS) -fPIC -shared
VP_IFLAGS = -I$(ERTS_INCLUDE_DIR) -I$(DIR) $$(pkg-config --cflags libavcodec libavutil libswscale libavdevice libavformat)
VP_LDFLAGS = $$(pkg-config --libs libavcodec libavutil libswscale libavdevice libavformat)

ifneq (,$(filter $(OS),linux Linux))
	ifeq ($(ABI),gnu)
		ifneq (,$(filter $(ARCH),x86_64 armv7l arm aarch64))
			PRECOMPILED = true
			VP_IFLAGS = -I$(ERTS_INCLUDE_DIR) -I$(DIR) -I$(FFMPEG_DIR)/include
			VP_LDFLAGS = -L$(PRIV_DIR) -lavcodec -lavutil -lswscale -lavdevice -lavformat -Wl,-rpath=\$$ORIGIN
		endif
	endif
endif

#Flags for MacOS
ifeq ($(OS),Darwin)
   	VP_IFLAGS += $$(pkg-config --cflags-only-I libavcodec libavutil libswscale libavdevice libavformat)
   	VP_LFLAGS += $$(pkg-config --libs-only-L libavcodec libavutil libswscale libavdevice libavformat)
   	VP_CFLAGS += -undefined dynamic_lookup
endif

# Flags for Fedora
ifneq ($(PRECOMPILED),true)
	ifneq (,$(wildcard /etc/fedora-release))
		VP_IFLAGS += $$(pkg-config --cflags-only-I libavcodec libavutil libswscale)
		VP_LFLAGS += $$(pkg-config --libs-only-L libavcodec libavutil libswscale)
	endif
endif

all: download_ffmpeg $(VIDEO_PROCESSOR_SO) $(CAMERA_CAPTURE_SO) $(BYTE_TRACKER_SO) $(HAILO_SO)

download_ffmpeg:
	@if [ $(PRECOMPILED) = true ] && [ ! -d $(FFMPEG_DIR) ]; then \
		echo "Downloading precompiled ffmpeg..."; \
		mkdir -p $(TEMP); \
		mkdir -p $(FFMPEG_DIR); \
		curl -L $(PRECOMPILED_FFMPEG_LINK) -o $(TEMP)/$(PRECOMPILED_FFMPEG_NAME); \
		tar -xf $(TEMP)/$(PRECOMPILED_FFMPEG_NAME) -C $(FFMPEG_DIR); \
	fi

$(VIDEO_PROCESSOR_SO): $(HEADERS) $(SOURCES)
	mkdir -p $(PRIV_DIR);

	@if [ $(PRECOMPILED) = true ]; then \
		cp -f $(FFMPEG_DIR)/lib/*.so* $(PRIV_DIR)/; \
	fi
	$(CC) $(VP_CFLAGS) $(VP_IFLAGS) $(VP_LFLAGS) $(SOURCES) -o $(VIDEO_PROCESSOR_SO) $(VP_LDFLAGS)

$(CAMERA_CAPTURE_SO): $(CAMERA_CAPTURE_HEADERS) $(CAMERA_CAPTURE_SOURCES)
	$(CC) $(VP_CFLAGS) $(VP_IFLAGS) $(VP_LFLAGS) $(CAMERA_CAPTURE_SOURCES) -o $(CAMERA_CAPTURE_SO) $(VP_LDFLAGS)
	@rm -f $(PRIV_DIR)/libav*.so $(PRIV_DIR)/libsw*.so
	@rm -f $(PRIV_DIR)/libav*.so.*.* $(PRIV_DIR)/libsw*.so.*.*

${BYTE_TRACKER_SO}:
	# rm -rf $(BYTE_TRACK_BUILD)
	mkdir -p $(BYTE_TRACK_BUILD)
	cd $(BYTE_TRACK_BUILD) && cmake -DFINE_INCLUDE_DIR=$(FINE_INCLUDE_DIR) -DERTS_INCLUDE_DIR=$(ERTS_INCLUDE_DIR) ..
	cd $(BYTE_TRACK_BUILD) && make -j4
	cp $(BYTE_TRACK_BUILD)/libbytetrack.so $(PRIV_DIR)/libbytetrack.so

$(HAILO_SO): $(HAILO_SOURCES) $(HAILO_SOURCES)
	$(CXX) $(HAILO_CFLAGS) $(HAILO_SOURCES) -o $(HAILO_SO) $(HAILO_LDFLAGS)

format:
	clang-format -i $(DIR)/*

clean:
	@rm -f $(TEMP)/$(PRECOMPILED_FFMPEG_NAME)
	@rm -rf $(TEMP)/ex_nvr/$(VERSION)
	@rm -rf $(PRIV_DIR)/*

.PHONY: format
