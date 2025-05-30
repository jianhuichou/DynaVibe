//
//  FrequencyWeighting.swift
//  DynaVibe
//
//  Created by AI Assistant on 2024-10-28.
//  Copyright © 2024 DynaVibe Project. All rights reserved.
//

import Foundation

// This file will contain functions and structures for applying
// frequency weighting to vibration data as per standards like ISO 2631.

// Enum for different weighting types
/// Defines standard frequency weighting curves for vibration analysis based on user-provided formulas.
public enum WeightingType: String, CaseIterable, Identifiable {
    case none = "None"
    case wg = "Wg" // Motion Sickness (User formula based on ISO 2631 / BS 6841 snippets)
    case wb = "Wb" // Whole Body (User formula based on ISO 2631 / BS 6841 snippets)
    case wd = "Wd" // Horizontal Whole Body (User formula based on ISO 2631 / BS 6841 snippets)

    public var id: String { self.rawValue }

    // Descriptions can be added or refined here if needed
    public var description: String {
        switch self {
        case .none:
            return "No frequency weighting applied."
        case .wg:
            return "Wg weighting for motion sickness related vibration (User Formula)."
        case .wb:
            return "Wb weighting for whole-body vibration (User Formula)."
        case .wd:
            return "Wd weighting for horizontal whole-body vibration (User Formula)."
        }
    }
}

// MARK: - Weighting Factor Calculation

