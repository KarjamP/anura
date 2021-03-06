#
# Main Makefile, intended for use on Linux/X11 and compatible platforms
# using GNU Make.
#
# It should guess the paths to the game dependencies on its own, except for
# Boost which is assumed to be installed to the default locations. If you have
# installed Boost to a non-standard location, you will need to override CXXFLAGS
# and LDFLAGS with any applicable -I and -L arguments.
#
# The main options are:
#
#   CCACHE           The ccache binary that should be used when USE_CCACHE is
#                     enabled (see below). Defaults to 'ccache'.
#   CXX              C++ compiler comand line.
#   CXXFLAGS         Additional C++ compiler options.
#   OPTIMIZE         If set to 'yes' (default), builds with compiler
#                     optimizations enabled (-O2). You may alternatively use
#                     CXXFLAGS to set your own optimization options.
#   LDFLAGS          Additional linker options.
#   USE_CCACHE       If set to 'yes' (default), builds using the CCACHE binary
#                     to run the compiler. If ccache is not installed (i.e.
#                     found in PATH), this option has no effect.
#

OPTIMIZE=yes
CCACHE?=ccache
USE_CCACHE?=$(shell which $(CCACHE) 2>&1 > /dev/null && echo yes)
ifneq ($(USE_CCACHE),yes)
CCACHE=
endif

ifeq ($(OPTIMIZE),yes)
BASE_CXXFLAGS += -O2
endif

ifeq ($(CXX), g++)
GCC_GTEQ_490 := $(shell expr `$(CXX) -dumpversion | sed -e 's/\.\([0-9][0-9]\)/\1/g' -e 's/\.\([0-9]\)/0\1/g' -e 's/^[0-9]\{3,4\}$$/&00/'` \>= 40900)
ifeq "$(GCC_GTEQ_490)" "1"
BASE_CXXFLAGS += -fdiagnostics-color=auto -fsanitize=undefined
endif
endif

SDL2_CONFIG?=sdl2-config
USE_SDL2?=$(shell which $(SDL2_CONFIG) 2>&1 > /dev/null && echo yes)

ifneq ($(USE_SDL2),yes)
$(error SDL2 not found, SDL-1.2 is no longer supported)
endif

USE_LUA?=$(shell pkg-config --exists lua5.2 && echo yes)

# Initial compiler options, used before CXXFLAGS and CPPFLAGS.
BASE_CXXFLAGS += -std=c++0x -g -rdynamic -fno-inline-functions -fthreadsafe-statics -Wnon-virtual-dtor -Werror -Wignored-qualifiers -Wformat -Wswitch -Wreturn-type -DUSE_SHADERS -DUTILITY_IN_PROC -DUSE_ISOMAP -Wno-narrowing -Wno-literal-suffix
# -Wno-error=narrowing 

# Compiler include options, used after CXXFLAGS and CPPFLAGS.
INC := -Isrc $(shell pkg-config --cflags x11 sdl2 glew SDL2_image SDL2_ttf libpng zlib)

# Linker library options.
LIBS := $(shell pkg-config --libs x11 gl ) -lSDL2main \
	$(shell pkg-config --libs sdl2 glew SDL2_image libpng zlib) -lSDL2_ttf -lSDL2_mixer

ifeq ($(USE_LUA),yes)
	BASE_CXXFLAGS += -DUSE_LUA
	INC += $(shell pkg-config --cflags lua5.2)
	LIBS += $(shell pkg-config --libs lua5.2)
endif
	
# Enable Box2D if found.
ifeq ($(shell { cpp -x c++ -include Box2D/Box2D.h /dev/null \
	&& ld -lBox2D; } >/dev/null 2>/dev/null; \
	echo $$?),0)
  BASE_CXXFLAGS += -DUSE_BOX2D
  LIBS += -lBox2D
endif

TARBALL := /var/www/anura/anura-$(shell date +"%Y%m%d-%H%M").tar.bz2

include Makefile.common

src/%.o : src/%.cpp
	@echo "Building:" $<
	@$(CCACHE) $(CXX) $(BASE_CXXFLAGS) $(CXXFLAGS) $(CPPFLAGS) $(INC) -DIMPLEMENT_SAVE_PNG -c -o $@ $<
	@$(CXX) $(BASE_CXXFLAGS) $(CXXFLAGS) $(CPPFLAGS) $(INC) -DIMPLEMENT_SAVE_PNG -MM $< > $*.d
	@mv -f $*.d $*.d.tmp
	@sed -e 's|.*:|src/$*.o:|' < $*.d.tmp > src/$*.d
	@sed -e 's/.*://' -e 's/\\$$//' < $*.d.tmp | fmt -1 | \
		sed -e 's/^ *//' -e 's/$$/:/' >> src/$*.d
	@rm -f $*.d.tmp

anura: $(objects)
	@echo "Linking : anura"
	@$(CCACHE) $(CXX) \
		$(BASE_CXXFLAGS) $(LDFLAGS) $(CXXFLAGS) $(CPPFLAGS) $(INC) \
		$(objects) -o anura \
		$(LIBS) -lboost_regex -lboost_system -lboost_filesystem -lpthread -fthreadsafe-statics

# pull in dependency info for *existing* .o files
-include $(objects:.o=.d)

clean:
	rm -f src/*.o src/*.d *.o *.d anura

unittests: anura
	./anura --tests
	
tarball: unittests
	@tar --transform='s,^,anura/,g' -cjf $(TARBALL) anura data/ images/
	
assets:
	./anura --utility=compile_levels
	./anura --utility=compile_objects
