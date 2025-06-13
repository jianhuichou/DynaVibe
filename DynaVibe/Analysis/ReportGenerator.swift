import SwiftUI
import UIKit

struct ReportMetric {
    let title: String
    let value: String
}

/// Utility to generate a simple PDF summary of a project including
/// a chart image and a list of metrics.
class ReportGenerator {
    static func generatePDF(title: String, metrics: [ReportMetric], chart: UIImage) -> URL? {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let data = renderer.pdfData { ctx in
            ctx.beginPage()

            // Draw title
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 24)
            ]
            let titleSize = title.size(withAttributes: titleAttributes)
            title.draw(at: CGPoint(x: (pageRect.width - titleSize.width)/2, y: 40), withAttributes: titleAttributes)

            var currentY: CGFloat = 80
            let metricAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14)
            ]
            for metric in metrics {
                let str = "\(metric.title): \(metric.value)" as NSString
                str.draw(at: CGPoint(x: 40, y: currentY), withAttributes: metricAttributes)
                currentY += 20
            }

            // Draw chart image below metrics
            let chartRect = CGRect(x: 40, y: currentY + 20, width: pageRect.width - 80, height: 300)
            chart.draw(in: chartRect)
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("report.pdf")
        do {
            try data.write(to: url)
            return url
        } catch {
            print("Failed to write PDF: \(error)")
            return nil
        }
    }
}

extension View {
    /// Render this SwiftUI view as a UIImage to embed in PDFs.
    func asImage(size: CGSize) -> UIImage {
        let renderer = ImageRenderer(content: self.frame(width: size.width, height: size.height))
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage ?? UIImage()
    }
}
