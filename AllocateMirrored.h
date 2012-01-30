
#include <stddef.h>

void *allocate_mirrored(size_t howmuch, unsigned howmany);
void free_mirrored(void *ptr, size_t howmuch, unsigned howmany);
size_t get_page_size(void);

void test_allocate_mirrored(void);
