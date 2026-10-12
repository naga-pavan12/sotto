#include "../auth.hpp"
#include <cassert>
#include <cstdio>

// The two build modes have mutually exclusive expectations, so each mode's
// assertions are compiled only for that mode.
int main() {
    using sotto::is_authorized_client_for_test;
#ifdef SIGNED_BUILD_TEST
    // Signed build (SOTTO_TEAM_ID="ABCDE12345"): team id must match, bundle ignored.
    assert(is_authorized_client_for_test("anything.at.all", "ABCDE12345") == true);
    assert(is_authorized_client_for_test("io.github.sotto-audio.Sotto", "WRONG") == false);
    assert(is_authorized_client_for_test("io.github.sotto-audio.Sotto", "") == false);
#else
    // Unsigned build (SOTTO_TEAM_ID=""): exact bundle-ID match only.
    assert(is_authorized_client_for_test("io.github.sotto-audio.Sotto", "") == true);
    assert(is_authorized_client_for_test("com.evil.app", "") == false);
    assert(is_authorized_client_for_test("io.github.sotto-audio.Sotto", "ignored-team") == true);
#endif
    std::puts("auth_test PASS");
    return 0;
}
