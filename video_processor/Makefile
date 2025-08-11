ARCH := $(or $(TARGET_ARCH), $(shell uname -m))
OS := $(or $(TARGET_OS), $(shell uname -s))
ABI ?= gnu

VERSION ?= 0.1.0
FFMPEG_VERSION ?= 7.1.1

TEMP ?= $(HOME)/.cache
FFMPEG_DIR ?= $(TEMP)/ex_nvr/$(VERSION)/$(ARCH)/ffmpeg-$(FFMPEG_VERSION)
PRECOMPILED_FFMPEG_LINK ?= https://github.com/evercam/ex_nvr_precompiled/releases/download/v$(VERSION)/ffmpeg-linux-$(ARCH)-$(FFMPEG_VERSION).tar.xz
PRECOMPILED_FFMPEG_NAME ?= ffmpeg-linux-$(shell uname -m)-$(FFMPEG_VERSION).tar.xz

PRECOMPILED = false

DIR := c_src
PRIV_DIR := $(MIX_APP_PATH)/priv
VIDEO_PROCESSOR_SO := $(PRIV_DIR)/libvideoprocessor.so

# uncomment to compile with debug logs
# DEBUG_LOGS = -DNVR_DEBUG=1

HEADERS = $(DIR)/video_processor.h $(DIR)/encoder.h $(DIR)/decoder.h $(DIR)/video_converter.h $(DIR)/utils.h
SOURCES = $(DIR)/video_processor.c $(DIR)/encoder.c $(DIR)/decoder.c $(DIR)/video_converter.c $(DIR)/utils.c

CFLAGS += $(DEBUG_LOGS) -fPIC -shared

CFLAGS += -fPIC -shared
IFLAGS = -I$(ERTS_INCLUDE_DIR) -I$(DIR) $$(pkg-config --cflags libavcodec libavutil libswscale)
LDFLAGS = $$(pkg-config --libs libavcodec libavutil libswscale)

ifeq ($(OS),Linux)
	ifeq ($(ABI),gnu)
		ifneq (,$(filter $(ARCH),x86_64 armv7l arm aarch64))
			PRECOMPILED = true
			IFLAGS = -I$(ERTS_INCLUDE_DIR) -I$(DIR) -I$(FFMPEG_DIR)/include
			LDFLAGS = -L$(PRIV_DIR) -lavcodec -lavutil -lswscale -Wl,-rpath=\$$ORIGIN
		endif
	endif
endif

# Flags for MacOS
ifeq ($(OS),Darwin)
	ifeq ($(ARCH),arm64)
		IFLAGS += $$(pkg-config --cflags-only-I libavcodec libavutil libswscale)
		LFLAGS += $$(pkg-config --libs-only-L libavcodec libavutil libswscale)
		CFLAGS += -undefined dynamic_lookup
	else
		CFLAGS += -undefined dynamic_lookup 
	endif
endif

# Flags for Fedora
ifneq ($(PRECOMPILED),true)
	ifneq (,$(wildcard /etc/fedora-release))
		IFLAGS += $$(pkg-config --cflags-only-I libavcodec libavutil libswscale)
		LFLAGS += $$(pkg-config --libs-only-L libavcodec libavutil libswscale)
	endif
endif

all: download_ffmpeg $(VIDEO_PROCESSOR_SO)

download_ffmpeg:
	@if [ $(PRECOMPILED) = true ] && [ ! -d $(FFMPEG_DIR) ]; then \
		echo "Downloading precompiled ffmpeg..."; \
		mkdir -p $(TEMP); \
		mkdir -p $(FFMPEG_DIR); \
		curl -sL $(PRECOMPILED_FFMPEG_LINK) -o $(TEMP)/$(PRECOMPILED_FFMPEG_NAME); \
		tar -xf $(TEMP)/$(PRECOMPILED_FFMPEG_NAME) -C $(FFMPEG_DIR); \
	fi

$(VIDEO_PROCESSOR_SO): $(HEADERS) $(SOURCES)
	mkdir -p $(PRIV_DIR)
	@if [ $(PRECOMPILED) = true ]; then \
		cp -f $(FFMPEG_DIR)/lib/*.so* $(PRIV_DIR)/; \
	fi
	$(CC) $(CFLAGS) $(IFLAGS) $(LFLAGS) $(SOURCES) -o $(VIDEO_PROCESSOR_SO) $(LDFLAGS)
	@rm -f $(PRIV_DIR)/libav*.so $(PRIV_DIR)/libsw*.so
	@rm -f $(PRIV_DIR)/libav*.so.*.* $(PRIV_DIR)/libsw*.so.*.*

format:
	clang-format -i $(DIR)/*

clean:
	@rm -f $(TEMP)/$(PRECOMPILED_FFMPEG_NAME)
	@rm -rf $(TEMP)/ex_nvr/$(VERSION)

.PHONY: format