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

fn white_noise(n: usize) -> Vec<f32> {
    let mut rng = 999u32;
    (0..n)
        .map(|_| {
            rng = rng.wrapping_mul(1664525).wrapping_add(1013904223);
            (rng >> 9) as f32 / (1u32 << 23) as f32 - 0.5
        })
        .collect()
}

#[test]
fn null_inputs_return_error() {
    unsafe {
        assert_eq!(
            sotto_denoiser_process(std::ptr::null_mut(), std::ptr::null(), std::ptr::null_mut()),
            -2
        );
    }
}

#[test]
fn atten_lim_zero_disables_reduction() {
    unsafe {
        let hop = 480usize;
        let inp = white_noise(hop);
        let in_e: f32 = inp.iter().map(|v| v * v).sum();
        let mut out = vec![0f32; hop];

        // atten limit 0 dB => passthrough (energy preserved)
        let d = sotto_denoiser_new();
        sotto_denoiser_set_atten_lim_db(d, 0.0);
        let mut e0 = in_e;
        for _ in 0..20 {
            assert_eq!(sotto_denoiser_process(d, inp.as_ptr(), out.as_mut_ptr()), 0);
            e0 = out.iter().map(|v| v * v).sum::<f32>();
        }
        assert!(e0 > in_e * 0.8, "0 dB should preserve energy: {e0} vs {in_e}");

        // reset, then full reduction => energy drops
        sotto_denoiser_reset(d);
        sotto_denoiser_set_atten_lim_db(d, 100.0);
        let mut e1 = in_e;
        for _ in 0..20 {
            assert_eq!(sotto_denoiser_process(d, inp.as_ptr(), out.as_mut_ptr()), 0);
            e1 = out.iter().map(|v| v * v).sum::<f32>();
        }
        assert!(e1 < in_e * 0.6, "100 dB should reduce energy: {e1} vs {in_e}");
        sotto_denoiser_free(d);
    }
}
