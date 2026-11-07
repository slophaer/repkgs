// a header whose comments name .incbin and .include: nothing here reads another file,
// so the compile is cacheable
#include "comment.h"
int comment(void) { return comment_h; }
