//! Sotto noise-cancellation library: a C ABI around DeepFilterNet3.
//!
//! All entry points are panic-safe (a panic becomes an error return or a no-op)
//! and allocation-free after construction, so [`sotto_denoiser_process`] is safe to
//! call from a real-time audio thread. Functions that take a handle or buffer
//! pointer are `unsafe`: the caller must pass either null or a valid pointer, and
//! the input/output buffers must each hold at least `hop_size` floats.

use df::tract::{DfParams, DfTract, RuntimeParams};
use ndarray::{ArrayView2, ArrayViewMut2};
use std::panic::{catch_unwind, AssertUnwindSafe};

/// Opaque denoiser handle, created by [`sotto_denoiser_new`].
pub struct SottoDenoiser {
    model: DfTract,
    /// Pristine clone taken at construction; cloned back to implement reset().
    pristine: DfTract,
    scratch_out: Vec<f32>,
}

/// Create a denoiser with the embedded DeepFilterNet3 model (mono, 48 kHz).
/// Returns NULL if the model fails to load.
#[no_mangle]
pub extern "C" fn sotto_denoiser_new() -> *mut SottoDenoiser {
    let built = catch_unwind(|| {
        let params = DfParams::default();
        // Use DeepFilterNet's recommended inference thresholds (the deep-filter CLI
        // defaults) rather than the library's conservative default_with_ch values
        // (-10/30/20). The wider DF/ERB local-SNR range runs the deep-filter decoder
        // on more frames, matching the reference offline quality. min_db_thresh -15,
        // max_db_erb_thresh 35, max_db_df_thresh 35.
        let rp = RuntimeParams::default_with_ch(1).with_thresholds(-15.0, 35.0, 35.0);
        let model = DfTract::new(params, &rp).ok()?;
        let hop = model.hop_size;
        let pristine = model.clone();
        Some(Box::new(SottoDenoiser {
            model,
            pristine,
            scratch_out: vec![0.0; hop],
        }))
    });
    match built {
        Ok(Some(b)) => Box::into_raw(b),
        _ => std::ptr::null_mut(),
    }
}

/// Samples consumed and produced per [`sotto_denoiser_process`] call (480).
///
/// # Safety
/// `d` must be null or a valid handle from [`sotto_denoiser_new`].
#[no_mangle]
pub unsafe extern "C" fn sotto_denoiser_hop_size(d: *const SottoDenoiser) -> u32 {
    if d.is_null() {
        return 0;
    }
    (*d).model.hop_size as u32
}

/// Algorithmic look-ahead latency in samples.
///
/// # Safety
/// `d` must be null or a valid handle from [`sotto_denoiser_new`].
#[no_mangle]
pub unsafe extern "C" fn sotto_denoiser_latency_samples(d: *const SottoDenoiser) -> u32 {
    if d.is_null() {
        return 0;
    }
    ((*d).model.lookahead * (*d).model.hop_size) as u32
}

/// Set the attenuation limit in dB. 0 means no reduction (passthrough); values at
/// or above 100 mean unlimited reduction. Sotto maps `strength` (0..100) to
/// `strength * 0.4` dB, with strength 100 passed as 100.0 for full reduction.
///
/// # Safety
/// `d` must be null or a valid handle from [`sotto_denoiser_new`].
#[no_mangle]
pub unsafe extern "C" fn sotto_denoiser_set_atten_lim_db(d: *mut SottoDenoiser, db: f32) {
    if d.is_null() {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| {
        (*d).model.set_atten_lim(db);
    }));
}

/// Enhance one hop of `hop_size` mono samples.
///
/// Returns 0 on success, -2 for a null argument, -1 if the model errors (in which
/// case `output` is left untouched and the caller should pass the input through).
///
/// # Safety
/// `d` must be null or a valid handle; `input` and `output` must each point to at
/// least `hop_size` writable/readable floats.
#[no_mangle]
pub unsafe extern "C" fn sotto_denoiser_process(
    d: *mut SottoDenoiser,
    input: *const f32,
    output: *mut f32,
) -> i32 {
    if d.is_null() || input.is_null() || output.is_null() {
        return -2;
    }
    let result = catch_unwind(AssertUnwindSafe(|| {
        let this = &mut *d;
        let hop = this.model.hop_size;
        let inp = std::slice::from_raw_parts(input, hop);
        let noisy = ArrayView2::from_shape((1, hop), inp).expect("shape");
        let enh = ArrayViewMut2::from_shape((1, hop), &mut this.scratch_out).expect("shape");
        this.model.process(noisy, enh).map(|_| ())
    }));
    match result {
        Ok(Ok(())) => {
            let this = &*d;
            std::ptr::copy_nonoverlapping(this.scratch_out.as_ptr(), output, this.model.hop_size);
            0
        }
        _ => -1,
    }
}

/// Reset internal model state (e.g. after a device change).
///
/// # Safety
/// `d` must be null or a valid handle from [`sotto_denoiser_new`].
#[no_mangle]
pub unsafe extern "C" fn sotto_denoiser_reset(d: *mut SottoDenoiser) {
    if d.is_null() {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| {
        let this = &mut *d;
        this.model = this.pristine.clone();
    }));
}

/// Free a denoiser created by [`sotto_denoiser_new`].
///
/// # Safety
/// `d` must be null or a valid handle from [`sotto_denoiser_new`], not freed before.
#[no_mangle]
pub unsafe extern "C" fn sotto_denoiser_free(d: *mut SottoDenoiser) {
    if !d.is_null() {
        drop(Box::from_raw(d));
    }
}