/// Calculates the frequency weighting factor (gain) for a given frequency and weighting type.
/// - Parameters:
///   - frequency: The frequency (in Hz) at which to calculate the weighting factor.
///   - type: The `WeightingType` to apply.
/// - Returns: The gain (amplitude factor) at the specified frequency. Returns 1.0 if type is `.none` or for frequencies <= 0.
public func getFrequencyWeightingFactor(frequency: Double, type: WeightingType) -> Double {
    guard frequency > 0 else { return 1.0 } // Weighting is not typically defined for DC or negative frequencies
    guard type != .none else { return 1.0 }

    // Transfer function constants for various weighting curves (from ISO 2631-1 and other sources)
    // H(s) = (K * s^n) / (s^2 + a*s + b) for band-limiting filters
    // H(s) = (K * s^n1 * (s^2 + c*s + d)) / ((s^2 + a1*s + b1)*(s^2 + a2*s + b2)) for more complex filters
    // For digital implementation, these are typically converted to poles/zeros in the z-domain.
    // Here, we'll implement the magnitude response of H(j*2*pi*f).

    let f = frequency
    let s = 2.0 * .pi * f * 1.0i // s = jw, where w = 2*pi*f. Using imaginary literal for Complex type.

    // Placeholder for Complex type if not available by default;
    // For now, we'll calculate magnitude squared |H(jw)|^2 directly using real arithmetic
    // to avoid needing a full Complex number library for this step.
    // |s| = w = 2*pi*f
    // s^2 = -w^2
    // s^3 = -jw^3
    // s^4 = w^4

    let w = 2.0 * .pi * f // angular frequency omega
    // Note: s = jw. For magnitude calculations |s| = w, s^2 = -w^2, etc.
    // Pole-zero calculation infrastructure is preserved for future use (e.g., time-domain filters)
    // but is NOT used for Wg, Wb, Wd in this function as per current requirements.

    // Complex number representation (real, imag parts of a pole or zero in s-plane)
    // ... (ComplexPoleZero struct and static pole/zero definitions remain here but are not used by the switch cases below for Wg, Wb, Wd)
    fileprivate struct ComplexPoleZero { // fileprivate to be accessible by static members
        let sigma: Double // Real part (σ)
        let omega_pz: Double // Imaginary part (ω_polezero)
        func magnitudeSq(omega_signal: Double) -> Double {
            let term_re_sq = sigma * sigma
            let term_im_diff = omega_signal - omega_pz
            return term_re_sq + term_im_diff * term_im_diff
        }
    }
    private static let wk_k: Double = 1.0; private static let wk_zeros: [ComplexPoleZero] = []; private static let wk_poles: [ComplexPoleZero] = [] // Simplified
    private static let wd_k_illustrative: Double = 1.0; private static let wd_zeros_illustrative: [ComplexPoleZero] = []; private static let wd_poles_illustrative: [ComplexPoleZero] = [] // Simplified
    private static let wg_k_illustrative: Double = 1.0; private static let wg_zeros_illustrative: [ComplexPoleZero] = []; private static let wg_poles_illustrative: [ComplexPoleZero] = [] // Simplified

    fileprivate static func evaluateTransferFunctionMagnitude(omega: Double, k: Double, zeros: [ComplexPoleZero], poles: [ComplexPoleZero]) -> Double {
        var numMagSq: Double = k * k
        for zero in zeros { numMagSq *= zero.magnitudeSq(omega_signal: omega) }
        var denMagSq: Double = 1.0
        for pole in poles {
            let poleMagSq = pole.magnitudeSq(omega_signal: omega)
            if poleMagSq < 1e-12 { return 0.0 }
            denMagSq *= poleMagSq
        }
        if denMagSq < 1e-12 { return 0.0 }
        return sqrt(numMagSq / denMagSq)
    }
    // End of preserved pole-zero infrastructure for future use.

    // Implementation using user-provided mathematical formulas
    // Source: User-provided based on ISO 2631 / BS 6841 snippets
    switch type {
    case .wg:
        // Wg: User formula. Targeted for 1 Hz to 80 Hz range by user.
        // Formulas define behavior for 1 Hz and above.
        // Behavior below 1 Hz (e.g. 0.1 Hz to 1 Hz) is not specified by these piecewise formulas.
        // Standard Wg (e.g. ISO 2631-1 Annex B / BS 6841) has defined response < 1 Hz.
        // For this implementation, returning 0.0 for f < 1 Hz as per user's formula structure for Wg.
        if frequency < 1.0 { return 0.0 } // Below 1 Hz, as per user formula starting point for Wg.

        // Formula: W = 0.5 * sqrt(frequency) for 1 Hz <= frequency < 4 Hz
        if frequency < 4.0 { // This covers [1.0, 4.0)
            return 0.5 * sqrt(frequency)
        }
        // Formula: W = 1.0 for 4 Hz <= frequency <= 8 Hz
        else if frequency <= 8.0 { // This covers [4.0, 8.0]
            return 1.0
        }
        // Formula: W = 8.0 / frequency for frequency > 8 Hz
        else { // This covers (8.0, infinity). User context implies up to 80Hz.
               // Standard Wg rolls off; 8.0/frequency continues this roll-off.
            return 8.0 / frequency
        }
        // Fallback, though logic above should cover all f >= 1.0

    case .wb:
        // Wb: User formula. Targeted for 0.1 Hz to 100 Hz range by user.
        // Formulas define behavior for 1 Hz and above.
        // Behavior below 1 Hz is not specified by these piecewise formulas.
        // Standard Wb (e.g. ISO 2631-1) has defined response < 1 Hz (typically flat then roll-off).
        // For this implementation, returning 0.0 for f < 1 Hz as per user's formula structure for Wb.
        if frequency < 1.0 { return 0.0 } // Below 1 Hz, as per user formula starting point for Wb.

        // Formula: W = 0.4 * sqrt(frequency) for 1 Hz <= frequency < 2 Hz
        if frequency < 2.0 { // This covers [1.0, 2.0)
            return 0.4 * sqrt(frequency)
        }
        // Formula: W = frequency / 5.0 for 2 Hz <= frequency < 5 Hz
        else if frequency < 5.0 { // This covers [2.0, 5.0)
            return frequency / 5.0
        }
        // Formula: W = 1.0 for 5 Hz <= frequency <= 16 Hz
        else if frequency <= 16.0 { // This covers [5.0, 16.0]
            return 1.0
        }
        // Formula: W = 16.0 / frequency for frequency > 16 Hz
        else { // This covers (16.0, infinity). User context implies up to 100Hz.
               // Standard Wb rolls off; 16.0/frequency continues this roll-off.
            return 16.0 / frequency
        }
        // Fallback, though logic above should cover all f >= 1.0

    case .wd:
        // Wd: User formula. Targeted for 0.1 Hz to 100 Hz range by user.
        // Formulas define behavior for 1 Hz and above.
        // Behavior below 1 Hz is not specified by these piecewise formulas.
        // Standard Wd (e.g. ISO 2631-1) has defined response < 1 Hz.
        // For this implementation, returning 0.0 for f < 1 Hz.
        if frequency < 1.0 { return 0.0 } // Below 1 Hz.

        // Formula: W = 1.0 for 1 Hz <= frequency < 2 Hz
        if frequency < 2.0 { // This covers [1.0, 2.0)
            return 1.0
        }
        // Formula: W = 2.0 / frequency for frequency >= 2 Hz
        else { // This covers [2.0, infinity). User context implies up to 100Hz.
               // Standard Wd rolls off; 2.0/frequency continues this.
            return 2.0 / frequency
        }
        // Fallback, though logic above should cover all f >= 1.0

    // case .wk, .wc, .we: // These are not part of the current requirement
    // return 1.0 // Or specific implementations if added back
    default: // Catches .none and any other unexpected cases
        return 1.0
    }
}

