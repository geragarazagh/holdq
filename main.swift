// HoldQ: ⌘Q quits an app only when held for a second; a short press quits nothing.
// Apple parts only, no permission of any kind: a Carbon hot key and NSRunningApplication.terminate().
// No network, no logs, no files; the one thing it keeps is UserDefaults' "launched" flag of the window.
//
// Why it is built this way:
// - ⌘Q is taken as a Carbon hot key (RegisterEventHotKey). A registered hot key reaches the hot key's
//   owner before any app sees it as a key press, it reports both press and release, and it needs no
//   Accessibility (since macOS 27 «Device Control and Data Access»), no Input Monitoring. The older
//   apps of this kind (SlowQuitApps and its forks) use an event tap, which needs that permission and
//   broke on new systems (their issues 97, 99, 101, 102).
// - The hold quits the app that owns the menu bar, the one a ⌘Q would have gone to, through
//   NSRunningApplication.terminate(): the quit Apple Event, the same request as File > Quit, so the
//   app still asks about unsaved work. Finder has no Quit in its menu unless QuitMenuItem is set, so
//   there a hold does nothing, as ⌘Q does.
// - The key is the one that types "q" with ⌘ held in the current Latin layout: the physical Q in
//   QWERTY, ABC, Russian, Ukrainian; the right key in Dvorak and the like. Looked up again when the
//   layout changes.
// - ⌘⇧Q (Log Out) and ⌥⌘Q (Quit and keep windows) are other combinations and stay untouched.
//
// Check the key lookup without starting the app: HoldQ --keycode  prints the key code ⌘Q is taken from.

import AppKit
import Carbon.HIToolbox

let holdTime: TimeInterval = 1.0

// The virtual key that gives "q" with ⌘ held in the current ASCII-capable layout.
func quitKeyCode() -> Int {
    guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
          let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return kVK_ANSI_Q }
    let data = unsafeBitCast(raw, to: CFData.self)
    let layout = unsafeBitCast(CFDataGetBytePtr(data), to: UnsafePointer<UCKeyboardLayout>.self)
    for key in 0..<128 {
        var dead: UInt32 = 0, count = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(layout, UInt16(key), UInt16(kUCKeyActionDown), UInt32(cmdKey >> 8) & 0xFF, UInt32(LMGetKbdType()),
                                    OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &count, &chars)
        if status == noErr, String(utf16CodeUnits: chars, count: count).lowercased() == "q" { return key }
    }
    return kVK_ANSI_Q
}

// Test builds only (TRACE=1 ./build): every 4 ms while the sign is up, the time, the ring as drawn (presentation
// layer) and the window's alpha go to stderr; also press, release and quit. Release builds have none of this.
#if TRACE
func trace(_ s: String) { FileHandle.standardError.write("\(String(format: "%.4f", CACurrentMediaTime())) \(s)\n".data(using: .utf8)!) }
#endif

// Carbon's handler is a C function and can capture nothing.
private var onKey: ((Bool) -> Void)?

