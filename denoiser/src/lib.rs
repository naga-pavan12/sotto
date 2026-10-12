//! Sotto noise-cancellation library: a C ABI around DeepFilterNet3.

/// Opaque denoiser handle.
pub struct SottoDenoiser {
    _private: [u8; 0],
}

#[no_mangle]
pub extern "C" fn sotto_denoiser_new() -> *mut SottoDenoiser {
    std::ptr::null_mut()
}

#[no_mangle]
pub extern "C" fn sotto_denoiser_hop_size(_d: *const SottoDenoiser) -> u32 {
    0
}

#[no_mangle]
pub extern "C" fn sotto_denoiser_latency_samples(_d: *const SottoDenoiser) -> u32 {
    0
}

#[no_mangle]
pub extern "C" fn sotto_denoiser_set_atten_lim_db(_d: *mut SottoDenoiser, _db: f32) {}

#[no_mangle]
pub extern "C" fn sotto_denoiser_process(_d: *mut SottoDenoiser, _i: *const f32, _o: *mut f32) -> i32 {
    -1
}

#[no_mangle]
pub extern "C" fn sotto_denoiser_reset(_d: *mut SottoDenoiser) {}

#[no_mangle]
pub extern "C" fn sotto_denoiser_free(_d: *mut SottoDenoiser) {}