// MARK: - Time Domain Filtering (Placeholder)
        // Wc: typically 0.5 Hz to 20 Hz, peak around 1-2 Hz.
        // We: typically 0.1 Hz to 10 Hz, peak around 0.2-0.8 Hz.
        // For now, pass-through (no weighting).
        return 1.0

    default: // .none
        return 1.0
    }
}

// MARK: - Time Domain Filtering (Placeholder)
        // These also have specific transfer functions.
        // For now, pass-through (no weighting).
        return 1.0

    default: // .none
        return 1.0
    }
}

// MARK: - Time Domain Filtering (Placeholder)
        // Wc (roll) is sensitive around 1-2 Hz.
        // We (pitch) is sensitive around 0.5-1 Hz.
        // For now, pass-through.
        return 1.0

    default: // .none
        return 1.0
    }
}

// MARK: - Time Domain Filtering (Placeholder)
// Applying frequency weighting in the time domain typically involves IIR or FIR filters.
// This requires filter design (e.g., from poles/zeros of the standard weighting curves).

/// Placeholder for a class that would apply frequency weighting using a digital filter.
public class FrequencyWeightingFilter {
    private var type: WeightingType
    // private var coefficients: [Double] // Filter coefficients (e.g., b0, b1, b2, a1, a2 for biquad)
    // private var zState: [Double]      // Previous input/output samples for IIR filter state

    public init(type: WeightingType, samplingRate: Double) {
        self.type = type
        // Here, one would design the filter based on type and samplingRate.
        // This involves converting analog prototype poles/zeros (from ISO standard)
        // to digital filter coefficients using methods like Bilinear Transform.
        // For example, for Wk, one would get the poles/zeros for H_hp(s) * H_lp(s) * H_bandpass(s) etc.
        // and convert them to a cascade of biquad sections.
        print("FrequencyWeightingFilter initialized for \(type.rawValue) at \(samplingRate) Hz. Filter design not yet implemented.")
    }

    /// Processes a single sample. (Stateful operation for IIR)
    public func processSample(_ input: Double) -> Double {
        guard type != .none else { return input }
        // Actual filtering logic would go here.
        // y[n] = b0*x[n] + b1*x[n-1] + ... - a1*y[n-1] - a2*y[n-2] - ...
        // This is a simplified placeholder.
        print("Warning: processSample in FrequencyWeightingFilter is a placeholder and not applying actual weighting.")
        return input // Placeholder - returns input unmodified
    }

    /// Processes an array of samples.
    public func processSamples(_ input: [Double]) -> [Double] {
        guard type != .none else { return input }
        // For stateless FIR or if managing state internally for blocks:
        // return input.map { processSample($0) } // Naive if processSample is stateful IIR for single samples

        // A proper block processing for IIR would maintain state across calls or process the whole block statefully.
        print("Warning: processSamples in FrequencyWeightingFilter is a placeholder and not applying actual weighting.")
        return input // Placeholder
    }
}


// Class/struct to apply weighting filter to time-series data
// (Implementations to be added in subsequent steps)

// MARK: - Vibration Dose Value (VDV) Calculation

/// Calculates the Vibration Dose Value (VDV) from a time series of weighted acceleration.
/// VDV = [∫ a_w(t)⁴ dt]^(1/4)
/// - Parameters:
///   - weightedTimeSeries: An array of frequency-weighted acceleration values (in m/s²).
///   - sampleRate: The sample rate of the time series data (in Hz).
/// - Returns: The calculated VDV (in m/s¹.⁷⁵). Returns 0.0 if data is empty or sampleRate is not positive.
public func calculateVDV(weightedTimeSeries: [Double], sampleRate: Double) -> Double {
    guard !weightedTimeSeries.isEmpty, sampleRate > 0 else { return 0.0 }

    let dt = 1.0 / sampleRate // Time interval between samples
    var sumOfFourthPowers: Double = 0.0

    for accelerationSample in weightedTimeSeries {
        sumOfFourthPowers += pow(accelerationSample, 4)
    }

    let integralOfFourthPowers = sumOfFourthPowers * dt
    let vdv = pow(integralOfFourthPowers, 0.25)

    return vdv
}

