// clang -framework Foundation -W -Wall -Wno-unused-parameter main.m AllocatePair.c

#import <Cocoa/Cocoa.h>

#import "AllocatePair.h"
#import "MAMirroredQueue.h"


int main(int argc, char **argv)
{
    test_allocate_pair();
}
