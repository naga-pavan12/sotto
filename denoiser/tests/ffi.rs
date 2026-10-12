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
