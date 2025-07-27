#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Objective-C wrapper for the Zig Logger
 * Provides a natural Objective-C API that mirrors the Zig usage pattern
 */
@interface ZigLogger : NSObject

/**
 * Create a new logger with the specified tag
 * @param tag The tag to identify this logger's output
 * @return A new ZigLogger instance
 */
+ (instancetype)loggerWithTag:(NSString *)tag;

/**
 * Initialize a logger with the specified tag
 * @param tag The tag to identify this logger's output
 * @return An initialized ZigLogger instance
 */
- (instancetype)initWithTag:(NSString *)tag;

/**
 * Log an informational message
 * @param message The message to log
 */
- (void)info:(NSString *)message;

/**
 * Log a warning message
 * @param message The message to log
 */
- (void)warn:(NSString *)message;

/**
 * Log a debug message
 * @param message The message to log
 */
- (void)debug:(NSString *)message;

/**
 * Log an error message
 * @param message The message to log
 */
- (void)error:(NSString *)message;

/**
 * Log a fatal message and exit the application
 * @param message The message to log before exiting
 */
- (void)fatal:(NSString *)message NS_SWIFT_UNAVAILABLE("Use fatalError() in Swift");

@end

NS_ASSUME_NONNULL_END
