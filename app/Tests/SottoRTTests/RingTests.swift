import Testing
import SottoRT

@Test func writeThenReadRoundTrips() {
    let r = spsc_create(8)
    #expect(r != nil)
    var inp: [Float] = [1, 2, 3, 4, 5]
    #expect(spsc_write(r, &inp, 5) == 5)
    #expect(spsc_fill(r) == 5)
    var out = [Float](repeating: 0, count: 5)
    #expect(spsc_read(r, &out, 5) == 5)
    #expect(out == inp)
    spsc_destroy(r)
}

@Test func writeStopsWhenFull() {
    let r = spsc_create(4)
    var inp: [Float] = [1, 2, 3, 4, 5, 6]
    #expect(spsc_write(r, &inp, 6) <= 4)
    spsc_destroy(r)
}
