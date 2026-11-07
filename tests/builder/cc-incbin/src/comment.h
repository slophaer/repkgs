/* the words in comments, as LLVM's MCTargetOptions.h and x86's nospec-branch.h have them:
 * from C via asm(".include <asm/nospec-branch.h>") but let's not go there.
 */
/// Additional paths to search for `.include` directives; resolving .incbin directives
static const int comment_h = 1;
