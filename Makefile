# Sotto build orchestration.
# Rust toolchain is resolved from rustup's default toolchain.
CARGO ?= $(shell ls -d $(HOME)/.rustup/toolchains/stable-*/bin/cargo 2>/dev/null | head -1)
CMAKE ?= cmake

# Swift Testing ships in the Command Line Tools but isn't on the default search
# path there; add it when full Xcode isn't selected. Harmless no-op under Xcode.
XCODE_DIR := $(shell xcode-select -p)
CLT_FW := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
CLT_LIB := /Library/Developer/CommandLineTools/Library/Developer/usr/lib
ifneq (,$(findstring CommandLineTools,$(XCODE_DIR)))
SWIFT_TEST_FLAGS := -Xswiftc -F$(CLT_FW) -Xlinker -F$(CLT_FW) -Xlinker -rpath -Xlinker $(CLT_FW) -Xlinker -rpath -Xlinker $(CLT_LIB)
endif

.PHONY: all denoiser driver app test install uninstall clean

all: denoiser driver app

denoiser:
	cd denoiser && $(CARGO) build --release
	@test -f denoiser/target/release/libsotto_denoiser.a && echo "denoiser: built libsotto_denoiser.a"

driver:
	$(CMAKE) -S driver -B driver/build -DCMAKE_BUILD_TYPE=Release
	$(CMAKE) --build driver/build
	@test -d driver/build/SottoAudio.driver && echo "driver: built SottoAudio.driver"

app: denoiser
	cd app && swift build -c release
	@echo "app: built (bundle assembly in task 14)"

test:
	cd denoiser && $(CARGO) test --release
	cd app && swift test $(SWIFT_TEST_FLAGS)

install: driver
	bash scripts/install_driver.sh

uninstall:
	bash scripts/uninstall_driver.sh

clean:
	rm -rf denoiser/target driver/build app/.build
