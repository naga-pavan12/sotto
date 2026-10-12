use sotto_denoiser::*;

#[test]
fn hop_size_is_480() {
    unsafe {
        let d = sotto_denoiser_new();
        assert!(!d.is_null(), "model should load");
        assert_eq!(sotto_denoiser_hop_size(d), 480);
        sotto_denoiser_free(d);
    }
}

#[test]
fn process_reduces_noise_energy() {
    unsafe {
        let d = sotto_denoiser_new();
        assert!(!d.is_null());
        let hop = sotto_denoiser_hop_size(d) as usize;
        let mut rng = 12345u32;
        let mut inp = vec![0f32; hop];
        for x in inp.iter_mut() {
            rng = rng.wrapping_mul(1664525).wrapping_add(1013904223);
            *x = (rng >> 9) as f32 / (1u32 << 23) as f32 - 0.5;
        }
        let in_e: f32 = inp.iter().map(|v| v * v).sum();
        let mut out = vec![0f32; hop];
        let mut last = in_e;
        for _ in 0..20 {
            assert_eq!(sotto_denoiser_process(d, inp.as_ptr(), out.as_mut_ptr()), 0);
            last = out.iter().map(|v| v * v).sum::<f32>();
        }
        assert!(last < in_e * 0.6, "noise energy should drop: {last} vs {in_e}");
        sotto_denoiser_free(d);
    }
}
