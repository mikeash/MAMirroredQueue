
#import "MAMirroredQueue.h"

#include <mach/mach.h>

#import "AllocatePair.h"


// Utility functions
static size_t RoundUpToPageSize(size_t n)
{
    size_t pageSize = get_page_size();
    return ((n + pageSize - 1) / pageSize) * pageSize;
}

static void *RoundDownToPageSize(void *ptr)
{
    size_t pageSize = get_page_size();
    intptr_t n = (intptr_t)ptr;
    n = (n / pageSize) * pageSize;
    return (void *)n;
}

// Class implementation
@implementation MAMirroredQueue
{
    char *_buf;
    size_t _bufSize;
    BOOL _allocationLocked;
    
    char *_readPointer;
    char *_writePointer;
}

- (void)dealloc
{
    if(_buf)
        free_pair(_buf, _bufSize);
}

- (size_t)availableBytes
{
    ptrdiff_t amount = _writePointer - _readPointer;
    
    if(amount < 0)
        amount += _bufSize;
    else if((size_t)amount > _bufSize)
        amount -= _bufSize;
    
    return amount;
}

- (void *)readPointer
{
    return _readPointer;
}

- (void)advanceReadPointer: (size_t)howmuch
{
    _readPointer += howmuch;
    
    if((size_t)(_readPointer - _buf) >= _bufSize)
    {
        _readPointer -= _bufSize;
        _writePointer -= _bufSize;
    }
}

- (BOOL)ensureWriteSpace: (size_t)howmuch
{
    size_t contentLength = [self availableBytes];
    if(howmuch <= _bufSize - contentLength)
        return YES;
    else if(_allocationLocked)
        return NO;
    
    // else reallocate
    size_t newBufferLength = RoundUpToPageSize(contentLength + howmuch);
    char *newBuf = allocate_pair(newBufferLength);
    
    if(_bufSize > 0)
    {
        char *copyStart = RoundDownToPageSize(_readPointer);
        size_t copyLength = RoundUpToPageSize(_writePointer - copyStart);
        
        vm_copy(mach_task_self(), (vm_address_t)copyStart, copyLength, (vm_address_t)newBuf);
        
        char *newReadPointer = newBuf + (_readPointer - copyStart);
        if(*newReadPointer != *_readPointer)
            abort();
        
        free_pair(_buf, _bufSize);
        _readPointer = newReadPointer;
        _writePointer = _readPointer + contentLength;
    }
    else
    {
        _readPointer = newBuf;
        _writePointer = newBuf;
    }
    
    _buf = newBuf;
    _bufSize = newBufferLength;
    
    return YES;
}

- (void *)writePointer
{
    return _writePointer;
}

- (void)advanceWritePointer: (size_t)howmuch
{
    _writePointer += howmuch;
}

- (void)lockAllocation
{
    _allocationLocked = YES;
}

- (void)unlockAllocation
{
    _allocationLocked = NO;
}

// UNIX-like compatibility wrappers
- (size_t)read: (void *)buf count: (size_t)howmuch
{
    size_t toRead = MIN(howmuch, [self availableBytes]);
    memcpy(buf, [self readPointer], toRead);
    [self advanceReadPointer: toRead];
    return toRead;
}

- (size_t)write: (const void *)buf count: (size_t)howmuch
{
    [self ensureWriteSpace: howmuch];
    memcpy([self writePointer], buf, howmuch);
    return howmuch;
}

@end

// Test methods
@implementation MAMirroredQueue (Testing)

static void fail(const char *fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    
    vfprintf(stderr, fmt, args);
    fprintf(stderr, "\n");
    
    va_end(args);
}

static void check_equal(MAMirroredQueue *queue, NSData *auxQueue)
{
    const unsigned char *buf1 = [queue readPointer];
    const unsigned char *buf2 = [auxQueue bytes];
    
    size_t length = [queue availableBytes];
    for(size_t i = 0; i < length; i++)
        if(buf1[i] != buf2[i])
            fail("bytes don't match, %d != %d at index %lu", buf1[i], buf2[i], (long)i);
}