// The small sign in the middle of the screen while ⌘Q is held: the app's icon, a ring that fills in a
// second, and its line. 260 x 168 pt: line 18 + gap 18 + ring 88 (84 across + its 4 pt stroke) = 124, so 22 pt above
// and below; the ring clears the 64 pt icon by 10 pt. A line too long for 236 pt (the ru and uk ones with most app
// names, seen 2026-11-10: «Удерживать ⌘Q,…ить Калькулятор») goes on two lines and the sign grows by the second one;
// only a name too long even for two lines is cut at its end. It takes no clicks and never becomes key.
@MainActor final class HUD {
    let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 168), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
    let icon = NSImageView(frame: NSRect(x: 98, y: 70, width: 64, height: 64))
    let label = NSTextField(labelWithString: "")
    let ring = CAShapeLayer(), track = CAShapeLayer(), ringHost = CALayer()

    init() {
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle, .transient]
        let blur = NSVisualEffectView(frame: panel.contentView!.bounds)
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        // Rounded through the view's mask image, Apple's way for a visual effect view: a layer corner radius left
        // the window's square corners and shadow showing (seen on macOS 26).
        blur.maskImage = NSImage(size: NSSize(width: 37, height: 37), flipped: false) { r in
            NSColor.black.setFill(); NSBezierPath(roundedRect: r, xRadius: 18, yRadius: 18).fill(); return true
        }
        blur.maskImage?.capInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        blur.maskImage?.resizingMode = .stretch
        blur.wantsLayer = true
        panel.contentView = blur

        // From twelve o'clock clockwise, like a clock hand (the layer's y axis points up). The ring lives in its own
        // 88 pt layer, so a two-line sign only moves that layer up.
        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: 44, y: 44), radius: 42, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)
        for layer in [track, ring] {
            layer.path = path
            layer.fillColor = nil
            layer.lineWidth = 4
            layer.lineCap = .round
            ringHost.addSublayer(layer)
        }
        ring.strokeEnd = 0
        blur.layer?.addSublayer(ringHost)
        blur.addSubview(icon)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.alignment = .center
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byWordWrapping
        label.cell?.truncatesLastVisibleLine = true
        blur.addSubview(label)
    }

    // start: CACurrentMediaTime() of the press. The ring and the quit timer both count from it, so the ring is
    // full exactly when the app is told to quit, never before.
    func show(_ app: NSRunningApplication, start: CFTimeInterval) {
        // The icon NSRunningApplication gives is small (32 pt) and an image view never enlarges by default.
        let image = app.icon?.copy() as? NSImage
        image?.size = NSSize(width: 64, height: 64)
        icon.image = image
        icon.imageScaling = .scaleProportionallyUpOrDown
        label.stringValue = String(format: L("Hold ⌘Q to quit %@"), app.localizedName ?? "")
        // One line takes 18 pt; when the line needs more, a second line adds the font's own line height and the
        // sign grows by it (at most two lines: maximumNumberOfLines cuts the rest).
        let one: CGFloat = 18
        let need = label.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: 236, height: 1000)).height
        let extra = need > one + 1 ? ceil(NSLayoutManager().defaultLineHeight(for: label.font!)) : 0
        panel.setContentSize(NSSize(width: 260, height: 168 + extra))
        label.frame = NSRect(x: 12, y: 22, width: 236, height: one + extra)
        icon.frame.origin.y = 70 + extra
        CATransaction.begin(); CATransaction.setDisableActions(true)
        ringHost.frame = CGRect(x: 86, y: 58 + extra, width: 88, height: 88)
        CATransaction.commit()
        // The screen with the active window, as macOS's own volume and brightness signs use.
        let screen = NSScreen.main ?? NSScreen.screens.first
        if let f = screen?.frame {
            panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.minY + f.height * 0.42 - panel.frame.height / 2))
        }
        // The label colour resolved in the sign's own appearance: resolved outside it, it came out black on the dark
        // sign of an app drawn dark (seen 2026-11-10 in a test build); the system theme happened to hide this.
        panel.contentView!.effectiveAppearance.performAsCurrentDrawingAppearance {
            ring.strokeColor = NSColor.labelColor.withAlphaComponent(0.9).cgColor
            track.strokeColor = NSColor.labelColor.withAlphaComponent(0.18).cgColor
        }
        // An empty ring before the window shows, flushed to the window server at once: otherwise the first frame of
        // a new press could show the last one's ring (seen on 26).
        ring.removeAllAnimations()
        CATransaction.begin(); CATransaction.setDisableActions(true); ring.strokeEnd = 0; CATransaction.commit()
        let fill = CABasicAnimation(keyPath: "strokeEnd")
        fill.fromValue = 0; fill.toValue = 1; fill.duration = holdTime
        fill.beginTime = ring.convertTime(start, from: nil)
        fill.fillMode = .both
        fill.isRemovedOnCompletion = false
        fill.timingFunction = CAMediaTimingFunction(name: .linear)
        ring.add(fill, forKey: "fill")
        CATransaction.flush()
        // A press during the fade of the last sign: a zero-length animation replaces that fade.
        NSAnimationContext.runAnimationGroup { c in c.duration = 0; panel.animator().alphaValue = 1 }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.invalidateShadow()
        #if TRACE
        trace("show start=\(String(format: "%.4f", start))")
        probe?.invalidate()
        let p = Timer(timeInterval: 0.004, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.panel.isVisible else { return }
                trace("ring \(String(format: "%.3f", self.ring.presentation()?.strokeEnd ?? -1)) alpha \(String(format: "%.3f", self.panel.alphaValue))")
            }
        }
        RunLoop.main.add(p, forMode: .common); probe = p
        #endif
    }
    #if TRACE
    var probe: Timer?
    #endif

    // quit: the hold reached its second and the app was told to quit; the ring shows full while the sign fades.
    // Otherwise the ring stays where it was at the release and fades from there: a full ring means only a quit.
    // (Removing the animation alone would show the layer's own value, which is why the ring once jumped to full.)
    // The window server draws a frame ahead of the app's clock, so the value at the release is up to one frame
    // behind what is already on screen: the ring would step back a little (measured on the 14 and 26 machines,
    // 0.005 and 0.017 of the circle). It stops one frame further instead, and never at full.
    func hide(quit: Bool) {
        let frame = 1.0 / Double(max(panel.screen?.maximumFramesPerSecond ?? 60, 30)) / holdTime
        let shown = quit ? 1 : min((ring.presentation()?.strokeEnd ?? 0) + frame, 0.99)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        ring.strokeEnd = shown
        ring.removeAllAnimations()
        CATransaction.commit()
        NSAnimationContext.runAnimationGroup({ c in
            // Released early: ease-in, so the stopped ring stays readable for a moment before it goes.
            c.duration = quit ? 0.15 : 0.3
            c.timingFunction = CAMediaTimingFunction(name: quit ? .easeOut : .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.panel.alphaValue == 0 else { return }
                self.panel.orderOut(nil)
            }
        })
    }
}

