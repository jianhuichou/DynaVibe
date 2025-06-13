import Foundation
import SwiftData

@Model
final class Measurement {
    var id: UUID
    var timestamp: Date
    var rawX: [Double]
    var rawY: [Double]
    var rawZ: [Double]
    var fftFrequencies: [Double]
    var fftX: [Double]
    var fftY: [Double]
    var fftZ: [Double]
    var rmsX: Double?
    var rmsY: Double?
    var rmsZ: Double?
    var project: Project?

    init(id: UUID = UUID(),
         timestamp: Date = Date(),
         rawX: [Double] = [],
         rawY: [Double] = [],
         rawZ: [Double] = [],
         fftFrequencies: [Double] = [],
         fftX: [Double] = [],
         fftY: [Double] = [],
         fftZ: [Double] = [],
         rmsX: Double? = nil,
         rmsY: Double? = nil,
         rmsZ: Double? = nil,
         project: Project? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.rawX = rawX
        self.rawY = rawY
        self.rawZ = rawZ
        self.fftFrequencies = fftFrequencies
        self.fftX = fftX
        self.fftY = fftY
        self.fftZ = fftZ
        self.rmsX = rmsX
        self.rmsY = rmsY
        self.rmsZ = rmsZ
        self.project = project
    }
}
