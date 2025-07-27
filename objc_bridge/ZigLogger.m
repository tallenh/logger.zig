#import "ZigLogger.h"
#include "zig_logger.h"

@interface ZigLogger () {
    Logger _logger;  // Store the Zig Logger as a value, not pointer!
}
@end

@implementation ZigLogger

+ (instancetype)loggerWithTag:(NSString *)tag {
    return [[self alloc] initWithTag:tag];
}

- (instancetype)initWithTag:(NSString *)tag {
    self = [super init];
    if (self) {
        const char *tagCStr = [tag UTF8String];
        zig_logger_create(tagCStr, &_logger);  // Pass pointer to _logger
    }
    return self;
}

- (void)info:(NSString *)message {
    const char *msgCStr = [message UTF8String];
    zig_logger_info(&_logger, msgCStr);
}

- (void)warn:(NSString *)message {
    const char *msgCStr = [message UTF8String];
    zig_logger_warn(&_logger, msgCStr);
}

- (void)debug:(NSString *)message {
    const char *msgCStr = [message UTF8String];
    zig_logger_debug(&_logger, msgCStr);
}

- (void)error:(NSString *)message {
    const char *msgCStr = [message UTF8String];
    zig_logger_error(&_logger, msgCStr);
}

- (void)fatal:(NSString *)message {
    const char *msgCStr = [message UTF8String];
    zig_logger_fatal(&_logger, msgCStr);
    // This function never returns
}

@end
