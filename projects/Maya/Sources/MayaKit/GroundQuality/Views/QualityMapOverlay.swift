import MapKit
import SwiftUI

/// Renders colour-coded polylines on a Map for each ``TrailSegment``.
///
/// Each segment is drawn as a line from start to end coordinate, coloured
/// by its quality score.
public struct QualityMapOverlay: View {

    let segments: [TrailSegment]

    public init(segments: [TrailSegment]) {
        self.segments = segments
    }

    public var body: some View {
        Map {
            ForEach(segments) { segment in
                MapPolyline(coordinates: [
                    segment.startCoordinate.clLocationCoordinate,
                    segment.endCoordinate.clLocationCoordinate,
                ])
                .stroke(
                    QualityColor.color(for: segment.score.value),
                    lineWidth: 4
                )
            }
        }
        .mapStyle(.standard(elevation: .realistic))
    }
}