@MainActor final class App: NSObject, NSApplicationDelegate {
    var window: AppWindow?
    var hotKey: EventHotKeyRef?
    var key = kVK_ANSI_Q
    let hud = HUD()
    var target: NSRunningApplication?
    var timer: Timer?
    var holding = false

    func applicationDidFinishLaunching(_ n: Notification) {
        onKey = { [weak self] down in self?.key(down: down) }
        var specs = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            let down = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            DispatchQueue.main.async { onKey?(down) }
            return noErr
        }, 2, &specs, nil, nil)
        register()
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
                                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.register() }
        }
        window = AppWindow(name: "HoldQ", github: "https://github.com/geragarazagh/holdq")
    }

    func applicationShouldHandleReopen(_ a: NSApplication, hasVisibleWindows: Bool) -> Bool {
        window?.show()
        return false
    }

    func register() {
        let code = quitKeyCode()
        if hotKey != nil && code == key { return }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        key = code
        let id = EventHotKeyID(signature: OSType(0x484F_4C44), id: 1)   // 'HOLD'
        let status = RegisterEventHotKey(UInt32(code), UInt32(cmdKey), id, GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr { report("HoldQ", String(format: L("⌘Q can’t be used (error %d)"), status)) }
    }

    func key(down: Bool) {
        if down { press() } else { release(quitIfDue: false) }
    }

    func press() {
        guard !holding else { return }   // a held key may report its press again
        guard let app = NSWorkspace.shared.frontmostApplication, quits(app) else { return }
        holding = true
        target = app
        let start = CACurrentMediaTime()
        hud.show(app, start: start)
        // Every display frame (120 Hz on ProMotion): ⌘ still held, and the second is up. Tolerance 0, so the quit
        // comes at most one frame after the ring is drawn full.
        let t = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // ⌘ let go while Q stays down: a ⌘Q is no longer held.
                if !CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand) { self.release(quitIfDue: false); return }
                if CACurrentMediaTime() - start >= holdTime { self.release(quitIfDue: true) }
            }
        }
        t.tolerance = 0
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func release(quitIfDue: Bool) {
        guard holding else { return }
        #if TRACE
        trace(quitIfDue ? "quit" : "release")
        #endif
        holding = false
        timer?.invalidate(); timer = nil
        hud.hide(quit: quitIfDue)
        if quitIfDue, let target {
            if target.processIdentifier == ProcessInfo.processInfo.processIdentifier { NSApp.terminate(nil) } else { target.terminate() }
        }
        target = nil
    }

    // Whether ⌘Q would quit this app. Finder shows no Quit item unless a person turned it on.
    func quits(_ app: NSRunningApplication) -> Bool {
        if app.bundleIdentifier == "com.apple.finder" {
            return UserDefaults(suiteName: "com.apple.finder")?.bool(forKey: "QuitMenuItem") ?? false
        }
        return true
    }
}

startInBackgroundIfAtLogin()

let args = CommandLine.arguments
if args.count > 1, args[1] == "--keycode" {
    print(quitKeyCode()); exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = App()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    #if TRACE
    // Test builds: --dark draws the app dark, for pictures of every window in both themes on a machine whose
    // system theme can't be switched over ssh.
    if args.contains("--dark") { app.appearance = NSAppearance(named: .darkAqua) }
    #endif
    app.run()
}
