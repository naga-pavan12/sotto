//! Sotto noise-cancellation library: a C ABI around DeepFilterNet3.
//!
//! All entry points are panic-safe (a panic becomes an error return or a no-op)
//! and allocation-free after construction, so `sotto_denoiser_process` is safe to
//! call from a real-time audio thread.

use df::tract::{DfParams, DfTract, RuntimeParams};
use ndarray::{ArrayView2, ArrayViewMut2};
use std::panic::{catch_unwind, AssertUnwindSafe};

/// Opaque denoiser handle, created by [`sotto_denoiser_new`].
pub struct SottoDenoiser {
    model: DfTract,
    scratch_out: Vec<f32>,
}

/// Create a denoiser with the embedded DeepFilterNet3 model (mono, 48 kHz).
/// Returns NULL if the model fails to load.
#[no_mangle]
pub extern "C" fn sotto_denoiser_new() -> *mut SottoDenoiser {
    let built = catch_unwind(|| {
        let params = DfParams::default();
        let rp = RuntimeParams::default_with_ch(1);
        let model = DfTract::new(params, &rp).ok()?;
        let hop = model.hop_size;
        Some(Box::new(SottoDenoiser {
            model,
            scratch_out: vec![0.0; hop],
        }))
    });
    match built {
        Ok(Some(b)) => Box::into_raw(b),
        _ => std::ptr::null_mut(),
    }
}

/// Samples consumed and produced per `sotto_denoiser_process` call (480).
#[no_mangle]
pub extern "C" fn sotto_denoiser_hop_size(d: *const SottoDenoiser) -> u32 {
    if d.is_null() {
        return 0;
    }
    unsafe { (*d).model.hop_size as u32 }
}

/// Algorithmic look-ahead latency in samples.
#[no_mangle]
pub extern "C" fn sotto_denoiser_latency_samples(d: *const SottoDenoiser) -> u32 {
    if d.is_null() {
        return 0;
    }
    unsafe { ((*d).model.lookahead * (*d).model.hop_size) as u32 }
}

/// Set the attenuation limit in dB (0 = no reduction, 100 = unlimited).
#[no_mangle]
pub extern "C" fn sotto_denoiser_set_atten_lim_db(_d: *mut SottoDenoiser, _db: f32) {}

/// Enhance one hop of `hop_size` mono samples. Returns 0 on success, non-zero on error.
#[no_mangle]
pub extern "C" fn sotto_denoiser_process(
    _d: *mut SottoDenoiser,
    _input: *const f32,
    _output: *mut f32,
) -> i32 {
    -1
}

/// Reset internal model state (e.g. after a device change).
#[no_mangle]
pub extern "C" fn sotto_denoiser_reset(_d: *mut SottoDenoiser) {}

/// Free a denoiser created by [`sotto_denoiser_new`].
#[no_mangle]
pub extern "C" fn sotto_denoiser_free(d: *mut SottoDenoiser) {
    if !d.is_null() {
        unsafe { drop(Box::from_raw(d)) };
    }
}

// Silence unused-import warnings until process() is implemented in the next task.
#[allow(dead_code)]
fn _uses(_: Option<ArrayView2<f32>>, _: Option<ArrayViewMut2<f32>>, _: AssertUnwindSafe<()>) {}
