#include "auth.hpp"

#include <Security/Security.h>
#include <CoreFoundation/CoreFoundation.h>

#ifndef SOTTO_TEAM_ID
#define SOTTO_TEAM_ID ""
#endif
#ifndef SOTTO_BUNDLE_ID
#define SOTTO_BUNDLE_ID "io.github.sotto-audio.Sotto"
#endif

namespace sotto {

bool is_authorized_client_for_test(const std::string& client_bundle_id,
                                   const std::string& client_team_id) {
    const std::string build_team = SOTTO_TEAM_ID;
    if (!build_team.empty()) {
        return client_team_id == build_team;
    }
    return client_bundle_id == std::string(SOTTO_BUNDLE_ID);
}

// Resolve the client's signing Team ID from its PID. Returns empty on failure
// (unsigned/ad-hoc), which makes the helper fall back to the bundle-ID path.
static std::string team_id_for_pid(pid_t pid) {
    std::string result;
    CFNumberRef pidNum = CFNumberCreate(nullptr, kCFNumberIntType, &pid);
    if (!pidNum) return result;
    const void* keys[] = { kSecGuestAttributePid };
    const void* vals[] = { pidNum };
    CFDictionaryRef attrs = CFDictionaryCreate(nullptr, keys, vals, 1,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFRelease(pidNum);
    if (!attrs) return result;

    SecCodeRef code = nullptr;
    OSStatus st = SecCodeCopyGuestWithAttributes(nullptr, attrs, kSecCSDefaultFlags, &code);
    CFRelease(attrs);
    if (st != errSecSuccess || !code) return result;

    CFDictionaryRef info = nullptr;
    st = SecCodeCopySigningInformation(code, kSecCSSigningInformation, &info);
    if (st == errSecSuccess && info) {
        CFStringRef team = (CFStringRef)CFDictionaryGetValue(info, kSecCodeInfoTeamIdentifier);
        if (team) {
            char buf[256] = {0};
            if (CFStringGetCString(team, buf, sizeof(buf), kCFStringEncodingUTF8)) {
                result = buf;
            }
        }
        CFRelease(info);
    }
    CFRelease(code);
    return result;
}

bool is_authorized_client(pid_t pid, const std::string& client_bundle_id) {
    return is_authorized_client_for_test(client_bundle_id, team_id_for_pid(pid));
}

} // namespace sotto
