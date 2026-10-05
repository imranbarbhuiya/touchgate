import CoreGraphics

public enum WindowCoverage {
    public static func visibleRegions(of frame: CGRect, behind occluders: [CGRect]) -> [CGRect] {
        occluders.reduce(frame.isEmpty ? [] : [frame]) { regions, occluder in
            regions.flatMap { region -> [CGRect] in
                let overlap = region.intersection(occluder)
                guard !overlap.isNull, !overlap.isEmpty else { return [region] }
                return [
                    CGRect(x: region.minX, y: region.minY, width: region.width, height: overlap.minY - region.minY),
                    CGRect(x: region.minX, y: overlap.maxY, width: region.width, height: region.maxY - overlap.maxY),
                    CGRect(x: region.minX, y: overlap.minY, width: overlap.minX - region.minX, height: overlap.height),
                    CGRect(x: overlap.maxX, y: overlap.minY, width: region.maxX - overlap.maxX, height: overlap.height)
                ].filter { !$0.isEmpty }
            }
        }
    }

    public static func appKitFrame(from screenFrame: CGRect, primaryDisplayTop: CGFloat) -> CGRect {
        CGRect(x: screenFrame.minX, y: primaryDisplayTop - screenFrame.maxY,
               width: screenFrame.width, height: screenFrame.height)
    }
}
