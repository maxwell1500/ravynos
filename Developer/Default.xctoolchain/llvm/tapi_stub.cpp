#include <cstdint>
#include <tapi/APIVersion.h>
#include <tapi/PackedVersion32.h>
#include <tapi/LinkerInterfaceFile.h>
#include <tapi/Symbol.h>
namespace tapi { inline namespace v1 { struct LinkerInterfaceFile::Impl {}; } }
using namespace tapi::v1;
bool LinkerInterfaceFile::isSupported(const std::string&, const uint8_t*, size_t) noexcept { return false; }
bool LinkerInterfaceFile::shouldPreferTextBasedStubFile(const std::string&) noexcept { return false; }
bool LinkerInterfaceFile::areEquivalent(const std::string&, const std::string&) noexcept { return false; }
LinkerInterfaceFile* LinkerInterfaceFile::create(const std::string&, cpu_type_t, cpu_subtype_t, ParsingFlags, PackedVersion32, std::string &error) noexcept { error="tapi stub"; return nullptr; }
LinkerInterfaceFile* LinkerInterfaceFile::getInlinedFramework(const std::string&, cpu_type_t, cpu_subtype_t, ParsingFlags, PackedVersion32, std::string&) const noexcept { return nullptr; }
std::vector<std::string> LinkerInterfaceFile::getSupportedFileExtensions() noexcept { return {}; }
const std::vector<uint32_t>& LinkerInterfaceFile::getPlatformSet() const noexcept { static std::vector<uint32_t> v; return v; }
const std::vector<std::pair<uint32_t, PackedVersion32>>& LinkerInterfaceFile::getPlatformsAndMinDeployment() const noexcept { static std::vector<std::pair<uint32_t, PackedVersion32>> v; return v; }
const std::string& LinkerInterfaceFile::getInstallName() const noexcept { static std::string s; return s; }
bool LinkerInterfaceFile::isInstallNameVersionSpecific() const noexcept { return false; }
PackedVersion32 LinkerInterfaceFile::getCurrentVersion() const noexcept { return PackedVersion32(0); }
PackedVersion32 LinkerInterfaceFile::getCompatibilityVersion() const noexcept { return PackedVersion32(0); }
unsigned LinkerInterfaceFile::getSwiftVersion() const noexcept { return 0; }
bool LinkerInterfaceFile::hasTwoLevelNamespace() const noexcept { return false; }
bool LinkerInterfaceFile::isApplicationExtensionSafe() const noexcept { return false; }
bool LinkerInterfaceFile::isNotForDyldSharedCache() const noexcept { return false; }
bool LinkerInterfaceFile::hasAllowableClients() const noexcept { return false; }
bool LinkerInterfaceFile::hasReexportedLibraries() const noexcept { return false; }
bool LinkerInterfaceFile::hasWeakDefinedExports() const noexcept { return false; }
const std::string& LinkerInterfaceFile::getParentFrameworkName() const noexcept { static std::string s; return s; }
const std::vector<std::string>& LinkerInterfaceFile::allowableClients() const noexcept { static std::vector<std::string> v; return v; }
const std::vector<std::string>& LinkerInterfaceFile::reexportedLibraries() const noexcept { static std::vector<std::string> v; return v; }
const std::vector<std::string>& LinkerInterfaceFile::rPaths() const noexcept { static std::vector<std::string> v; return v; }
const std::vector<std::string>& LinkerInterfaceFile::relinkedLibraries() const noexcept { static std::vector<std::string> v; return v; }
const std::vector<std::string>& LinkerInterfaceFile::ignoreExports() const noexcept { static std::vector<std::string> v; return v; }
const std::vector<Symbol>& LinkerInterfaceFile::exports() const noexcept { static std::vector<Symbol> v; return v; }
const std::vector<Symbol>& LinkerInterfaceFile::undefineds() const noexcept { static std::vector<Symbol> v; return v; }
const std::vector<std::string>& LinkerInterfaceFile::inlinedFrameworkNames() const noexcept { static std::vector<std::string> v; return v; }
LinkerInterfaceFile::LinkerInterfaceFile() noexcept = default;
LinkerInterfaceFile::~LinkerInterfaceFile() noexcept = default;
LinkerInterfaceFile::LinkerInterfaceFile(LinkerInterfaceFile&&) noexcept = default;
LinkerInterfaceFile& LinkerInterfaceFile::operator=(LinkerInterfaceFile&&) noexcept = default;
namespace tapi {
bool APIVersion::isAtLeast(unsigned, unsigned, unsigned) noexcept { return false; }
unsigned APIVersion::getMajor() noexcept { return 0; }
unsigned APIVersion::getMinor() noexcept { return 0; }
class Version { public: std::string getAsString() const; std::string getFullVersionAsString() const; std::string getAsString(); std::string getFullVersionAsString(); };
std::string Version::getAsString() const { return ""; }
std::string Version::getFullVersionAsString() const { return ""; }
std::string Version::getAsString() { return ""; }
std::string Version::getFullVersionAsString() { return ""; }
}
extern "C" void tapi_stub() {}
