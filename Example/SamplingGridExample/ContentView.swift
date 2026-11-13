import SwiftUI
import MapKit
import GeoJSONSwiftHelper

struct ContentView: View {
  @State var model: SamplingModel
  @State private var position: MapCameraPosition = .automatic
  @State private var exportFilter: ExportFilter = .done

  var body: some View {
    NavigationStack {
      MapReader { proxy in
        Map(position: $position) {
          GeoJSONMapContent(model.boundary, fill: .clear, stroke: .white, lineWidth: 3)

          ForEach(model.cells) { cell in
            GeoJSONMapContent(cell.shape,
                              fill: cell.status.color.opacity(0.45),
                              stroke: cell.status.color,
                              lineWidth: 1)
          }
        }
        .mapStyle(.imagery)
        .onTapGesture { location in
          if let coordinate = proxy.convert(location, from: .local) {
            model.cycleStatus(at: coordinate)
          }
        }
      }
      .safeAreaInset(edge: .bottom) {
        GridControls(model: model)
      }
      .navigationTitle("Sampling Grid")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          exportMenu
        }
      }
      .task(id: model.parameters) {
        // Debounce slider drags so the grid is clipped once the value settles.
        guard (try? await Task.sleep(for: .milliseconds(150))) != nil else { return }
        model.regenerateGrid()
      }
    }
  }

  private var exportMenu: some View {
    Menu {
      Picker("Include", selection: $exportFilter) {
        ForEach(ExportFilter.allCases) { filter in
          Text("\(filter.rawValue) (\(model.exportCount(filter)))").tag(filter)
        }
      }

      if let data = try? model.exportData(exportFilter), model.exportCount(exportFilter) > 0 {
        ShareLink(item: GeoJSONFile(data: data),
                  preview: SharePreview("Sampling cells")) {
          Label("Export GeoJSON", systemImage: "square.and.arrow.up")
        }
      } else {
        Text("No cells to export")
      }
    } label: {
      Label("Export", systemImage: "square.and.arrow.up")
    }
  }
}

private struct GridControls: View {
  @Bindable var model: SamplingModel

  var body: some View {
    VStack(spacing: 8) {
      HStack(spacing: 16) {
        ForEach(SampleStatus.allCases) { status in
          Label("\(model.count(of: status))", systemImage: "square.fill")
            .foregroundStyle(status.color)
            .accessibilityLabel("\(status.rawValue.capitalized): \(model.count(of: status))")
        }
        Spacer()
        Text("Tap a cell to change its status")
          .foregroundStyle(.secondary)
      }
      .font(.caption)

      LabeledSlider(title: "Cell size", value: $model.parameters.cellSize, range: 20...100, step: 5, unit: "m")
      LabeledSlider(title: "Rotation", value: $model.parameters.rotation, range: 0...90, step: 1, unit: "°")
      LabeledSlider(title: "Offset E/W", value: $model.parameters.offsetX, range: -50...50, step: 1, unit: "m")
      LabeledSlider(title: "Offset N/S", value: $model.parameters.offsetY, range: -50...50, step: 1, unit: "m")
    }
    .padding()
    .background(.regularMaterial)
  }
}

private struct LabeledSlider: View {
  let title: String
  @Binding var value: Double
  let range: ClosedRange<Double>
  let step: Double
  let unit: String

  var body: some View {
    HStack {
      Text(title)
        .frame(width: 90, alignment: .leading)
      Slider(value: $value, in: range, step: step)
      Text("\(value, format: .number.precision(.fractionLength(0))) \(unit)")
        .monospacedDigit()
        .frame(width: 56, alignment: .trailing)
    }
    .font(.subheadline)
  }
}

extension SampleStatus {
  var color: Color {
    switch self {
    case .pending: .yellow
    case .done: .green
    case .skipped: .red
    }
  }
}