// MARK: - Maximum Transient Vibration Value (MTVV) Calculation

/// Calculates the Maximum Transient Vibration Value (MTVV) from a time series of weighted acceleration.
/// MTVV is the maximum of the running RMS values, typically with a 1-second integration time.
/// - Parameters:
///   - weightedTimeSeries: An array of frequency-weighted acceleration values (in m/s²).
///   - sampleRate: The sample rate of the time series data (in Hz).
///   - windowSeconds: The duration of the running RMS window (in seconds, typically 1.0s for MTVV).
/// - Returns: The calculated MTVV (in m/s²). Returns 0.0 if data is insufficient or parameters are invalid.
public func calculateMTVV(weightedTimeSeries: [Double],
                                 sampleRate: Double,
                                 windowSeconds: Double = 1.0) -> Double {
    guard !weightedTimeSeries.isEmpty, sampleRate > 0, windowSeconds > 0 else { return 0.0 }

    let windowSamples = Int(windowSeconds * sampleRate)
    guard windowSamples > 0 else { return 0.0 } // Window is too short

    // ISO 2631-1 defines MTVV as max of running RMS with 1s integration time.
    // If the total signal duration is less than the window duration,
    // standard practice might vary (e.g., RMS of whole signal, or undefined).
    // Here, we return 0.0 if the signal is shorter than one window,
    // as a "running" RMS cannot be properly established over its defined window length.
    guard weightedTimeSeries.count >= windowSamples else {
        // Alternative: Calculate RMS of the whole signal if shorter than windowSamples
        // let sumOfSquares = weightedTimeSeries.reduce(0.0) { $0 + ($1 * $1) }
        // return sqrt(sumOfSquares / Double(weightedTimeSeries.count))
        return 0.0
    }

    var maxRunningRMS: Double = 0.0

    // Iterate with a sliding window
    // Number of possible windows: weightedTimeSeries.count - windowSamples + 1
    for i in 0...(weightedTimeSeries.count - windowSamples) {
        let windowData = Array(weightedTimeSeries[i ..< (i + windowSamples)])

        // windowData should not be empty due to loop condition and prior checks
        // but as a safeguard if Array slicing behaves unexpectedly with empty result:
        if windowData.isEmpty { continue }

        let sumOfSquaresInWindow = windowData.reduce(0.0) { $0 + ($1 * $1) }
        let rmsOfWindow = sqrt(sumOfSquaresInWindow / Double(windowData.count))

        if rmsOfWindow > maxRunningRMS {
            maxRunningRMS = rmsOfWindow
        }
    }
    return maxRunningRMS
}


import Accelerate

// MARK: - FFT-based Frequency Weighting
extension FrequencyWeightingFilter { // Extend the placeholder class with static methods for now

