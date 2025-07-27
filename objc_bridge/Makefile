# Makefile for building Zig Logger with Objective-C bridge
#
# This builds:
# 1. The Zig logger as a static library
# 2. The Objective-C test application that links against it

# Configuration
ZIG_SRC_DIR = ../src
ZIG_BUILD_DIR = ../zig-out
OBJC_SRC_DIR = .
BUILD_DIR = build

# Targets
ZIG_LIB = $(ZIG_BUILD_DIR)/lib/libzig-logger.a
OBJC_APP = $(BUILD_DIR)/test_app

# Compiler flags
OBJC_FLAGS = -fobjc-arc -framework Foundation
INCLUDE_FLAGS = -I$(OBJC_SRC_DIR)
LINK_FLAGS = -L$(ZIG_BUILD_DIR)/lib -lzig-logger

.PHONY: all clean zig-lib objc-app test

all: $(OBJC_APP)

# Build the Zig library
zig-lib: $(ZIG_LIB)

$(ZIG_LIB):
	@echo "Building Zig logger library..."
	cd .. && zig build

# Build the Objective-C application
objc-app: $(OBJC_APP)

$(OBJC_APP): $(ZIG_LIB) $(OBJC_SRC_DIR)/main.m $(OBJC_SRC_DIR)/ZigLogger.m
	@echo "Building Objective-C test application..."
	@mkdir -p $(BUILD_DIR)
	clang $(OBJC_FLAGS) $(INCLUDE_FLAGS) \
		$(OBJC_SRC_DIR)/main.m $(OBJC_SRC_DIR)/ZigLogger.m \
		$(LINK_FLAGS) \
		-o $(OBJC_APP)

# Run the test application
test: $(OBJC_APP)
	@echo "Running Objective-C test application..."
	@echo "========================================="
	./$(OBJC_APP)

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	rm -rf $(BUILD_DIR)
	cd .. && rm -rf zig-out .zig-cache

# Help target
help:
	@echo "Available targets:"
	@echo "  all      - Build everything (default)"
	@echo "  zig-lib  - Build only the Zig library"
	@echo "  objc-app - Build only the Objective-C application"
	@echo "  test     - Build and run the test application"
	@echo "  clean    - Clean all build artifacts"
	@echo "  help     - Show this help message"