+ (void)testThreaded
{
    unsigned short seed[3] = { 0 };
    
    NSLock *queueLock = [[NSLock alloc] init];
    
    for(int iter = 0; iter < 1000000; iter++)
    {
        unsigned short *seedPtr1 = (unsigned short[]) { nrand48(seed), nrand48(seed), nrand48(seed) };
        unsigned short *seedPtr2 = (unsigned short[]) { nrand48(seed), nrand48(seed), nrand48(seed) };
        
        NSUInteger targetLength = nrand48(seed) % 1024 * 1024 + 1;
        
        MAMirroredQueue *queue = [[MAMirroredQueue alloc] init];
        [queue ensureWriteSpace: 10240];
        [queue lockAllocation];
        
        NSMutableData *inData = [NSMutableData data];
        NSMutableData *outData = [NSMutableData data];
        
        dispatch_group_t group = dispatch_group_create();
        
        dispatch_group_async(group, dispatch_get_global_queue(0, 0), ^{
            while([inData length] < targetLength)
            {
                unsigned len = nrand48(seedPtr1) % 1024 + 1;
                unsigned remaining = targetLength - [inData length];
                len = MIN(len, remaining);
                
                char buf[len];
                for(unsigned i = 0; i < len; i++)
                    buf[i] = nrand48(seedPtr1);
                
                [queueLock lock];
                while(![queue ensureWriteSpace: len])
                {
                    [queueLock unlock];
                    usleep(1);
                    [queueLock lock];
                }
                
                memcpy([queue writePointer], buf, len);
                [queue advanceWritePointer: len];
                [queueLock unlock];
                
                [inData appendBytes: buf length: len];
            }
        });
        dispatch_group_async(group, dispatch_get_global_queue(0, 0), ^{
            while([outData length] < targetLength)
            {
                unsigned len = nrand48(seedPtr2) % 10240 + 1;
                [queueLock lock];
                unsigned available = [queue availableBytes];
                [queueLock unlock];
                len = MIN(len, available);
                
                if(len > 0)
                {
                    [queueLock lock];
                    [outData appendBytes: [queue readPointer] length: len];
                    [queue advanceReadPointer: len];
                    [queueLock unlock];
                }
            }
        });
        
        dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
        
        if(![inData isEqual: outData])
            fail("Datas not equal!");
        
        fprintf(stderr, "iteration %d done\n", iter);
    }
}

+ (void)runTests
{
    [self testThreaded];
    return;
    
    unsigned short seed[3] = { 0 };
    
    for(int iter = 0; iter < 1000; iter++)
    {
        MAMirroredQueue *queue = [[MAMirroredQueue alloc] init];
        NSMutableData *auxQueue = [NSMutableData data];
        
        int readStart = nrand48(seed) % 100 + 1;
        int writeStop = nrand48(seed) % 1000 + readStart;
        int maxLength = nrand48(seed) % 65536;
        for(int i = 0; i < writeStop || [queue availableBytes] > 0; i++)
        {
            BOOL write = (i < readStart || (nrand48(seed) % 2)) && i < writeStop;
            
            size_t length = nrand48(seed) % (maxLength + 1);
            
            if(write)
            {
                [queue ensureWriteSpace: length];
                check_equal(queue, auxQueue);
                char *buf = [queue writePointer];
                for(unsigned j = 0; j < length; j++)
                {
                    unsigned char byte = nrand48(seed);
                    buf[j] = byte;
                    [auxQueue appendBytes: &byte length: 1];
                }
                check_equal(queue, auxQueue);
                [queue advanceWritePointer: length];
                check_equal(queue, auxQueue);
            }
            else
            {
                length = MIN(length, [queue availableBytes]);
                check_equal(queue, auxQueue);
                [queue advanceReadPointer: length];
                [auxQueue replaceBytesInRange: NSMakeRange(0, length) withBytes: NULL length: 0];
            }
            
            if([queue availableBytes] != [auxQueue length])
                fail("lengths don't match: %lu != %lu", (long)[queue availableBytes], (long)[auxQueue length]);
            
            check_equal(queue, auxQueue);
        }
    }
}

@end
