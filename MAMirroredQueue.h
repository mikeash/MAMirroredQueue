
#import <Foundation/Foundation.h>


@interface MAMirroredQueue : NSObject

- (size_t)availableBytes;
- (void *)readPointer;
- (void)advanceReadPointer: (size_t)howmuch;

- (BOOL)ensureWriteSpace: (size_t)howmuch;
- (void *)writePointer;
- (void)advanceWritePointer: (size_t)howmuch;

- (void)lockAllocation;
- (void)unlockAllocation;

// UNIX-like wrappers

- (size_t)read: (void *)buf count: (size_t)howmuch;
- (size_t)write: (const void *)buf count: (size_t)howmuch;

@end

@interface MAMirroredQueue (Testing)

+ (void)runTests;

@end
