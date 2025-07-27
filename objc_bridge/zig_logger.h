#ifndef ZIG_LOGGER_H
#define ZIG_LOGGER_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque struct representing the Zig Logger
// Size must match the Zig Logger struct layout
typedef struct {
    char tag_buf[128];      // MAX_TAG_LEN from Zig
    size_t tag_len;
    // LogOptions config fields - we need to match the exact layout
    char config_tag_ptr[8]; // pointer to tag slice
    size_t config_tag_len;  // tag slice length
    int config_color;       // LogColor enum (optional)
    void* config_file;      // File pointer (optional)
    char config_show_timestamp; // bool
    char config_show_level;     // bool
    char _padding[32];      // Extra padding for safety
} Logger;

// C API functions
void zig_logger_create(const char* tag, Logger* out_logger);
void zig_logger_info(Logger* logger, const char* message);
void zig_logger_warn(Logger* logger, const char* message);
void zig_logger_debug(Logger* logger, const char* message);
void zig_logger_error(Logger* logger, const char* message);
void zig_logger_fatal(Logger* logger, const char* message);

#ifdef __cplusplus
}
#endif

#endif // ZIG_LOGGER_H
