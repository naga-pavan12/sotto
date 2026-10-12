# Driver tests

- **auth** (`auth_test.cpp`): unit test for the bridge authorization helper. Runs
  in CI via CTest: `cd driver/build && ctest`.
- **loopback** (`loopback_test.swift`): end-to-end integration test. **Local only**
  — it needs the driver installed. Build and install first, then run:

  ```bash
  make driver && make install
  swift driver/tests/loopback_test.swift
  ```

  It writes a 1 kHz sine into Sotto Bridge, records Sotto Microphone, and checks
  the recording appears ~480 frames (one 10 ms frame) later at the same amplitude.
