PLUGIN_NAME = hypr-kinetic-scroll

CXXFLAGS ?= -O2
# EXTRA_CXXFLAGS is a local addition, so build.sh can pass
# -DKINETIC_DEBUG_DEFAULT=1 without clobbering the flags above (a
# command-line CXXFLAGS= override would drop -shared and -fPIC and
# quietly produce a broken .so). -g is kept even for release builds:
# debug info is what makes a compositor core dump symbolizable, and
# 5 MB on disk is cheap next to guessing at a backtrace.
CXXFLAGS += -shared -fPIC -std=c++2b -g $(EXTRA_CXXFLAGS)
LDFLAGS ?=

PKG_CONFIG = pkg-config --cflags pixman-1 libdrm hyprland pangocairo libinput libudev wayland-server xkbcommon

SRC = main.cpp kinetic.cpp
OUT = $(PLUGIN_NAME).so

all: $(OUT)

$(OUT): $(SRC) globals.hpp kinetic.hpp
	$(CXX) $(CXXFLAGS) $(LDFLAGS) $(SRC) -o $@ `$(PKG_CONFIG)`

clean:
	rm -f $(OUT)

.PHONY: all clean
