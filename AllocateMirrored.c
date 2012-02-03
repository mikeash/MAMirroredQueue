#include <dispatch/dispatch.h>
#include <errno.h>
#include <mach/mach.h>
#include <mach/vm_map.h>
#include <stdio.h>
#include <stdlib.h>

#include "AllocateMirrored.h"


void *allocate_mirrored(size_t howmuch, unsigned howmany)
{
    // make sure it's positive and an exact multiple of page size
    if(howmuch <= 0 || howmuch != trunc_page(howmuch))
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
        
        CHECK_ERR(vm_allocate(mach_task_self(), (vm_address_t *)&mem, howmuch * howmany, VM_FLAGS_ANYWHERE), 0);
        
        char *target = mem + howmuch;
        CHECK_ERR(vm_deallocate(mach_task_self(), (vm_address_t)target, howmuch * (howmany - 1)), howmuch * howmany);
        
        for(unsigned i = 1; i < howmany && mem != NULL; i++)
        {
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
            target += howmuch;
            
            if(err == KERN_NO_SPACE)
            {
                CHECK_ERR(vm_deallocate(mach_task_self(), (vm_address_t)mem, howmuch * i), 0);
                mem = NULL;
            }
            else
            {
                CHECK_ERR(err, howmuch * i);
            }
        }
    }
    return mem;
}

void free_mirrored(void *ptr, size_t howmuch, unsigned howmany)
{
    vm_deallocate(mach_task_self(), (vm_address_t)ptr, howmuch * howmany);
}

size_t get_page_size(void)
{
    return vm_page_size;
}

// test code here

static void test_size(unsigned howmany, size_t howmuch)
{
    char *buf = allocate_mirrored(howmuch, howmany);
    
    unsigned short seed[3] = { 0 };
    for(unsigned j = 0; j < howmany; j++)
    {
        for(size_t i = 0; i < howmuch; i++)
            buf[i] = nrand48(seed);
        if(memcmp(buf, buf + howmuch * j, howmuch) != 0)
            fprintf(stderr, "FAIL: writing to first half didn't update second half with size %lu\n", (long)howmuch);
        
        for(size_t i = 0; i < howmuch; i++)
            buf[howmuch * j + i] = nrand48(seed);
        if(memcmp(buf, buf + howmuch * j, howmuch) != 0)
            fprintf(stderr, "FAIL: writing to second half didn't update first half with size %lu\n", (long)howmuch);
    }
    
    free_mirrored(buf, howmuch, howmany);
}

void test_allocate_mirrored(void)
{
    for(unsigned i = 2; i < 10; i++)
    {
        test_size(i, get_page_size());
        test_size(i, get_page_size() * 2);
        test_size(i, get_page_size() * 10);
        test_size(i, get_page_size() * 100);
    }
}
