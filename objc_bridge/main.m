#import <Foundation/Foundation.h>
#import "ZigLogger.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSLog(@"=== Zig Logger Objective-C Test ===");
        
        // Test 1: Basic logger creation and usage
        NSLog(@"\n--- Test 1: Basic Usage ---");
        ZigLogger *log = [ZigLogger loggerWithTag:@"TestApp"];
        [log info:@"Application started successfully"];
        [log debug:@"This is a debug message"];
        [log warn:@"This is a warning message"];
        [log error:@"This is an error message"];
        
        // Test 2: Multiple loggers with different tags
        NSLog(@"\n--- Test 2: Multiple Loggers ---");
        ZigLogger *networkLog = [[ZigLogger alloc] initWithTag:@"Network"];
        ZigLogger *dbLog = [[ZigLogger alloc] initWithTag:@"Database"];
        
        [networkLog info:@"Connecting to server..."];
        [dbLog debug:@"Executing query: SELECT * FROM users"];
        [networkLog warn:@"Connection timeout, retrying..."];
        [dbLog info:@"Query completed successfully"];
        
        // Test 3: Stress test with multiple messages
        NSLog(@"\n--- Test 3: Stress Test ---");
        ZigLogger *stressLog = [ZigLogger loggerWithTag:@"StressTest"];
        for (int i = 0; i < 10; i++) {
            NSString *message = [NSString stringWithFormat:@"Stress test message #%d", i + 1];
            [stressLog info:message];
        }
        
        // Test 4: Long messages
        NSLog(@"\n--- Test 4: Long Messages ---");
        ZigLogger *longLog = [ZigLogger loggerWithTag:@"LongMessage"];
        NSString *longMessage = @"This is a very long message that tests how the logger handles longer strings. "
                               @"It should work fine because the Zig logger uses a buffer for formatting. "
                               @"Let's see if it truncates properly or handles it gracefully.";
        [longLog info:longMessage];
        
        // Test 5: Special characters and Unicode
        NSLog(@"\n--- Test 5: Special Characters ---");
        ZigLogger *unicodeLog = [ZigLogger loggerWithTag:@"Unicode"];
        [unicodeLog info:@"Testing special chars: !@#$%^&*()"];
        [unicodeLog info:@"Testing Unicode: 🚀 Hello 世界 🌍"];
        
        NSLog(@"\n=== All tests completed ===");
        
        // Note: We don't test fatal() because it would exit the program
        NSLog(@"Note: fatal() test skipped as it would terminate the application");
    }
    return 0;
}
