import AppKit
import SwiftUI
import TouchGateCore

@MainActor
final class WindowCoverController {
    var onUnlock: ((pid_t) -> Void)?
    private struct RegionID: Hashable {
        let pid: pid_t
        let window: CGWindowID
        let fragment: Int
    }
    private var panels: [RegionID: CoverPanel] = [:]
    private var lastFrontmostPID: pid_t?

    func update(lockedApps: [pid_t: String]) -> Bool {
        guard !lockedApps.isEmpty else { clear(); return true }
        guard let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        let coverIDs = Set(panels.values.compactMap { $0.windowNumber > 0 ? CGWindowID($0.windowNumber) : nil })
        let onscreenIDs = Set(rows.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value })
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let focusChanged = frontmostPID != lastFrontmostPID
        let displayTop = NSScreen.screens.first?.frame.maxY ?? 0
        var occluders: [CGRect] = []
        var activeRegions: Set<RegionID> = []
        for row in rows {
            guard let number = row[kCGWindowNumber as String] as? NSNumber,
                  !coverIDs.contains(number.uint32Value),
                  let pid = row[kCGWindowOwnerPID as String] as? NSNumber,
                  let layer = row[kCGWindowLayer as String] as? NSNumber,
                  let bounds = row[kCGWindowBounds as String] as? NSDictionary,
                  let screenFrame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  !screenFrame.isEmpty, (row[kCGWindowAlpha as String] as? NSNumber)?.doubleValue != 0 else { continue }
            let frame = WindowCoverage.appKitFrame(from: screenFrame, primaryDisplayTop: displayTop)
            if let name = lockedApps[pid.int32Value], layer.intValue >= 0, layer.intValue < NSWindow.Level.statusBar.rawValue {
                let fragments = WindowCoverage.visibleRegions(of: frame, behind: occluders)
                    .flatMap { region in NSScreen.screens.map { region.intersection($0.frame) }.filter { !$0.isNull && !$0.isEmpty } }
                for (index, region) in fragments.enumerated() {
                    let id = RegionID(pid: pid.int32Value, window: number.uint32Value, fragment: index)
                    activeRegions.insert(id)
                    let panel: CoverPanel
                    let created: Bool
                    if let existing = panels[id] {
                        panel = existing
                        created = false
                    } else {
                        panel = CoverPanel(contentRect: region, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                        panel.isReleasedWhenClosed = false
                        panel.hidesOnDeactivate = false
                        panel.isOpaque = true
                        panel.backgroundColor = .windowBackgroundColor
                        panel.hasShadow = false
                        panel.animationBehavior = .none
                        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
                        let targetPID = pid.int32Value
                        panel.contentView = NSHostingView(rootView: WindowCoverView(name: name) { [weak self] in self?.onUnlock?(targetPID) })
                        panels[id] = panel
                        created = true
                    }
                    let moved = panel.frame != region
                    if moved { panel.setFrame(region, display: true) }
                    panel.level = NSWindow.Level(rawValue: max(NSWindow.Level.floating.rawValue, layer.intValue + 1))
                    if created || moved || focusChanged || panel.windowNumber <= 0 || !onscreenIDs.contains(CGWindowID(panel.windowNumber)) {
                        panel.orderFrontRegardless()
                    }
                }
            }
            if layer.intValue >= 0 { occluders.append(frame) }
        }
        for id in Set(panels.keys).subtracting(activeRegions) {
            panels.removeValue(forKey: id)?.close()
        }
        lastFrontmostPID = frontmostPID
        return true
    }

    func clear() {
        panels.values.forEach { $0.close() }
        panels.removeAll()
        lastFrontmostPID = nil
    }
}

private final class CoverPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct WindowCoverView: View {
    let name: String
    let onUnlock: () -> Void

    var body: some View {
        GeometryReader { geometry in
            Button(action: onUnlock) {
                VStack(spacing: 10) {
                    Image(systemName: "lock.fill").font(.title2)
                    if geometry.size.width > 180, geometry.size.height > 100 {
                        Text(name).font(.headline)
                        Text("Unlock with Touch ID").font(.caption)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.buttonStyle(.plain)
                .accessibilityLabel("Unlock \(name) with Touch ID")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipped()
        }
    }
}
