//
//  FrequencyWeightingTests.swift
//  DynaVibeTests
//
//  Created by AI Assistant on 2024-10-28.
//  Copyright © 2024 DynaVibe Project. All rights reserved.
//

import XCTest
@testable import DynaVibe

class FrequencyWeightingTests: XCTestCase {

    let accuracy = 0.001 // Default accuracy for floating-point comparisons

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    // MARK: - Tests for getFrequencyWeightingFactor

    func testWg_WeightingFactors() {
        // Wg: Defined by user formulas:
        // 0.0 for f < 1.0 Hz
        // 0.5 * sqrt(f) for 1.0 Hz <= f < 4.0 Hz
        // 1.0 for 4.0 Hz <= f <= 8.0 Hz
        // 8.0 / f for f > 8.0 Hz

        // Test points for Wg
        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 0.0, type: .wg), 0.0, accuracy: accuracy, "Wg at 0.0 Hz (Boundary condition)")
        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 0.5, type: .wg), 0.0, accuracy: accuracy, "Wg at 0.5 Hz (Below 1Hz)")
        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 0.99, type: .wg), 0.0, accuracy: accuracy, "Wg at 0.99 Hz (Below 1Hz)")

        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 1.0, type: .wg), 0.5 * sqrt(1.0), accuracy: accuracy, "Wg at 1.0 Hz (Start of 0.5*sqrt(f) segment)")
        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 2.0, type: .wg), 0.5 * sqrt(2.0), accuracy: accuracy, "Wg at 2.0 Hz")
        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 3.99, type: .wg), 0.5 * sqrt(3.99), accuracy: accuracy, "Wg at 3.99 Hz (End of 0.5*sqrt(f) segment)")

        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 4.0, type: .wg), 1.0, accuracy: accuracy, "Wg at 4.0 Hz (Start of 1.0 segment)")
        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 6.0, type: .wg), 1.0, accuracy: accuracy, "Wg at 6.0 Hz")
        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 8.0, type: .wg), 1.0, accuracy: accuracy, "Wg at 8.0 Hz (End of 1.0 segment)")

        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 8.01, type: .wg), 8.0 / 8.01, accuracy: accuracy, "Wg at 8.01 Hz (Start of 8/f segment)")
        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 16.0, type: .wg), 8.0 / 16.0, accuracy: accuracy, "Wg at 16.0 Hz")
        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 80.0, type: .wg), 8.0 / 80.0, accuracy: accuracy, "Wg at 80.0 Hz (User context upper limit)")
        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 100.0, type: .wg), 8.0 / 100.0, accuracy: accuracy, "Wg at 100.0 Hz (Extrapolating 8/f)")
    }

    func testWb_WeightingFactors() {
        // Wb: Defined by user formulas:
        // 0.0 for f < 1.0 Hz
        // 0.4 * sqrt(f) for 1.0 Hz <= f < 2.0 Hz
        // f / 5.0 for 2.0 Hz <= f < 5.0 Hz
        // 1.0 for 5.0 Hz <= f <= 16.0 Hz
        // 16.0 / f for f > 16.0 Hz

        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 0.0, type: .wb), 0.0, accuracy: accuracy, "Wb at 0.0 Hz (Boundary)")
        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 0.5, type: .wb), 0.0, accuracy: accuracy, "Wb at 0.5 Hz (Below 1Hz)")
        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 0.99, type: .wb), 0.0, accuracy: accuracy, "Wb at 0.99 Hz (Below 1Hz)")

        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 1.0, type: .wb), 0.4 * sqrt(1.0), accuracy: accuracy, "Wb at 1.0 Hz")
        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 1.5, type: .wb), 0.4 * sqrt(1.5), accuracy: accuracy, "Wb at 1.5 Hz")
        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 1.99, type: .wb), 0.4 * sqrt(1.99), accuracy: accuracy, "Wb at 1.99 Hz")

        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 2.0, type: .wb), 2.0 / 5.0, accuracy: accuracy, "Wb at 2.0 Hz")
        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 3.5, type: .wb), 3.5 / 5.0, accuracy: accuracy, "Wb at 3.5 Hz")
        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 4.99, type: .wb), 4.99 / 5.0, accuracy: accuracy, "Wb at 4.99 Hz")

        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 5.0, type: .wb), 1.0, accuracy: accuracy, "Wb at 5.0 Hz")
        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 10.0, type: .wb), 1.0, accuracy: accuracy, "Wb at 10.0 Hz")
        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 16.0, type: .wb), 1.0, accuracy: accuracy, "Wb at 16.0 Hz")

        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 16.01, type: .wb), 16.0 / 16.01, accuracy: accuracy, "Wb at 16.01 Hz")
        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 100.0, type: .wb), 16.0 / 100.0, accuracy: accuracy, "Wb at 100.0 Hz (User context upper limit)")
        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 200.0, type: .wb), 16.0 / 200.0, accuracy: accuracy, "Wb at 200.0 Hz (Extrapolating 16/f)")
    }

    func testWd_WeightingFactors() {
        // Wd: Defined by user formulas:
        // 0.0 for f < 1.0 Hz
        // 1.0 for 1.0 Hz <= f < 2.0 Hz
        // 2.0 / f for f >= 2.0 Hz

        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 0.0, type: .wd), 0.0, accuracy: accuracy, "Wd at 0.0 Hz (Boundary)")
        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 0.5, type: .wd), 0.0, accuracy: accuracy, "Wd at 0.5 Hz (Below 1Hz)")
        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 0.99, type: .wd), 0.0, accuracy: accuracy, "Wd at 0.99 Hz (Below 1Hz)")

        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 1.0, type: .wd), 1.0, accuracy: accuracy, "Wd at 1.0 Hz")
        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 1.5, type: .wd), 1.0, accuracy: accuracy, "Wd at 1.5 Hz")
        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 1.99, type: .wd), 1.0, accuracy: accuracy, "Wd at 1.99 Hz")

        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 2.0, type: .wd), 2.0 / 2.0, accuracy: accuracy, "Wd at 2.0 Hz")
        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 10.0, type: .wd), 2.0 / 10.0, accuracy: accuracy, "Wd at 10.0 Hz")
        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 100.0, type: .wd), 2.0 / 100.0, accuracy: accuracy, "Wd at 100.0 Hz (User context upper limit)")
        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 200.0, type: .wd), 2.0 / 200.0, accuracy: accuracy, "Wd at 200.0 Hz (Extrapolating 2/f)")
    }

    func testNone_WeightingFactor() {
        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 0.5, type: .none), 1.0, accuracy: accuracy, "None at 0.5 Hz")
        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 10.0, type: .none), 1.0, accuracy: accuracy, "None at 10.0 Hz")
        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 100.0, type: .none), 1.0, accuracy: accuracy, "None at 100.0 Hz")
        // Test with frequency 0, though getFrequencyWeightingFactor guards against f<=0 for typed weightings,
        // .none should still yield 1.0 due to the guard `guard type != .none else { return 1.0 }`
        // However, the top guard `guard frequency > 0 else { return 1.0 }` takes precedence.
        XCTAssertEqual(FrequencyWeighting.getFrequencyWeightingFactor(frequency: 0.0, type: .none), 1.0, accuracy: accuracy, "None at 0.0 Hz")

    }

    // MARK: - Placeholder Tests for Time-Domain Filters

    func testWg_FilterResponse_Placeholder() {
        XCTFail("Time-domain filter Wg tests are not yet implemented. Requires filter coefficients and implementation in FrequencyWeightingFilter.")
        // Test Plan:
        // 1. Define a sample rate (e.g., 512 Hz).
        // 2. Generate input signals:
        //    - Sine wave at 0.2 Hz (expected high gain by Wg)
        //    - Sine wave at 1 Hz (expected moderate gain by Wg)
        //    - Sine wave at 5 Hz (expected low gain by Wg)
        // 3. Apply the (future) FrequencyWeightingFilter.applyFilter(data:sampleRate:type:.wg) to these signals.
        // 4. Assertions:
        //    - Compare RMS of output signal to RMS of input signal. The ratio squared should approximate
        //      the Wg factor squared at that frequency (or use magnitude directly if comparing amplitudes).
        //    - OR: Perform FFT on output signal and check magnitude at the input frequency, comparing to input magnitude * Wg_factor.
        // Note: This requires FrequencyWeightingFilter to be implemented with actual filter coefficients derived from standards.
    }

    func testWb_FilterResponse_Placeholder() {
        XCTFail("Time-domain filter Wb tests are not yet implemented. Requires filter coefficients and implementation in FrequencyWeightingFilter.")
        // Test Plan: (Similar to Wg)
        // 1. Define sample rate.
        // 2. Generate input signals at key Wb frequencies (e.g., 1.5 Hz, 10 Hz, 50 Hz).
        // 3. Apply future Wb time-domain filter.
        // 4. Assert output based on expected Wb attenuation/gain at those frequencies.
    }

    func testWd_FilterResponse_Placeholder() {
        XCTFail("Time-domain filter Wd tests are not yet implemented. Requires filter coefficients and implementation in FrequencyWeightingFilter.")
        // Test Plan: (Similar to Wg)
        // 1. Define sample rate.
        // 2. Generate input signals at key Wd frequencies (e.g., 1.5 Hz, 10 Hz, 50 Hz).
        // 3. Apply future Wd time-domain filter.
        // 4. Assert output based on expected Wd attenuation/gain at those frequencies.
    }

    // MARK: - Tests for applyWeightingViaFFT (from FrequencyWeightingFilter class)

    func testApplyWeightingViaFFT_NoneWeighting() {
        let timeSeries: [Double] = [1.0, 2.0, 3.0, 4.0, 5.0]
        let sampleRate = 100.0
        let output = FrequencyWeightingFilter.applyWeightingViaFFT(
            timeSeries: timeSeries,
            sampleRate: sampleRate,
            weightingType: .none
        )
        XCTAssertEqual(output, timeSeries, accuracy: accuracy, "Output should be same as input for .none weighting.")
    }

    func testApplyWeightingViaFFT_EmptyInput() {
        let output = FrequencyWeightingFilter.applyWeightingViaFFT(
            timeSeries: [],
            sampleRate: 100.0,
            weightingType: .wg
        )
        XCTAssertTrue(output.isEmpty, "Output should be empty for empty input.")
    }

    func testApplyWeightingViaFFT_InvalidSampleRate() {
        let timeSeries: [Double] = [1.0, 2.0, 3.0, 4.0, 5.0]
        // Test with sampleRate = 0
        var output = FrequencyWeightingFilter.applyWeightingViaFFT(
            timeSeries: timeSeries,
            sampleRate: 0.0,
            weightingType: .wg
        )
        XCTAssertEqual(output, timeSeries, "Output should be original timeSeries for sampleRate = 0 (due to FFT setup guard).")

        // Test with negative sampleRate (though guard might catch it earlier)
        output = FrequencyWeightingFilter.applyWeightingViaFFT(
            timeSeries: timeSeries,
            sampleRate: -100.0,
            weightingType: .wg
        )
         XCTAssertEqual(output, timeSeries, "Output should be original timeSeries for negative sampleRate (due to FFT setup guard).")
    }

    func testApplyWeightingViaFFT_BasicSignalIntegrity() {
        // Create a simple sine wave: sin(2*pi*f*t)
        // For this test, we mostly care that the FFT-IFFT process doesn't mangle the signal too badly with .none
        // or a near-unity weighting. We won't check exact weighting application here as that depends on getFrequencyWeightingFactor.
        let n = 256 // Power of 2 for FFT convenience
        let sampleRate = Double(n) // Results in 1 Hz frequency resolution
        let frequencyOfSine = 5.0 // 5 Hz sine wave
        var timeSeries: [Double] = []
        for i in 0..<n {
            let time = Double(i) / sampleRate
            timeSeries.append(sin(2.0 * .pi * frequencyOfSine * time))
        }

        let output = FrequencyWeightingFilter.applyWeightingViaFFT(
            timeSeries: timeSeries,
            sampleRate: sampleRate,
            weightingType: .none // Using .none, so output should be very close to input
        )

        XCTAssertEqual(output.count, timeSeries.count, "Output count should match input count.")
        for i in 0..<timeSeries.count {
            XCTAssertEqual(output[i], timeSeries[i], accuracy: accuracy, "Output sample \(i) should match input for .none weighting.")
        }
    }

    // MARK: - Tests for calculateVDV (global function)

    func testCalculateVDV_ConstantSignal() {
        let series: [Double] = [1.0, 1.0, 1.0, 1.0]
        let sampleRate = 1.0
        // Expected VDV: ( (1^4 + 1^4 + 1^4 + 1^4) * (1/1) )^(1/4) = (4)^(1/4)
        let expectedVDV = pow(4.0, 0.25) // approx 1.41421356
        XCTAssertEqual(DynaVibe.calculateVDV(weightedTimeSeries: series, sampleRate: sampleRate), expectedVDV, accuracy: accuracy)
    }

    func testCalculateVDV_SimpleVaryingSignal() {
        let series: [Double] = [1.0, 2.0]
        let sampleRate = 1.0
        // Expected VDV: ( (1^4 + 2^4) * (1/1) )^(1/4) = (1 + 16)^(1/4) = (17)^(1/4)
        let expectedVDV = pow(17.0, 0.25) // approx 2.03054318
        XCTAssertEqual(DynaVibe.calculateVDV(weightedTimeSeries: series, sampleRate: sampleRate), expectedVDV, accuracy: accuracy)
    }

    func testCalculateVDV_EmptyInput() {
        XCTAssertEqual(DynaVibe.calculateVDV(weightedTimeSeries: [], sampleRate: 1.0), 0.0, accuracy: accuracy)
    }

    func testCalculateVDV_ZeroSampleRate() {
        XCTAssertEqual(DynaVibe.calculateVDV(weightedTimeSeries: [1.0, 1.0], sampleRate: 0.0), 0.0, accuracy: accuracy)
    }

    func testCalculateVDV_NonUnitSampleRate() {
        let series: [Double] = [1.0, 2.0]
        let sampleRate = 2.0 // dt = 0.5
        // Expected VDV: ( (1^4 + 2^4) * (1/2) )^(1/4) = ( (1 + 16) * 0.5 )^(1/4) = (8.5)^(1/4)
        let expectedVDV = pow(8.5, 0.25) // approx 1.70735
        XCTAssertEqual(DynaVibe.calculateVDV(weightedTimeSeries: series, sampleRate: sampleRate), expectedVDV, accuracy: accuracy)
    }

    // MARK: - Tests for calculateMTVV (global function)

    func testCalculateMTVV_EmptyInput() {
        XCTAssertEqual(DynaVibe.calculateMTVV(weightedTimeSeries: [], sampleRate: 100.0, windowSeconds: 1.0), 0.0, accuracy: accuracy)
    }

    func testCalculateMTVV_SignalShorterThanWindow() {
        let series: [Double] = [1.0, 2.0, 3.0] // 0.3s signal at 10Hz SR
        XCTAssertEqual(DynaVibe.calculateMTVV(weightedTimeSeries: series, sampleRate: 10.0, windowSeconds: 1.0), 0.0, accuracy: accuracy, "Signal shorter than window should return 0.0")
    }

    func testCalculateMTVV_ConstantSignalLongerThanWindow() {
        let series: [Double] = [2.0, 2.0, 2.0, 2.0, 2.0]
        let sampleRate = 1.0
        let windowSeconds = 1.0 // windowSamples = 1
        // Window 1: [2.0], RMS = 2.0
        // Window 2: [2.0], RMS = 2.0
        // ...
        // Max RMS = 2.0
        XCTAssertEqual(DynaVibe.calculateMTVV(weightedTimeSeries: series, sampleRate: sampleRate, windowSeconds: windowSeconds), 2.0, accuracy: accuracy)
    }

    func testCalculateMTVV_ConstantSignalWindowEqualsLength() {
        let series: [Double] = [2.0, 2.0]
        let sampleRate = 1.0
        let windowSeconds = 2.0 // windowSamples = 2
        // Window 1: [2.0, 2.0], RMS = 2.0
        // Max RMS = 2.0
        XCTAssertEqual(DynaVibe.calculateMTVV(weightedTimeSeries: series, sampleRate: sampleRate, windowSeconds: windowSeconds), 2.0, accuracy: accuracy)
    }

    func testCalculateMTVV_SimplePeakingSignal() {
        let series: [Double] = [1.0, 1.0, 5.0, 5.0, 1.0, 1.0]
        let sampleRate = 1.0
        let windowSeconds = 2.0 // windowSamples = 2
        // Window 1 ([1,1]): RMS = sqrt((1+1)/2) = 1.0
        // Window 2 ([1,5]): RMS = sqrt((1+25)/2) = sqrt(13) approx 3.60555
        // Window 3 ([5,5]): RMS = sqrt((25+25)/2) = 5.0
        // Window 4 ([5,1]): RMS = sqrt((25+1)/2) = sqrt(13) approx 3.60555
        // Window 5 ([1,1]): RMS = sqrt((1+1)/2) = 1.0
        // Expected MTVV: 5.0
        XCTAssertEqual(DynaVibe.calculateMTVV(weightedTimeSeries: series, sampleRate: sampleRate, windowSeconds: windowSeconds), 5.0, accuracy: accuracy)
    }

    func testCalculateMTVV_ZeroSampleRateOrWindow() {
        XCTAssertEqual(DynaVibe.calculateMTVV(weightedTimeSeries: [1,1], sampleRate: 0.0, windowSeconds: 1.0), 0.0, accuracy: accuracy)
        XCTAssertEqual(DynaVibe.calculateMTVV(weightedTimeSeries: [1,1], sampleRate: 100.0, windowSeconds: 0.0), 0.0, accuracy: accuracy)
    }
}
