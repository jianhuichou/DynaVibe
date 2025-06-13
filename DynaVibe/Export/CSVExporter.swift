// Utility to export acceleration data as CSV
import Foundation

class CSVExporter {
    static func exportAccelerationData(_ data: [(timestamp: TimeInterval, x: Double, y: Double, z: Double)]) -> URL? {
        let header = "timestamp,x,y,z\n"
        let rows = data.map { String(format: "%.6f,%.6f,%.6f,%.6f", $0.timestamp, $0.x, $0.y, $0.z) }
        let csvString = ([header] + rows).joined(separator: "\n")
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("acceleration_data.csv")
        do {
            try csvString.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("CSV export failed: \(error)")
            return nil
        }
    }

    /// Export FFT results as CSV with columns for frequency and magnitude.
    static func exportFFTData(frequencies: [Double], magnitudes: [Double]) -> URL? {
        guard frequencies.count == magnitudes.count else { return nil }
        let header = "frequency,magnitude\n"
        let rows = zip(frequencies, magnitudes).map { freq, mag in
            String(format: "%.6f,%.6f", freq, mag)
        }
        let csvString = ([header] + rows).joined(separator: "\n")

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("fft_data.csv")
        do {
            try csvString.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("CSV export failed: \(error)")
            return nil
        }
    }
}
