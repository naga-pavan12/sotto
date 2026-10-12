# Sotto build orchestration.
# Rust toolchain is resolved from rustup's default toolchain.
CARGO ?= $(shell ls -d $(HOME)/.rustup/toolchains/stable-*/bin/cargo 2>/dev/null | head -1)
CMAKE ?= cmake

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
	cd app && swift test

install: driver
	bash scripts/install_driver.sh

uninstall:
	bash scripts/uninstall_driver.sh

clean:
	rm -rf denoiser/target driver/build app/.build
