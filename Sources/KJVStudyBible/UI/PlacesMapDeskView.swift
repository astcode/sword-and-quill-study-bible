import MapKit
import SwiftUI

// MARK: - Biblical Geography & Interactive MapKit Tab (Left Study Desk)

public struct PlacesMapDeskView: View {
    @ObservedObject var viewModel: BibleWorkspaceViewModel

    enum MapVisualStyle: String, CaseIterable, Identifiable {
        case hybrid = "Satellite"
        case standard = "Map"
        case imagery = "Terrain"
        var id: String { rawValue }

        var mapStyle: MapStyle {
            switch self {
            case .hybrid: return .hybrid(elevation: .realistic)
            case .standard: return .standard(elevation: .realistic)
            case .imagery: return .imagery(elevation: .realistic)
            }
        }
    }

    @State private var searchQuery: String = ""
    @State private var searchResults: [BiblicalPlace] = []
    @State private var selectedPlace: BiblicalPlace? = nil
    @State private var selectedPlaceVerses: [SearchResult] = []
    @State private var mapVisualStyle: MapVisualStyle = .hybrid
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 31.7781, longitude: 35.2360), // Jerusalem
            span: MKCoordinateSpan(latitudeDelta: 3.2, longitudeDelta: 3.2)
        )
    )

    private var displayedPlaces: [BiblicalPlace] {
        if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return searchResults
        }
        return viewModel.chapterPlaces
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Search + Map Style Header
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(viewModel.theme.secondaryText)
                    TextField("Search 1,335 biblical places...", text: $searchQuery)
                        .font(.caption)
                        .textFieldStyle(.plain)
                        .onChange(of: searchQuery) { _, val in
                            let q = val.trimmingCharacters(in: .whitespacesAndNewlines)
                            if q.isEmpty {
                                searchResults = []
                                fitMapToPlaces(viewModel.chapterPlaces)
                            } else {
                                searchResults = viewModel.referenceDB.searchPlaces(query: q, limit: 30)
                                fitMapToPlaces(searchResults)
                            }
                        }
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                            searchResults = []
                            fitMapToPlaces(viewModel.chapterPlaces)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(viewModel.theme.secondaryText)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(viewModel.theme.canvasBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(viewModel.theme.dividerColor, lineWidth: 1))

                HStack(spacing: 6) {
                    Text(searchQuery.isEmpty
                         ? "\(viewModel.currentLocationTitle) · \(viewModel.chapterPlaces.count) places"
                         : "\(searchResults.count) matching places")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(viewModel.theme.secondaryText)
                        .lineLimit(1)

                    Spacer()

                    Picker("Style", selection: $mapVisualStyle) {
                        ForEach(MapVisualStyle.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
            }
            .padding(8)
            .background(viewModel.theme.chromeBackground)

            // Interactive MapKit View
            Map(position: $cameraPosition) {
                ForEach(displayedPlaces.prefix(40)) { place in
                    Annotation(place.name, coordinate: CLLocationCoordinate2D(latitude: place.lat, longitude: place.lon)) {
                        Button {
                            focusPlace(place)
                        } label: {
                            VStack(spacing: 2) {
                                Image(systemName: iconForPlaceType(place.placeType))
                                    .font(.system(size: selectedPlace?.id == place.id ? 13 : 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(selectedPlace?.id == place.id ? 6 : 5)
                                    .background(selectedPlace?.id == place.id ? Color.red : viewModel.theme.accentBlue)
                                    .clipShape(Circle())
                                    .shadow(radius: 2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .mapStyle(mapVisualStyle.mapStyle)
            .frame(height: 215)
            .overlay(alignment: .bottomTrailing) {
                Button {
                    fitMapToPlaces(displayedPlaces)
                } label: {
                    Image(systemName: "scope")
                        .font(.caption.weight(.semibold))
                        .padding(6)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .padding(8)
            }

            Divider().overlay(viewModel.theme.dividerColor)

            // Place Detail or Scrollable Place List
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if let sel = selectedPlace {
                        selectedPlaceDetailCard(sel)
                    }

                    if displayedPlaces.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "map")
                                .font(.title2)
                                .foregroundStyle(viewModel.theme.secondaryText)
                            Text(searchQuery.isEmpty
                                 ? "No named geographic locations in \(viewModel.currentLocationTitle). Search above to explore all 1,335 biblical places (Jerusalem, Galilee, Sinai, Bethany...)."
                                 : "No biblical places matched \"\(searchQuery)\".")
                                .font(.caption)
                                .foregroundStyle(viewModel.theme.secondaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 12)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
                        ForEach(displayedPlaces) { place in
                            Button {
                                focusPlace(place)
                            } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: iconForPlaceType(place.placeType))
                                        .font(.caption)
                                        .foregroundStyle(selectedPlace?.id == place.id ? .white : viewModel.theme.accentBlue)
                                        .frame(width: 24, height: 24)
                                        .background(selectedPlace?.id == place.id ? viewModel.theme.accentBlue : viewModel.theme.accentBlue.opacity(0.12))
                                        .clipShape(Circle())

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(place.name)
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(viewModel.theme.primaryText)
                                            Text(place.placeType)
                                                .font(.system(size: 9.5, weight: .semibold))
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(viewModel.theme.accentBlue.opacity(0.12))
                                                .foregroundStyle(viewModel.theme.accentBlue)
                                                .clipShape(Capsule())
                                        }
                                        if !place.modernName.isEmpty && place.modernName.lowercased() != place.name.lowercased() {
                                            Text("Modern: \(place.modernName)")
                                                .font(.caption2)
                                                .foregroundStyle(viewModel.theme.secondaryText)
                                                .lineLimit(1)
                                        }
                                        HStack(spacing: 8) {
                                            Text("\(place.verseCount) \(place.verseCount == 1 ? "verse" : "verses")")
                                                .font(.caption2)
                                                .foregroundStyle(viewModel.theme.secondaryText)
                                            if place.name.lowercased() != "jerusalem" {
                                                Text("· \(place.milesFromJerusalem) mi from Jerusalem")
                                                    .font(.caption2)
                                                    .foregroundStyle(viewModel.theme.secondaryText)
                                            }
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(8)
                                .background(selectedPlace?.id == place.id ? viewModel.theme.accentBlue.opacity(0.10) : viewModel.theme.canvasBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selectedPlace?.id == place.id ? viewModel.theme.accentBlue : viewModel.theme.dividerColor, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(10)
            }
        }
        .onAppear {
            fitMapToPlaces(viewModel.chapterPlaces)
        }
        .onChange(of: viewModel.chapterPlaces) { _, newPlaces in
            if searchQuery.isEmpty {
                selectedPlace = nil
                selectedPlaceVerses = []
                fitMapToPlaces(newPlaces)
            }
        }
    }

    private func selectedPlaceDetailCard(_ place: BiblicalPlace) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(place.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(viewModel.theme.primaryText)
                Spacer()
                Button {
                    var summary = "\(place.name) (\(place.placeType))"
                    if !place.modernName.isEmpty { summary += " — Modern: \(place.modernName)" }
                    if !place.description.isEmpty { summary += "\n\(place.description)" }
                    summary += String(format: "\nCoords: %.3f°N, %.3f°E (%d mi from Jerusalem)", place.lat, place.lon, place.milesFromJerusalem)
                    viewModel.startClipToJournal(sourceLabel: "Place: \(place.name)", text: summary)
                } label: {
                    Label("Clip", systemImage: "scissors")
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(viewModel.theme.accentBlue)

                Button {
                    selectedPlace = nil
                    selectedPlaceVerses = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(viewModel.theme.secondaryText)
                }
            }

            if !place.modernName.isEmpty {
                Text("Modern ID: \(place.modernName)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(viewModel.theme.accentBlue)
            }

            if !place.description.isEmpty {
                Text(place.description)
                    .font(.caption)
                    .foregroundStyle(viewModel.theme.primaryText)
            }

            Text(String(format: "%.3f° N, %.3f° E · %d mi from Jerusalem", place.lat, place.lon, place.milesFromJerusalem))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(viewModel.theme.secondaryText)

            if !selectedPlaceVerses.isEmpty {
                Text("VERSES MENTIONING \(place.name.uppercased())")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(viewModel.theme.secondaryText)
                    .padding(.top, 2)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 5)], alignment: .leading, spacing: 5) {
                    ForEach(selectedPlaceVerses.prefix(16)) { res in
                        Button {
                            let book = viewModel.referenceDB.book(id: res.bookId)
                            let ref = CrossReference(
                                id: res.id,
                                fromBook: viewModel.currentBookId,
                                fromChapter: viewModel.currentChapter,
                                fromVerse: 1,
                                phrase: place.name,
                                toBook: res.bookId,
                                toChapter: res.chapter,
                                toVerseStart: res.verse,
                                toVerseEnd: res.verse,
                                toBookAbbr: book?.abbr ?? res.bookName,
                                toBookName: res.bookName
                            )
                            viewModel.openCrossRefPreview(ref)
                        } label: {
                            let abbr = viewModel.referenceDB.book(id: res.bookId)?.abbr ?? res.bookName
                            Text("\(abbr) \(res.chapter):\(res.verse)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(viewModel.theme.accentBlue)
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .frame(maxWidth: .infinity)
                                .background(viewModel.theme.accentBlue.opacity(0.11))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(10)
        .background(viewModel.theme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(viewModel.theme.accentBlue.opacity(0.45), lineWidth: 1.2))
    }

    private func focusPlace(_ place: BiblicalPlace) {
        selectedPlace = place
        selectedPlaceVerses = viewModel.referenceDB.versesForPlace(placeId: place.id, limit: 24)
        viewModel.recordStudyEvent(
            kind: .place,
            title: place.name,
            detail: place.modernName.isEmpty ? place.placeType : "\(place.placeType) · Modern: \(place.modernName)",
            bookId: viewModel.currentBookId,
            chapter: viewModel.currentChapter,
            refKey: place.id
        )
        withAnimation(.easeInOut(duration: 0.35)) {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: place.lat, longitude: place.lon),
                    span: MKCoordinateSpan(latitudeDelta: 0.65, longitudeDelta: 0.65)
                )
            )
        }
    }

    private func fitMapToPlaces(_ places: [BiblicalPlace]) {
        guard !places.isEmpty else {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 31.7781, longitude: 35.2360),
                    span: MKCoordinateSpan(latitudeDelta: 3.5, longitudeDelta: 3.5)
                )
            )
            return
        }
        if places.count == 1, let p = places.first {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon),
                    span: MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 1.2)
                )
            )
            return
        }
        let lats = places.prefix(30).map(\.lat)
        let lons = places.prefix(30).map(\.lon)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let latSpan = max(0.8, min(25.0, (maxLat - minLat) * 1.45))
        let lonSpan = max(0.8, min(25.0, (maxLon - minLon) * 1.45))
        cameraPosition = .region(MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan)))
    }

    private func iconForPlaceType(_ type: String) -> String {
        let low = type.lowercased()
        if low.contains("mountain") || low.contains("hill") { return "mountain.2.fill" }
        if low.contains("river") || low.contains("water") || low.contains("sea") || low.contains("spring") { return "drop.fill" }
        if low.contains("region") || low.contains("people") { return "map.fill" }
        return "mappin"
    }
}