    public static func applyWeightingViaFFT(timeSeries: [Double],
                                           sampleRate: Double,
                                           weightingType: WeightingType) -> [Double] {
        if weightingType == .none {
            return timeSeries
        }

        let n = timeSeries.count
        guard n > 0, let fft = DSP.FFT(count: n, realSource: true, direction: .forward) else {
            print("Error: Could not create FFT setup or n is 0.")
            return timeSeries // Return original if FFT setup fails or n=0
        }

        // Prepare buffers for FFT output (packed format for real FFT)
        // For a real input of N samples, the output is N/2 complex numbers.
        // The first element is DC (real), Nyquist (if N is even) is also real and packed into imag part of DC or last element.
        // DSP.FFT handles this by expecting N/2 for real and N/2 for imag parts of the complex packed output.
        // However, the modern DSP.FFT with ComplexBuffer might abstract this better.
        // Let's use the split complex representation as it's common with vDSP's underlying concepts
        // and often easier to manage for element-wise operations.
        // For N input samples, we get N/2 complex results.
        // DC is stored in realp[0], Nyquist (if N is even) in imagp[0] if using vDSP_fft_rzip.
        // Or, more simply with DSP.FFT, it produces N/2 complex values.
        // If N is even, N/2 complex values. C[0] = DC, C[N/2-1] contains info up to Nyquist-df.
        // If N is odd, (N-1)/2 complex values.
        // The output of DSP.FFT transform on real data using ComplexBuffer is N/2 complex numbers.
        // The Nyquist frequency component (if N is even) is stored as the imaginary part of the DC component (realParts[0], imagParts[0])
        // when using certain vDSP routines. However, DSP.FFT with ComplexBuffer might be more straightforward:
        // It produces N/2 complex values if N is even. DC is realParts[0] (imagParts[0] should be 0).
        // Nyquist is realParts[n/2] (imagParts[n/2] should be 0) if using certain split complex representations.
        // Let's assume DSP.FFT output for realSource gives N/2 complex numbers (output.count = N/2).
        // The last element realParts[N/2-1] + j*imagParts[N/2-1] corresponds to frequencies near Nyquist.

        var realParts = [Double](repeating: 0.0, count: n / 2)
        var imagParts = [Double](repeating: 0.0, count: n / 2)

        // Perform forward FFT
        timeSeries.withUnsafeBufferPointer { inputBufferPtr in
            var tempTimeSeries = [Double](inputBufferPtr) // Mutable copy for in-place operations if needed by some FFTs
            tempTimeSeries.withUnsafeMutableBufferPointer { tempInputBufferPtr in
                var complexOutput = DSP.ComplexBuffer(real: &realParts, imaginary: &imagParts)
                fft.transform(input: tempInputBufferPtr, output: &complexOutput)
            }
        }

        // Construct Weighting Curve W(f) and Apply it
        let df = sampleRate / Double(n)
        // N points in time domain -> N/2 complex points in frequency domain (excluding symmetric part)
        // Bin 0: DC (0 Hz)
        // Bin k: k * df Hz
        // Bin N/2-1: (N/2 - 1) * df Hz (highest freq for N/2 complex points if N is even)
        // Nyquist frequency is sampleRate / 2.0, which corresponds to bin N/2.

        for k in 0..<(n / 2) {
            let frequency: Double
            // Special handling for DC (k=0) and Nyquist (k=n/2, if N is even) might be needed
            // depending on FFT packing and how getFrequencyWeightingFactor handles f=0 or f=Nyquist.
            // Our getFrequencyWeightingFactor returns 1.0 for f=0.
            // For DSP.FFT, the k-th element corresponds to frequency k*df.
            frequency = Double(k) * df

            let weightingFactor = getFrequencyWeightingFactor(frequency: frequency, type: weightingType)

            realParts[k] *= weightingFactor
            imagParts[k] *= weightingFactor
        }

        // If N is even, the Nyquist frequency (f = sampleRate/2, k = N/2) might be stored separately by some FFTs
        // or handled as a purely real component. DSP.FFT for real signals (count N) produces N/2 complex results.
        // The frequency for realParts[k] and imagParts[k] is k * df.
        // The highest frequency represented explicitly is (N/2 - 1) * df.
        // The component at Nyquist frequency (N/2 * df) is implicitly real and might be packed.
        // However, modern DSP.FFT might just give N/2 complex numbers and the framework handles reconstruction.
        // For DSP.FFT, the output is N/2 complex numbers. Frequencies are 0*df, 1*df, ..., (N/2-1)*df.
        // We don't need to handle Nyquist separately for multiplication if it's part of this complex array.
        // If `getFrequencyWeightingFactor` handles frequency 0 correctly (returns a non-NaN/inf value), DC is fine.
        // Our `getFrequencyWeightingFactor` returns 1.0 if f=0 for non-.none types, which might be okay for DC.
        // Or, for DC (k=0), sometimes weighting is explicitly 1.0 or not applied.
        // Let's assume getFrequencyWeightingFactor(frequency: 0.0, type: weightingType) is what we want for DC.
        // The loop `0..<(n/2)` covers all output complex numbers.

        // Perform Inverse IFFT
        guard let ifft = DSP.FFT(count: n, realSource: false, direction: .inverse) else {
            print("Error: Could not create IFFT setup.")
            return timeSeries // Return original on error
        }

        var weightedTimeSeries = [Double](repeating: 0.0, count: n)
        realParts.withUnsafeMutableBufferPointer { realPtr in
            imagParts.withUnsafeMutableBufferPointer { imagPtr in
                var complexInput = DSP.ComplexBuffer(real: realPtr, imaginary: imagPtr)
                weightedTimeSeries.withUnsafeMutableBufferPointer { outputBufferPtr in
                    ifft.transform(input: complexInput, output: outputBufferPtr)
                }
            }
        }

        // IFFT output from Accelerate framework usually needs scaling by 1/N or 1/sqrt(N).
        // For DSP.FFT, it's typically 1/N.
        let scaleFactor = 1.0 / Double(n)
        weightedTimeSeries = weightedTimeSeries.map { $0 * scaleFactor }

        return weightedTimeSeries
    }
}
