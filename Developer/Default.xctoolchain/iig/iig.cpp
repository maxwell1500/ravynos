#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iostream>
#include <regex>
#include <set>
#include <sstream>
#include <string>
#include <vector>

namespace {

struct Options {
    std::string defPath;
    std::string headerPath;
    std::string implPath;
};

struct MethodInfo {
    std::string name;
    std::string returnType;
    std::string args;
    bool isStatic = false;
    bool isVirtual = false;
    bool isConst = false;
    bool isOverride = false;
    bool isLocal = false;
    bool isLocalOnly = false;
    bool isQueued = false;
    bool isKernelOnly = false;
    bool hasTypeAttribute = false;
    bool isPureVirtual = false;
};

static std::string
trim(const std::string &s)
{
    size_t start = 0;
    while (start < s.size() && (std::isspace(static_cast<unsigned char>(s[start])) != 0)) {
        start++;
    }
    size_t end = s.size();
    while (end > start && (std::isspace(static_cast<unsigned char>(s[end - 1])) != 0)) {
        end--;
    }
    return s.substr(start, end - start);
}

static std::string
stripComments(const std::string &src)
{
    std::string out;
    out.reserve(src.size());

    bool inBlock = false;
    bool inLine = false;

    for (size_t i = 0; i < src.size(); i++) {
        if (!inBlock && !inLine && i + 1 < src.size() && src[i] == '/' && src[i + 1] == '*') {
            inBlock = true;
            out.push_back(' ');
            i++;
            continue;
        }
        if (inBlock && i + 1 < src.size() && src[i] == '*' && src[i + 1] == '/') {
            inBlock = false;
            out.push_back(' ');
            i++;
            continue;
        }
        if (!inBlock && !inLine && i + 1 < src.size() && src[i] == '/' && src[i + 1] == '/') {
            inLine = true;
            out.push_back(' ');
            i++;
            continue;
        }
        if (inLine && (src[i] == '\n' || src[i] == '\r')) {
            inLine = false;
            out.push_back(src[i]);
            continue;
        }
        if (inBlock) {
            if (src[i] == '\n' || src[i] == '\r') {
                out.push_back(src[i]);
            } else {
                out.push_back(' ');
            }
        } else if (!inLine) {
            out.push_back(src[i]);
        }
    }

    return out;
}

static uint64_t
fnv1a64(const std::string &s)
{
    uint64_t hash = 14695981039346656037ULL;
    for (char c : s) {
        hash ^= static_cast<uint8_t>(c);
        hash *= 1099511628211ULL;
    }
    return hash;
}

static bool
findMainClass(const std::string &clean,
              std::string &className,
              std::string &superClassName,
              bool &isNative,
              size_t &bodyStart,
              size_t &bodyEnd)
{
    std::regex classRe(R"(\bclass\s+(?:(?:KERNEL|NATIVE)\s+)*([A-Za-z0-9_]+)\s*(?::\s*(public\s+)?([A-Za-z0-9_]+))?\s*\{)");
    auto words_begin = std::sregex_iterator(clean.begin(), clean.end(), classRe);
    auto words_end = std::sregex_iterator();

    std::smatch m;
    bool found = false;
    for (std::sregex_iterator i = words_begin; i != words_end; ++i) {
        std::smatch match = *i;
        std::string name = match[1].str();
        if (name == "OSMetaClassBase" && clean.find("class OSObject") != std::string::npos) {
            continue; // skip OSMetaClassBase declaration in OSObject.iig
        }
        m = match;
        found = true;
        break;
    }

    if (!found) {
        return false;
    }

    className = m[1].str();
    if (m[3].matched) {
        superClassName = m[3].str();
    } else {
        superClassName = "OSMetaClassBase";
    }

    size_t openBrace = m.position(0) + m.length(0) - 1;
    int depth = 1;
    size_t closeBrace = std::string::npos;
    for (size_t i = openBrace + 1; i < clean.size(); i++) {
        if (clean[i] == '{') {
            depth++;
        } else if (clean[i] == '}') {
            depth--;
            if (depth == 0) {
                closeBrace = i;
                break;
            }
        }
    }

    if (closeBrace == std::string::npos) {
        return false;
    }

    bodyStart = openBrace + 1;
    bodyEnd = closeBrace;

    std::string declPrefix = clean.substr(0, openBrace);
    isNative = (declPrefix.find("NATIVE") != std::string::npos);

    return true;
}

static std::vector<std::string>
splitArgs(const std::string &args)
{
    std::vector<std::string> res;
    std::string current;
    int templDepth = 0;
    int parenDepth = 0;

    for (char c : args) {
        if (c == '<') {
            templDepth++;
        } else if (c == '>') {
            templDepth = std::max(0, templDepth - 1);
        } else if (c == '(') {
            parenDepth++;
        } else if (c == ')') {
            parenDepth = std::max(0, parenDepth - 1);
        }

        if (c == ',' && templDepth == 0 && parenDepth == 0) {
            std::string t = trim(current);
            if (!t.empty() && t != "void") {
                res.push_back(t);
            }
            current.clear();
        } else {
            current.push_back(c);
        }
    }

    std::string t = trim(current);
    if (!t.empty() && t != "void") {
        res.push_back(t);
    }

    return res;
}

static std::string
extractParamName(const std::string &argDecl)
{
    std::string s = trim(argDecl);
    if (s.empty() || s == "void") {
        return "";
    }

    size_t eq = s.find('=');
    if (eq != std::string::npos) {
        s = trim(s.substr(0, eq));
    }

    // Strip array brackets: "const char reason[1024]" -> "const char reason"
    size_t lbracket = s.find('[');
    if (lbracket != std::string::npos) {
        s = trim(s.substr(0, lbracket));
    }

    while (!s.empty() && (s.back() == ')' || s.back() == ']' || s.back() == '*' || s.back() == '&')) {
        s.pop_back();
    }
    s = trim(s);

    size_t lastSpace = s.find_last_of(" \t*&");
    if (lastSpace == std::string::npos) {
        return "";
    }

    std::string name = trim(s.substr(lastSpace + 1));
    return name;
}

static std::string
sanitizeArgDecl(const std::string &argDecl)
{
    std::string s = trim(argDecl);
    static const std::vector<std::string> keywords = {
        "PORT", "PORTMAP", "KERNEL", "RPC", "LOCAL", "LOCALONLY", "QUEUED", "FINAL", "TARGET"
    };

    for (const auto &kw : keywords) {
        std::regex r(R"(\b)" + kw + R"(\b)");
        s = std::regex_replace(s, r, "");
    }

    // Remove TYPE(...) annotations like TYPE(IOUserClient::AsyncCompletion)
    std::regex typeRe(R"(TYPE\s*\([^)]*\))");
    s = std::regex_replace(s, typeRe, "");

    std::regex ws(R"(\s+)");
    s = std::regex_replace(s, ws, " ");
    return trim(s);
}

static std::vector<MethodInfo>
parseMethods(const std::string &body, const std::string &/*className*/)
{
    std::vector<MethodInfo> methods;
    std::istringstream stream(body);
    std::string line;
    std::string stmt;

    while (std::getline(stream, line)) {
        line = trim(line);
        if (line.empty() || line[0] == '#') {
            continue;
        }

        if (line == "public:" || line == "protected:" || line == "private:") {
            continue;
        }

        stmt += (stmt.empty() ? "" : " ") + line;
        if (stmt.back() == ';') {
            std::string s = stmt.substr(0, stmt.size() - 1);
            stmt.clear();

            bool isType = false;
            std::regex typeAttrRe(R"(__attribute__\s*\(\s*\(\s*annotate\s*\(\s*"type"\s*\)\s*\)\s*\))");
            if (std::regex_search(s, typeAttrRe)) {
                isType = true;
                s = std::regex_replace(s, typeAttrRe, "");
            }
            if (s.rfind("TYPE", 0) == 0 && s.size() > 4 && std::isspace(static_cast<unsigned char>(s[4]))) {
                isType = true;
                s = trim(s.substr(4));
            }

            size_t lparen = s.find('(');
            if (lparen == std::string::npos) {
                continue;
            }
            // Find matching ')' for the method's arg list (handle nested parens)
            int depth = 1;
            size_t rparen = std::string::npos;
            for (size_t i = lparen + 1; i < s.size(); i++) {
                if (s[i] == '(') depth++;
                else if (s[i] == ')') {
                    depth--;
                    if (depth == 0) { rparen = i; break; }
                }
            }
            if (rparen == std::string::npos) {
                continue;
            }

            std::string pre = trim(s.substr(0, lparen));
            std::string args = trim(s.substr(lparen + 1, rparen - lparen - 1));
            std::string post = trim(s.substr(rparen + 1));

            MethodInfo info;
            info.args = args;
            info.hasTypeAttribute = isType;

            if (pre.rfind("static ", 0) == 0) {
                info.isStatic = true;
                pre = trim(pre.substr(7));
            }
            if (pre.rfind("virtual ", 0) == 0) {
                info.isVirtual = true;
                pre = trim(pre.substr(8));
            }

            size_t namePos = pre.find_last_of(" \t*&");
            if (namePos == std::string::npos) {
                continue;
            }

            info.name = trim(pre.substr(namePos + 1));
            info.returnType = trim(pre.substr(0, namePos + 1));

            if (info.name.empty() || info.name[0] == '~') {
                continue;
            }

            info.isConst = (post.find("const") != std::string::npos);
            info.isOverride = (post.find("override") != std::string::npos);
            info.isLocal = (post.find("LOCAL") != std::string::npos || post.find("LOCALONLY") != std::string::npos);
            info.isLocalOnly = (post.find("LOCALONLY") != std::string::npos);
            info.isQueued = (post.find("QUEUED") != std::string::npos);
            info.isKernelOnly = (post.find("KERNEL") != std::string::npos);
            // Pure virtual: "= 0" appears after signature, possibly with spaces
            info.isPureVirtual = (post.find("= 0") != std::string::npos || post.find("=0") != std::string::npos);
            methods.push_back(info);
        }
    }

    return methods;
}

static std::vector<MethodInfo>
parseExtendsMethods(const std::string &clean, const std::string &className)
{
    std::vector<MethodInfo> extMethods;

    std::regex extRe(R"(\bclass\s+EXTENDS\s*\(\s*([A-Za-z0-9_]+)\s*\)\s*([A-Za-z0-9_]+)\s*\{)");
    auto words_begin = std::sregex_iterator(clean.begin(), clean.end(), extRe);
    auto words_end = std::sregex_iterator();

    for (std::sregex_iterator i = words_begin; i != words_end; ++i) {
        std::smatch m = *i;
        std::string targetClass = m[1].str();
        if (targetClass != className) {
            continue;
        }

        size_t openBrace = m.position(0) + m.length(0) - 1;
        int depth = 1;
        size_t closeBrace = std::string::npos;
        for (size_t k = openBrace + 1; k < clean.size(); k++) {
            if (clean[k] == '{') {
                depth++;
            } else if (clean[k] == '}') {
                depth--;
                if (depth == 0) {
                    closeBrace = k;
                    break;
                }
            }
        }
        if (closeBrace != std::string::npos) {
            std::string body = clean.substr(openBrace + 1, closeBrace - openBrace - 1);
            auto parsed = parseMethods(body, className);
            extMethods.insert(extMethods.end(), parsed.begin(), parsed.end());
        }
    }

    return extMethods;
}

static std::string
emitHeader(const std::string &input, const std::string &basename)
{
    std::string clean = stripComments(input);
    std::string className;
    std::string superClassName;
    bool isNative = false;
    size_t classStart = 0;
    size_t classEnd = 0;

    if (!findMainClass(clean, className, superClassName, isNative, classStart, classEnd)) {
        return "/* iig(iig-linux) generated from " + basename + " */\n";
    }

    std::string classText = clean.substr(classStart, classEnd - classStart);
    std::vector<MethodInfo> methods = parseMethods(classText, className);
    auto extMethods = parseExtendsMethods(clean, className);
    methods.insert(methods.end(), extMethods.begin(), extMethods.end());

    std::ostringstream out;
    out << "/* iig(iig-linux) generated from " << basename << " */\n\n"
        << "#ifndef _IOKIT_" << className << "_H\n"
        << "#define _IOKIT_" << className << "_H\n\n"
        << "#include <stdint.h>\n"
        << "#include <DriverKit/OSObject.h>\n"
        << "#include <DriverKit/IORPC.h>\n\n";

    if (superClassName != "OSMetaClassBase" && superClassName != "OSObject") {
        out << "#include <DriverKit/" << superClassName << ".h>\n\n";
    }

    out << "class " << className << ";\n\n";

    for (const auto &m : methods) {
        if (m.isLocalOnly || m.isKernelOnly) {
            continue;
        }
        std::string msgIdName = className + "_" + m.name + "_ID";
        uint64_t msgId = fnv1a64(className + "::" + m.name);
        out << "#define " << msgIdName << " 0x" << std::hex << msgId << "ULL\n";
    }
    out << std::dec << "\n";

    for (const auto &m : methods) {
        if (m.isLocalOnly || m.isKernelOnly) {
            continue;
        }
        std::string argsMacro = className + "_" + m.name + "_Args";
        out << "#define " << argsMacro << " \\\n";
        auto args = splitArgs(m.args);
        if (args.empty()) {
            out << "    /* no arguments */\n\n";
        } else {
            for (size_t i = 0; i < args.size(); i++) {
                out << "    " << sanitizeArgDecl(args[i]);
                if (i + 1 < args.size()) {
                    out << ", \\\n";
                } else {
                    out << "\n\n";
                }
            }
        }
    }

    out << "#define " << className << "_Methods \\\n";
    for (const auto &m : methods) {
        std::string retType = trim(m.returnType);
        if (retType.rfind("virtual ", 0) == 0) {
            retType = trim(retType.substr(8));
        }
        out << "    virtual " << retType << " \\\n"
            << "    " << m.name << "(\\\n";

        auto args = splitArgs(m.args);
        bool hasSupermethod = (!m.isLocalOnly && !m.isLocal && !m.isStatic);

        for (size_t i = 0; i < args.size(); i++) {
            out << "        " << sanitizeArgDecl(args[i]);
            if (i + 1 < args.size() || hasSupermethod) {
                out << ",\\\n";
            }
        }
        if (hasSupermethod) {
            out << "        OSDispatchMethod supermethod = NULL\\\n";
        }
        out << "    )" << (m.isConst ? " const" : "") << (m.isOverride ? " override" : "") << ";\\\n";
    }
    out << "\n";

    out << "#define " << className << "_KernelMethods \\\n";
    for (const auto &m : methods) {
        if (m.isLocalOnly) {
            continue;
        }
        std::string retType = trim(m.returnType);
        if (retType.rfind("virtual ", 0) == 0) {
            retType = trim(retType.substr(8));
        }

        if (m.isStatic) {
            out << "    static kern_return_t \\\n"
                << "    " << m.name << "_Call(\\\n"
                << "        IORPC rpc";
            auto args = splitArgs(m.args);
            if (!args.empty()) {
                out << ",\\\n";
                for (size_t i = 0; i < args.size(); i++) {
                    out << "        " << sanitizeArgDecl(args[i]);
                    if (i + 1 < args.size()) {
                        out << ",\\\n";
                    }
                }
            }
            out << ");\\\n";
        } else {
            out << "    " << retType << " \\\n"
                << "    " << m.name << "_Impl(\\\n";

            auto args = splitArgs(m.args);
            for (size_t i = 0; i < args.size(); i++) {
                out << "        " << sanitizeArgDecl(args[i]);
                if (i + 1 < args.size()) {
                    out << ",\\\n";
                }
            }
            out << ");\\\n";
        }
    }
    out << "\n";

    out << "class " << className;
    if (!superClassName.empty() && superClassName != "OSMetaClassBase") {
        out << " : public " << superClassName;
    } else {
        out << " : public OSMetaClassBase";
    }
    out << "\n{\n"
        << "#if KERNEL\n"
        << "    OSDeclareDefaultStructorsWithDispatch(" << className << ");\n"
        << "#endif /* KERNEL */\n\n"
        << "public:\n"
        << "    virtual kern_return_t Dispatch(const IORPC rpc) override;\n"
        << "    static kern_return_t _Dispatch(" << className << " * self, const IORPC rpc);\n\n"
        << "    " << className << "_Methods\n"
        << "    " << className << "_KernelMethods\n"
        << "};\n\n"
        << "#endif /* !_IOKIT_" << className << "_H */\n";

    return out.str();
}

static std::string
emitImpl(const std::string &input, const std::string &basename)
{
    std::string clean = stripComments(input);
    std::string className;
    std::string superClassName;
    bool isNative = false;
    size_t classStart = 0;
    size_t classEnd = 0;
    if (!findMainClass(clean, className, superClassName, isNative, classStart, classEnd)) {
        return "/* iig(iig-linux) generated from " + basename + " */\n";
    }

    // IOUserServer's vtable is defined in IOUserServer.cpp but its RPC methods still need stubs for linking.
    // Fall through to generate Dispatch + method stubs like other classes.


    std::string classText = clean.substr(classStart, classEnd - classStart);
    std::vector<MethodInfo> methods = parseMethods(classText, className);
    auto extMethods = parseExtendsMethods(clean, className);
    methods.insert(methods.end(), extMethods.begin(), extMethods.end());

    std::ostringstream out;
    out << "/* iig(iig-linux) generated from " << basename << " */\n\n"
        << "#undef  IIG_IMPLEMENTATION\n"
        << "#define IIG_IMPLEMENTATION  " << basename << "\n\n"
        << "#ifndef KERNEL\n"
        << "#define KERNEL 1\n"
        << "#endif\n\n"
        << "#include <libkern/c++/OSString.h>\n"
        << "#include <DriverKit/IOReturn.h>\n";

    if (className != "OSObject" && superClassName != "OSMetaClassBase" && superClassName != "OSObject") {
        out << "#include <DriverKit/" << superClassName << ".h>\n";
    }
    out << "#include <DriverKit/" << className << ".h>\n\n";

    out << "kern_return_t\n"
        << className << "::Dispatch(const IORPC rpc)\n"
        << "{\n"
        << "    return _Dispatch(this, rpc);\n"
        << "}\n\n";

    out << "kern_return_t\n"
        << className << "::_Dispatch(" << className << " * self, const IORPC rpc)\n"
        << "{\n"
        << "    (void)self;\n"
        << "    (void)rpc;\n"
        << "    return kIOReturnUnsupported;\n"
        << "}\n\n";

    if (className != "OSObject") {
        out << "kern_return_t\n"
            << className << "::MetaClass::Dispatch(const IORPC rpc)\n"
            << "{\n"
            << "    (void)rpc;\n"
            << "    return kIOReturnUnsupported;\n"
            << "}\n\n";
    }

    for (const auto &m : methods) {
        if (m.isPureVirtual) {
            continue;
        }
        if (m.name == "init" || m.name == "free") {
            continue;
        }
        if (m.isStatic) {
            continue;
        }

        std::string retType = trim(m.returnType);
        if (retType.rfind("virtual ", 0) == 0) {
            retType = trim(retType.substr(8));
        }

        auto args = splitArgs(m.args);
        bool hasSupermethod = (!m.isLocalOnly && !m.isLocal && !m.isStatic);
        std::string constSuffix = m.isConst ? " const" : "";

        out << retType << "\n"
            << className << "::" << m.name << "(\n";

        for (size_t i = 0; i < args.size(); i++) {
            out << "        " << sanitizeArgDecl(args[i]);
            if (i + 1 < args.size() || hasSupermethod) {
                out << ",\n";
            }
        }
        if (hasSupermethod) {
            out << "        OSDispatchMethod supermethod\n";
        }
        out << ")" << constSuffix << "\n"
            << "{\n";

        for (const auto &arg : args) {
            std::string pname = extractParamName(sanitizeArgDecl(arg));
            if (!pname.empty()) {
                out << "    (void)" << pname << ";\n";
            }
        }
        if (hasSupermethod) {
            out << "    (void)supermethod;\n";
        }

        if (retType == "void") {
            out << "}\n\n";
        } else if (retType == "bool") {
            out << "    return true;\n}\n\n";
        } else if (retType.find('*') != std::string::npos) {
            out << "    return NULL;\n}\n\n";
        } else {
            out << "    return kIOReturnUnsupported;\n}\n\n";
        }
    }

    return out.str();
}

static bool
parseArgs(int argc, const char **argv, Options &opts)
{
    bool sawDoubleDash = false;
    for (int i = 1; i < argc; i++) {
        std::string arg = argv[i];
        if (arg == "--") {
            sawDoubleDash = true;
            continue;
        }
        if (arg == "--def" && i + 1 < argc) {
            opts.defPath = argv[++i];
        } else if (arg == "--header" && i + 1 < argc) {
            opts.headerPath = argv[++i];
        } else if (arg == "--impl" && i + 1 < argc) {
            opts.implPath = argv[++i];
        } else if (arg.rfind("-I", 0) == 0) {
            // Include paths ignored for now
        } else if (arg.rfind("-D", 0) == 0) {
            // Macro defines ignored for now
        } else if (arg[0] != '-' && opts.defPath.empty()) {
            opts.defPath = arg;
        }
    }
    (void)sawDoubleDash;
    return !opts.defPath.empty();
}

static bool
readFile(const std::string &path, std::string &out)
{
    std::ifstream in(path, std::ios::binary);
    if (!in) {
        return false;
    }
    std::ostringstream ss;
    ss << in.rdbuf();
    out = ss.str();
    return true;
}

static bool
writeFile(const std::string &path, const std::string &content)
{
    std::ofstream out(path, std::ios::binary);
    if (!out) {
        return false;
    }
    out.write(content.data(), content.size());
    return out.good();
}

} // anonymous namespace

int
main(int argc, const char **argv)
{
    Options opts;
    if (!parseArgs(argc, argv, opts)) {
        std::cerr << "Usage: iig-linux --def <file.iig> [--header <file.h>] [--impl <file.iig.cpp>]\n";
        return 1;
    }

    std::string input;
    if (!readFile(opts.defPath, input)) {
        std::cerr << "iig-linux: failed to read: " << opts.defPath << "\n";
        return 1;
    }

    std::string basename = opts.defPath;
    size_t lastSlash = basename.find_last_of("/\\");
    if (lastSlash != std::string::npos) {
        basename = basename.substr(lastSlash + 1);
    }

    if (!opts.headerPath.empty()) {
        std::string header = emitHeader(input, basename);
        if (!writeFile(opts.headerPath, header)) {
            std::cerr << "iig-linux: failed to write header: " << opts.headerPath << "\n";
            return 1;
        }
    }

    if (!opts.implPath.empty()) {
        std::string impl = emitImpl(input, basename);
        if (!writeFile(opts.implPath, impl)) {
            std::cerr << "iig-linux: failed to write impl: " << opts.implPath << "\n";
            return 1;
        }
    }

    return 0;
}
