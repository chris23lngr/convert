import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var windows: [NSWindow: ConvertModel] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        // Launched by double-click (no files)? Show an empty drop panel.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, self.windows.isEmpty else { return }
            self.openPanel([])
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        openPanel(urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openPanel([]) }
        return true
    }

    func openPanel(_ urls: [URL]) {
        // Reuse an empty drop panel if one is open.
        if !urls.isEmpty, let (win, model) = windows.first(where: { $0.value.files.isEmpty && $0.value.phase == .idle })
        {
            model.add(urls)
            win.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let model = ConvertModel(files: urls)
        let host = NSHostingController(rootView: ContentView(model: model))
        host.sizingOptions = [.preferredContentSize]
        let win = NSWindow(contentViewController: host)
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.title = "Convert"
        win.isReleasedWhenClosed = false
        win.delegate = self
        model.onClose = { [weak win] in win?.close() }
        windows[win] = model
        if let last = windows.keys.first(where: { $0 !== win && $0.isVisible }) {
            win.setFrameTopLeftPoint(win.cascadeTopLeft(from: NSPoint(x: last.frame.minX, y: last.frame.maxY)))
        } else {
            win.center()
        }
        win.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        guard let win = notification.object as? NSWindow else { return }
        windows[win]?.cancel()
        windows[win] = nil
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { openPanel(panel.urls) }
    }

    @objc func showAbout(_ sender: Any?) {
        let credits = NSMutableAttributedString(
            string: "Convert any file on your Mac, locally.\nVibe coded, open source (MIT).\n",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        credits.append(
            NSAttributedString(
                string: "convert.newtonbuilds.dev",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .link: URL(string: "https://convert.newtonbuilds.dev")!,
                ]))
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        credits.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: credits.length))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate()
    }

    @objc func installQuickAction(_ sender: Any?) {
        do {
            try QuickAction.install()
            alert(
                "Quick Action installed",
                "Right-click files in Finder → Quick Actions → Convert…\n\nIf it doesn't show up, enable it in System Settings → General → Login Items & Extensions → Finder."
            )
        } catch {
            alert("Couldn't install the Quick Action", error.localizedDescription)
        }
        NotificationCenter.default.post(name: .quickActionChanged, object: nil)
    }

    @objc func removeQuickAction(_ sender: Any?) {
        do { try QuickAction.uninstall() } catch {
            alert("Couldn't remove the Quick Action", error.localizedDescription)
        }
        NotificationCenter.default.post(name: .quickActionChanged, object: nil)
    }

    @objc func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(installQuickAction(_:)): !QuickAction.isInstalled
        case #selector(removeQuickAction(_:)): QuickAction.isInstalled
        default: true
        }
    }

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }

    private func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Convert", action: #selector(showAbout(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Install Finder Quick Action", action: #selector(installQuickAction(_:)), keyEquivalent: "")
        appMenu.addItem(
            withTitle: "Remove Finder Quick Action", action: #selector(removeQuickAction(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Convert", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Convert", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Open…", action: #selector(openDocument(_:)), keyEquivalent: "o")
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        NSApp.mainMenu = main
    }
}
