// .note.dlopen (systemd's ELF_NOTE_DLOPEN, https://systemd.io/ELF_DLOPEN_METADATA/): notes of
// owner "FDO", type 0x407c0c0a, each a JSON array of {feature, soname: [...], ...}. A soname
// named there is a library the code dlopen()s by that name, so the dir that provides it belongs
// on the RUNPATH of the object that calls dlopen. Read as ELF structures from objects at link time
// (driver.cc: the link puts the providing dependency dirs on the padded RUNPATH) and from the
// finished file (elf_fixup.cc: a dir of the package's own stays there).
#pragma once

#include <filesystem>
#include <string>
#include <string_view>
#include <vector>

namespace jig {

// sonames in the notes of one .note.dlopen section's bytes (4-byte aligned notes). Notes of
// another owner or type, and malformed JSON, are skipped
auto ParseDlopenNotes(std::string_view section) -> std::vector<std::string>;

// sonames in the .note.dlopen sections of an ELF64 little-endian file held in memory. Not such a
// file: none
auto ElfDlopenSonames(std::string_view image) -> std::vector<std::string>;

// of a link input: a relocatable object, or each member of an ar archive (thin or not) that is
// one. Shared libraries and anything else: none (their notes are their own)
auto LinkInputDlopenSonames(const std::filesystem::path& path) -> std::vector<std::string>;

}  // namespace jig
