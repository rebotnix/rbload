# Compiler settings
NVCC ?= nvcc
CXX ?= g++

# Warning flags
COMMON_WARNINGS ?= -Wall -Wextra -Werror
CUDA_WARNINGS ?= -Xcompiler "-Wall -Wextra" -Xcudafe --display_error_number

# Compiler flags
NVCCFLAGS ?= -O2 $(CUDA_WARNINGS) --ptxas-options=-v
CXXFLAGS ?= -O2 -std=c++11 $(COMMON_WARNINGS)

# Linker flags
LDFLAGS ?= -lpthread

# CUDA architecture settings for Jetson
# Jetson Nano: 53
# Jetson Xavier NX: 72
# Jetson AGX Xavier: 72
# Jetson TX2: 62
# Please adjust according to your Jetson model
ARCH ?= -arch=sm_53

# Source files
SOURCES = rbload.cu

# Output binary
TARGET = rbload

all: $(TARGET)

$(TARGET): $(SOURCES)
	$(NVCC) $(NVCCFLAGS) $(ARCH) -o $(TARGET) $(SOURCES) $(LDFLAGS)

clean:
	rm -f $(TARGET)

.PHONY: all clean
