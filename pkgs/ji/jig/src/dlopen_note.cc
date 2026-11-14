#include "dlopen_note.h"

#include <elf.h>
#include <fcntl.h>
#include <sys/types.h>
#include <unistd.h>

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <json.hpp>
#include <optional>
#include <string>
#include <string_view>
#include <type_traits>
#include <utility>
#include <vector>

#include "base.h"

namespace jig {

namespace {

namespace fs = std::filesystem;

constexpr std::uint32_t kDlopenNoteType = 0x407c0c0a;
constexpr std::string_view kDlopenOwner = "FDO";
constexpr std::string_view kDlopenSection = ".note.dlopen";
constexpr std::string_view kArMagic = "!<arch>\n";
constexpr std::string_view kThinMagic = "!<thin>\n";
constexpr std::uint64_t kArHeader = 60;
constexpr std::uint64_t kArNameField = 16;
constexpr std::uint64_t kArSizeAt = 48;
constexpr std::uint64_t kArSizeField = 10;
constexpr std::uint64_t kArEndAt = 58;
constexpr std::uint64_t kNoteHeader = 12;
constexpr std::uint64_t kNoteAlign = 4;
// a section table or note section this big is no object's: refuse rather than allocate
constexpr std::uint64_t kMaxRead = std::uint64_t{64} * 1024 * 1024;

// [offset, offset + size) of an open file, nullopt when it is shorter
auto ReadAt(int file, std::uint64_t offset, std::uint64_t size) -> std::optional<std::string> {
  if (size > kMaxRead) {
    return std::nullopt;
  }
  std::string out(size, '\0');
  std::uint64_t filled = 0;
  while (filled < size) {
    const ssize_t got = ::pread(file, &out.at(filled), size - filled, static_cast<off_t>(offset + filled));
    if (got <= 0) {
      return std::nullopt;
    }
    filled += static_cast<std::uint64_t>(got);
  }
  return out;
}

auto FileReader(int file) {
  return [file](std::uint64_t offset, std::uint64_t size) -> std::optional<std::string> {
    return ReadAt(file, offset, size);
  };
}

template <typename T>
  requires std::is_trivially_copyable_v<T>
auto Load(std::string_view bytes, std::uint64_t offset) -> std::optional<T> {
  if (offset > bytes.size() || bytes.size() - offset < sizeof(T)) {
    return std::nullopt;
  }
  T value{};
  std::memcpy(&value, &bytes.at(offset), sizeof(T));
  return value;
}

auto Align(std::uint64_t size) -> std::uint64_t { return (size + kNoteAlign - 1) / kNoteAlign * kNoteAlign; }

// the NUL-terminated string at `offset` of a string table
auto CStringAt(std::string_view table, std::uint64_t offset) -> std::string_view {
  const std::string_view rest = table.substr(offset);
  return rest.substr(0, rest.find('\0'));
}

auto TrimNul(std::string_view text) -> std::string_view {
  while (text.ends_with('\0')) {
    text.remove_suffix(1);
  }
  return text;
}

void Merge(std::vector<std::string>& into, std::vector<std::string> more) {
  for (std::string& soname : more) {
    if (!std::ranges::contains(into, soname)) {
      into.push_back(std::move(soname));
    }
  }
}

// the soname lists of a note's JSON: [{"feature": …, "soname": ["libz.so.1", …]}, …]
void AddJsonSonames(std::string_view json, std::vector<std::string>& out) {
  const nlohmann::json doc = nlohmann::json::parse(json, nullptr, /*allow_exceptions=*/false);
  if (!doc.is_array()) {
    return;
  }
  for (const nlohmann::json& entry : doc) {
    const auto sonames = entry.is_object() ? entry.find("soname") : entry.end();
    if (sonames == entry.end() || !sonames->is_array()) {
      continue;
    }
    for (const nlohmann::json& soname : *sonames) {
      if (soname.is_string()) {
        Merge(out, {soname.get<std::string>()});
      }
    }
  }
}

// the ELF file at `base` of what `read(offset, size)` reads. relocatable_only: a link input, whose
// shared libraries carry notes of their own
template <typename Read>
auto SonamesAt(const Read& read, std::uint64_t base, bool relocatable_only) -> std::vector<std::string> {
  const std::optional<std::string> head = read(base, sizeof(Elf64_Ehdr));
  const std::optional<Elf64_Ehdr> ehdr = head ? Load<Elf64_Ehdr>(*head, 0) : std::nullopt;
  if (!ehdr || !head->starts_with(std::string_view(ELFMAG, SELFMAG)) || head->at(EI_CLASS) != ELFCLASS64 ||
      head->at(EI_DATA) != ELFDATA2LSB || (relocatable_only && ehdr->e_type != ET_REL) ||
      ehdr->e_shentsize != sizeof(Elf64_Shdr) || ehdr->e_shstrndx >= ehdr->e_shnum) {
    return {};
  }
  const std::optional<std::string> table =
      read(base + ehdr->e_shoff, std::uint64_t{ehdr->e_shnum} * sizeof(Elf64_Shdr));
  const auto shdr = [&](std::uint64_t index) -> std::optional<Elf64_Shdr> {
    return table ? Load<Elf64_Shdr>(*table, index * sizeof(Elf64_Shdr)) : std::nullopt;
  };
  const std::optional<Elf64_Shdr> names_shdr = shdr(ehdr->e_shstrndx);
  const std::optional<std::string> names =
      names_shdr ? read(base + names_shdr->sh_offset, names_shdr->sh_size) : std::nullopt;
  if (!names) {
    return {};
  }
  std::vector<std::string> out;
  for (std::uint64_t i = 0; i < ehdr->e_shnum; ++i) {
    const std::optional<Elf64_Shdr> section = shdr(i);
    if (!section || section->sh_type != SHT_NOTE || section->sh_name >= names->size() ||
        CStringAt(*names, section->sh_name) != kDlopenSection) {
      continue;
    }
    if (const std::optional<std::string> notes = read(base + section->sh_offset, section->sh_size)) {
      Merge(out, ParseDlopenNotes(*notes));
    }
  }
  return out;
}

// a member's name: "x.o/" (GNU short name), "/<offset>" into the long-name table ("name/\n" each)
auto MemberName(const std::string& field, std::string_view long_names) -> std::string {
  std::string name = field;
  if (field.size() > 1 && field.starts_with('/')) {
    const std::optional<std::uint64_t> index = ParseUint(std::string_view(field).substr(1));
    const std::string_view rest = index && *index < long_names.size() ? long_names.substr(*index) : "";
    name = rest.substr(0, rest.find('\n'));
  }
  if (name.ends_with('/')) {
    name.pop_back();
  }
  return name;
}

// a thin archive's member: a file named relative to the archive
auto ThinMemberSonames(const fs::path& archive, const std::string& member) -> std::vector<std::string> {
  const fs::path on_disk = fs::path(member).is_absolute() ? fs::path(member) : archive.parent_path() / member;
  const UniqueFd object(::open(on_disk.c_str(), O_RDONLY | O_CLOEXEC));  // NOLINT(cppcoreguidelines-pro-type-vararg)
  return object.valid() ? SonamesAt(FileReader(object.get()), 0, true) : std::vector<std::string>{};
}

// every member of a GNU/SysV ar archive (what llvm-ar writes on ELF platforms). A thin archive
// (meson's internal static libraries) holds only names: the members are files beside it
auto ArchiveSonames(int file, const fs::path& path, bool thin) -> std::vector<std::string> {
  std::vector<std::string> out;
  std::string long_names;
  for (std::uint64_t offset = kArMagic.size();;) {
    const std::optional<std::string> header = ReadAt(file, offset, kArHeader);
    const std::optional<std::uint64_t> size = header && header->substr(kArEndAt) == "`\n"
                                                  ? ParseUint(Trim(header->substr(kArSizeAt, kArSizeField)))
                                                  : std::nullopt;
    if (!size) {
      break;
    }
    const std::string field(Trim(header->substr(0, kArNameField)));
    const std::uint64_t data = offset + kArHeader;
    // the symbol tables and the long-name table are stored in thin archives too
    const bool special = field == "/" || field == "/SYM64/" || field == "//";
    if (field == "//") {
      long_names = ReadAt(file, data, *size).value_or("");
    } else if (!special && thin) {
      Merge(out, ThinMemberSonames(path, MemberName(field, long_names)));
    } else if (!special) {
      Merge(out, SonamesAt(FileReader(file), data, true));
    }
    const std::uint64_t stored = thin && !special ? 0 : *size;
    offset = data + stored + (stored % 2);  // members start on even offsets
  }
  return out;
}

}  // namespace

auto ParseDlopenNotes(std::string_view section) -> std::vector<std::string> {
  std::vector<std::string> out;
  for (std::uint64_t offset = 0; offset + kNoteHeader <= section.size();) {
    const std::uint32_t namesz = Load<std::uint32_t>(section, offset).value_or(0);
    const std::uint32_t descsz = Load<std::uint32_t>(section, offset + sizeof(std::uint32_t)).value_or(0);
    const std::uint32_t type = Load<std::uint32_t>(section, offset + (2 * sizeof(std::uint32_t))).value_or(0);
    const std::uint64_t name_at = offset + kNoteHeader;
    const std::uint64_t desc_at = name_at + Align(namesz);
    if (desc_at > section.size() || section.size() - desc_at < descsz) {
      break;
    }
    if (TrimNul(section.substr(name_at, namesz)) == kDlopenOwner && type == kDlopenNoteType) {
      AddJsonSonames(TrimNul(section.substr(desc_at, descsz)), out);
    }
    offset = desc_at + Align(descsz);
  }
  return out;
}

auto ElfDlopenSonames(std::string_view image) -> std::vector<std::string> {
  const auto read = [image](std::uint64_t offset, std::uint64_t size) -> std::optional<std::string> {
    if (offset > image.size() || image.size() - offset < size) {
      return std::nullopt;
    }
    return std::string(image.substr(offset, size));
  };
  return SonamesAt(read, 0, false);
}

auto LinkInputDlopenSonames(const fs::path& path) -> std::vector<std::string> {
  const UniqueFd file(::open(path.c_str(), O_RDONLY | O_CLOEXEC));  // NOLINT(cppcoreguidelines-pro-type-vararg)
  if (!file.valid()) {
    return {};
  }
  const std::optional<std::string> magic = ReadAt(file.get(), 0, kArMagic.size());
  if (magic == kArMagic || magic == kThinMagic) {
    return ArchiveSonames(file.get(), path, magic == kThinMagic);
  }
  return SonamesAt(FileReader(file.get()), 0, true);
}

}  // namespace jig
