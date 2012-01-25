#include <dispatch/dispatch.h>
#include <errno.h>
#include <mach/mach.h>
#include <mach/vm_map.h>
#include <stdio.h>
#include <stdlib.h>

#include "AllocatePair.h"


void *allocate_pair(size_t howmuch)
{
    // make sure it's positive and an exact multiple of page size
    if(howmuch <= 0 || howmuch != howmuch / get_page_size() * get_page_size())
    {
        errno = EINVAL;
        return NULL;
    }
    
    char *mem = NULL;
    while(mem == NULL)
    {
        #define CHECK_ERR(expr, todealloc) do { \
            kern_return_t __check_err = (expr); \
            if(__check_err != KERN_SUCCESS) \
            { \
                if(todealloc > 0) \
                    vm_deallocate(mach_task_self(), (vm_address_t)mem, (todealloc)); \
                errno = ENOMEM; \
                return NULL; \
            } \
        } while(0)
        
        CHECK_ERR(vm_allocate(mach_task_self(), (vm_address_t *)&mem, howmuch * 2, VM_FLAGS_ANYWHERE), 0);
        
        char *target = mem + howmuch;
        CHECK_ERR(vm_deallocate(mach_task_self(), (vm_address_t)target, howmuch), howmuch * 2);
        
        vm_prot_t curProtection, maxProtection;
        kern_return_t err = vm_remap(mach_task_self(),
                                     (vm_address_t *)&target,
                                     howmuch,
                                     0, // mask
                                     0, // anywhere
                                     mach_task_self(),
                                     (vm_address_t)mem,
                                     0, // copy
                                     &curProtection,
                                     &maxProtection,
                                     VM_INHERIT_COPY);
        if(err == KERN_PROTECTION_FAILURE)
        {
            CHECK_ERR(vm_deallocate(mach_task_self(), (vm_address_t)mem, howmuch), 0);
            mem = NULL;
        }
        else
        {
            CHECK_ERR(err, howmuch);
        }
    }
    return mem;
}

void free_pair(void *ptr, size_t howmuch)
{
    vm_deallocate(mach_task_self(), (vm_address_t)ptr, howmuch * 2);
}

size_t get_page_size(void)
{
    static vm_size_t pageSize;
    static dispatch_once_t pred;
    dispatch_once(&pred, ^{
        kern_return_t ret = host_page_size(mach_host_self(), &pageSize);
        if(ret != KERN_SUCCESS)
            pageSize = 4096; // a pretty good guess
    });
    return pageSize;
}

// test code here

static void test_size(size_t howmuch)
{
    char *buf = allocate_pair(howmuch);
    
    unsigned short seed[3] = { 0 };
    for(size_t i = 0; i < howmuch; i++)
        buf[i] = nrand48(seed);
    if(memcmp(buf, buf + howmuch, howmuch) != 0)
        fprintf(stderr, "FAIL: writing to first half didn't update second half with size %lu\n", (long)howmuch);
    
    for(size_t i = 0; i < howmuch; i++)
        buf[howmuch + i] = nrand48(seed);
    if(memcmp(buf, buf + howmuch, howmuch) != 0)
        fprintf(stderr, "FAIL: writing to second half didn't update first half with size %lu\n", (long)howmuch);
    
    free_pair(buf, howmuch);
}

void test_allocate_pair(void)
{
    test_size(get_page_size());
    test_size(get_page_size() * 2);
    test_size(get_page_size() * 10);
    test_size(get_page_size() * 100);
}
