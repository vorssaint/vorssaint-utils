// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

// Sanitized raw samples from Mac16,5, Apple M4 Max (10P + 4E), macOS
// 27.0.1 (26A434), source cb84ea01410710350dc373417715990351f79f00.
// Tpx/Tex names identify observed regions, not physical core identities.
enum M4MaxTemperatureFixtures {
    struct Sample {
        let cpu: [(key: String, value: Double)]
        let gpu: [Double]
        let hottest: Double
        let average: Double
        let defaultLevel: Int
        let balancedLevel: Int
    }

    // 2026-10-09T15:26:13.810Z, 20261009T152456Z-cpu-load.jsonl, sample 37.
    // CPU busy 97.02%; original selected CPU 68.765625 C.
    static let loaded = Sample(cpu: [
        ("Te05", 63.03101348876953),
        ("Te0S", 60.3482780456543),
        ("Tex0", 61.231014251708984),
        ("Tex1", 66.28125),
        ("Tex2", 58.74726486206055),
        ("Tex3", 63.140625),
        ("Tp01", 66.05305480957031),
        ("Tp05", 68.6349105834961),
        ("Tp06", 85.375),
        ("Tp09", 65.9620361328125),
        ("Tp0D", 67.66142272949219),
        ("Tp0M", 70.34375),
        ("Tp0W", 59.7010383605957),
        ("Tp0Y", 68.765625),
        ("Tp0b", 65.81719207763672),
        ("Tp0e", 63.0102424621582),
        ("Tpx0", 67.13432312011719),
        ("Tpx1", 85.375),
        ("Tpx2", 60.881446838378906),
        ("Tpx3", 67.984375),
        ("Tpx4", 66.8882064819336),
        ("Tpx5", 71),
        ("Tpx8", 66.83943939208984),
        ("Tpx9", 73.8125),
        ("TpxA", 61.263023376464844),
        ("TpxB", 68.125),
        ("TpxC", 67.28157043457031),
        ("TpxD", 74.171875),
    ],
        gpu: [59.92347717285156],
        hottest: 85.375, average: 67.50980710983276,
        defaultLevel: 100, balancedLevel: 75)

    // 2026-10-09T15:36:47.044Z, 20261009T153611Z-paired-read.jsonl, sample 16.
    // CPU busy 10.79%; original selected CPU 48.875000 C.
    static let parked = Sample(cpu: [
        ("Te05", 48.875),
        ("Te0S", 48.02815628051758),
        ("Tex0", 47.098304748535156),
        ("Tex1", 53.234375),
        ("Tex2", 46.41859436035156),
        ("Tex3", 51.296875),
        ("Tp01", 1.9000000953674316),
        ("Tp05", 1.5),
        ("Tp06", 0),
        ("Tp09", 1.9000000953674316),
        ("Tp0D", 1.5),
        ("Tp0M", 0),
        ("Tp0W", -4),
        ("Tp0Y", 0),
        ("Tp0b", 1.5),
        ("Tp0e", 1.9000000953674316),
        ("Tpx0", 0),
        ("Tpx1", 0),
        ("Tpx2", 0),
        ("Tpx3", 0),
        ("Tpx4", 0),
        ("Tpx5", 0),
        ("Tpx8", 0),
        ("Tpx9", 0),
        ("TpxA", 0),
        ("TpxB", 0),
        ("TpxC", 0),
        ("TpxD", 0),
    ],
        gpu: [47.90591812133789],
        hottest: 53.234375, average: 49.51203727722168,
        defaultLevel: 20, balancedLevel: 0)

    // 2026-10-09T15:40:22.145Z, 20261009T153928Z-idle.jsonl, sample 25.
    // CPU busy 6.02%; original selected CPU 45.211327 C.
    static let idle = Sample(cpu: [
        ("Te05", 45.211326599121094),
        ("Te0S", 44.17515563964844),
        ("Tex0", 43.42367935180664),
        ("Tex1", 48.765625),
        ("Tex2", 42.57632827758789),
        ("Tex3", 47.09375),
        ("Tp01", 40),
        ("Tp05", 40),
        ("Tp06", 40),
        ("Tp09", 40),
        ("Tp0D", 40),
        ("Tp0M", 40),
        ("Tp0W", 40),
        ("Tp0Y", 40),
        ("Tp0b", 40),
        ("Tp0e", 40),
        ("Tpx0", 40),
        ("Tpx1", 40),
        ("Tpx2", 40),
        ("Tpx3", 40),
        ("Tpx4", 40),
        ("Tpx5", 40),
        ("Tpx8", 43.6086311340332),
        ("Tpx9", 53.234375),
        ("TpxA", 43.55355453491211),
        ("TpxB", 50.28125),
        ("TpxC", 43.23165512084961),
        ("TpxD", 48.828125),
    ],
        gpu: [44.92494201660156],
        hottest: 53.234375, average: 44.03731083869934,
        defaultLevel: 20, balancedLevel: 0)
}
