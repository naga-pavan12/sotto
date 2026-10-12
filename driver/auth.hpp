#ifndef SOTTO_AUTH_HPP
#define SOTTO_AUTH_HPP

#include <string>
#include <sys/types.h>

namespace sotto {

// Pure decision helper (unit-testable, no system calls):
// If a signing Team ID was baked in at build time (SOTTO_TEAM_ID non-empty),
// authorize iff the client's Team ID matches it. Otherwise (unsigned local
// build) authorize iff the client's bundle ID matches SOTTO_BUNDLE_ID exactly.
bool is_authorized_client_for_test(const std::string& client_bundle_id,
                                   const std::string& client_team_id);

// Runtime check: resolve the client's Team ID from its PID via code signing,
// then delegate to the helper above.
bool is_authorized_client(pid_t pid, const std::string& client_bundle_id);

} // namespace sotto

#endif
