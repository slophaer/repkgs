// The C/C++ compiler entry point (argv[0] = cc, c++, gcc, g++, clang, clang++).
//
// Cached: `cc -c x.c` (the object), `cc x.c -o x` with no object inputs (configure and cmake
// probes), `cc *.o *.a -o x` (a link: keyed on the InputId of every object argument, lld's
// --dependency-file adds crt files, -l libraries and linker scripts to the manifest), `cc -E x.c`
// and `cc -S x.c` (configure's preprocessor probes: the text, to stdout when no -o), and compile
// *failures* whose inputs are all known. Never cached: -M runs, several sources at once,
// sources mixed with objects, @response files, a failure caused by something absent (missing
// header, any link error) that a later build might provide.
#pragma once

#include <filesystem>
#include <span>
#include <string>
#include <vector>

#include "driver.h"
#include "keys.h"

namespace jig {

struct Invocation {
  std::vector<std::string> args;      // passed to the real compiler
  std::vector<std::string> key_args;  // what influences the output: all but -o, depfile options, the source
  std::string source;                 // the one translation unit, or the output name of a link (log label)
  std::vector<std::string> inputs;    // object/archive/shared-object arguments of a link
  std::vector<std::string> pch;       // -include-pch files: build-tree binaries no manifest header covers
  std::filesystem::path output;       // object for -c, text for -E/-S, else the executable / shared object
  bool compile_only = false;          // -c, -S or -E: one translation unit in, one file out, no link
  bool to_stdout = false;             // -E without -o
  bool link_one = false;              // one source straight to an executable, no object inputs
  bool link = false;                  // objects only
  bool cacheable = true;
  bool query = false;  // asks the compiler something instead of building: -v, -dM, -print-*, -E of no file
  // depfile requested by the build system (-MD/-MMD/-MF/-MT/-Wp,-MD,…): left out of the key,
  // cached as an extra artifact so a hit reproduces it
  bool wants_depfile = false;
  std::filesystem::path depfile;
  std::string depfile_target;  // -MT/-MQ value, written into a replayed depfile
};

auto ParseInvocation(std::span<const std::string> args) -> Invocation;

// Whether a source or an included file may read another file the depfile does not name. The
// assembler's `.incbin` and `.include` do: clang writes `t.o: t.S` for a `.S` that embeds
// data.bin or includes data.inc, so the key never sees a change of that file (LLVM does not
// implement `as -MD`, llvm/llvm-project#54996). Matches `incbin` and the word `.include` in any case,
// in an assembly file or in the asm string of a C file; a C++ member such as `.IncludeLoc` is not
// the directive. The C preprocessor's `#include` has no dot and
// stays out: its files are in the depfile. A compile whose inputs say true is never stored or
// replayed.
auto MentionsIncbin(std::string_view text) -> bool;
// The same for the arguments the build system passed: `-DEMBED=.incbin`, `-Wa,...`, `-Xassembler`
// all carry assembler text. All arguments are scanned, not a list of options: a missed option
// would replay stale data, and a false hit (a path with the word in it) costs one compile.
auto ArgsMentionIncbin(std::span<const std::string> args) -> bool;

// JIG_PASSTHROUGH: only the value "1" turns it on. Empty, "0", "false", "off" and every other
// value keep the driver policy.
auto PassthroughEnabled(std::string_view value) -> bool;

// The raw compiler's arguments for passthrough: the build system's words, plus the language driver
// mode a c++ link needs (the conf's compiler is clang, not clang++).
auto PassthroughArgs(Language lang, std::span<const std::string> user_args) -> std::vector<std::string>;

// The compiler's arguments and the words that join the cache key: the conf's policy around the build
// system's words, or with passthrough only those words (plus a c++ link's driver mode). Passthrough
// skips the policy flags (hardening, sysroot, RUNPATH, interpreter, prefix map), not the depfile jig
// adds to learn the inputs, so the compile cache still applies, under a key of its own.
void ApplyDriverConf(Invocation& inv, const DriverConf& conf, Language lang, std::span<const std::string> user_args,
                     bool passthrough);

auto RunCcMode(std::string_view argv0, std::span<const std::string> raw_args, const std::string& socket_path) -> int;

}  // namespace jig
