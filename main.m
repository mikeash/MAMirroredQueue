// clang -framework Foundation -W -Wall -Wno-unused-parameter -fobjc-arc main.m AllocateMirrored.c MAMirroredQueue.m

#import <Cocoa/Cocoa.h>

#import "AllocateMirrored.h"
#import "MAMirroredQueue.h"


int main(int argc, char **argv)
{
    @autoreleasepool
    {
        test_allocate_mirrored();
        [MAMirroredQueue runTests];
    }
}
