// FFTAnalysis.swift

import Foundation
import Accelerate

class FFTAnalysis {
    // Corrected to properly return the FFT results
    func performFFT(input: [Double], samplingRate: Double) -> (real: [Double], imag: [Double], magnitude: [Double], frequencies: [Double]) {
        let count = input.count
        guard count > 0 else { // Handle empty input
            return (real: [], imag: [], magnitude: [], frequencies: [])
        }

        // Ensure count is a power of 2 for vDSP FFT if required, or handle appropriately.
        // For simplicity here, we assume input count is suitable or vDSP handles it.
        // Production code might pad or truncate to a power of 2.
        let log2n = vDSP_Length(log2(Double(count)))

        var realInput = input
        var imagInput = [Double](repeating: 0.0, count: count)

        // This is the key change: The result of the closure is now directly returned.
        return realInput.withUnsafeMutableBufferPointer { realPtr -> (real: [Double], imag: [Double], magnitude: [Double], frequencies: [Double]) in
            imagInput.withUnsafeMutableBufferPointer { imagPtr -> (real: [Double], imag: [Double], magnitude: [Double], frequencies: [Double]) in
                var splitComplex = DSPDoubleSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)

                guard let fftSetup = vDSP_create_fftsetupD(log2n, FFTRadix(kFFTRadix2)) else {
                    // Consider throwing an error instead of fatalError for better handling in ViewModel
                    print("Failed to create FFT setup")
                    return (real: [], imag: [], magnitude: [], frequencies: [])
                }
                defer {
                    vDSP_destroy_fftsetupD(fftSetup)
                }

                vDSP_fft_zipD(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

                // Magnitudes calculation:
                // vDSP_zvmagsD computes magnitude = sqrt(real^2 + imag^2)
                // The result is for N/2 points.
                var magnitudes = [Double](repeating: 0.0, count: count / 2)
                vDSP_zvmagsD(&splitComplex, 1, &magnitudes, 1, vDSP_Length(count / 2))

                // Normalization:
                // For amplitude, divide by N (count).
                // Since vDSP_zvmagsD gives sqrt(re^2+im^2), and we want to scale the amplitude
                // of the original signal components, we scale by 1/N for DC and N/2 for others.
                // A common approach is to scale all by 2/N, then halve DC and Nyquist if present.
                // Or, scale magnitudes (not power) by 1.0 / N for DC and 2.0 / N for non-DC.
                // The previous normalization seemed to be taking sqrt of a scaled power.
                // Let's use a more standard amplitude scaling:
                var normalizedMagnitudes = [Double](repeating: 0.0, count: count / 2)
                
                // Scale DC component (index 0) by 1/N
                if count > 0 && !magnitudes.isEmpty {
                     normalizedMagnitudes[0] = magnitudes[0] / Double(count)
                }
                // Scale other components by 2/N
                // Note: vDSP_vsmulD multiplies by a scalar.
                // Magnitudes from vDSP_zvmagsD are already sqrt(real^2 + imag^2).
                // To get to amplitude of original signal: multiply by 2.0/N
                // (except DC and Nyquist if present).
                // For simplicity, many just scale all N/2 points by 2.0/N.

                var scale = 2.0 / Double(count)
                vDSP_vsmulD(magnitudes, 1, &scale, &normalizedMagnitudes, 1, vDSP_Length(count / 2))
                
                // If the 0th element (DC component) and Nyquist frequency component (if N is even, at index N/2)
                // need to be scaled by 1/N instead of 2/N, adjust them:
                if !normalizedMagnitudes.isEmpty {
                    normalizedMagnitudes[0] = magnitudes[0] / Double(count) // Correct DC component
                }
                // Nyquist frequency (if N is even) is at index N/2 of the original FFT output,
                // which is not included in `magnitudes` if `count/2` is used as length for `vDSP_zvmagsD`.
                // If `vDSP_fft_zipD` output format means `splitComplex.realp[0]` is DC and `splitComplex.realp[count/2]` is Nyquist,
                // then `vDSP_zvmagsD` output `magnitudes[0]` is DC's magnitude. The last element of `magnitudes`
                // is the one just before Nyquist or Nyquist itself depending on interpretation.
                // For now, the common 2/N scaling for all N/2 points is often sufficient for visualization.

                let frequencyResolution = samplingRate / Double(count)
                let frequencies = (0..<count/2).map { Double($0) * frequencyResolution }

                var realOutput = [Double](repeating: 0.0, count: count / 2)
                var imagOutput = [Double](repeating: 0.0, count: count / 2)
                for i in 0..<count / 2 {
                    realOutput[i] = splitComplex.realp[i]
                    imagOutput[i] = splitComplex.imagp[i]
                }
                
                return (real: realOutput, imag: imagOutput, magnitude: normalizedMagnitudes, frequencies: frequencies)
            }
        }
        // The above return now makes this part unreachable if the closures execute.
        // However, to satisfy all paths if early returns happen (e.g. guard count > 0)
        // it's still good practice to have a fallback, though the one inside the closure for FFT setup failure is more relevant.
        // Given the structure, the outer return is effectively shadowed by the inner ones.
    }
}
