struct Measurement: Identifiable {
    let id = UUID()
    let date: Date
    let timeSeriesData: [Axis: [DataPoint]]
    let fftFrequencies: [Double]
    let fftMagnitudes: [Axis: [Double]]
    let rmsX: Double?
    let rmsY: Double?
    let rmsZ: Double?
    let minX: Double?
    let maxX: Double?
    let minY: Double?
    let maxY: Double?
    let minZ: Double?
    let maxZ: Double?
    let peakFrequencyX: Double?
    let peakFrequencyY: Double?
    let peakFrequencyZ: Double?
}
