import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Waveform — десктопный клиент: задаём комфортный размер и минимум,
    // чтобы лента и сайдбар не сжимались в overflow.
    self.setContentSize(NSSize(width: 1180, height: 760))
    self.minSize = NSSize(width: 920, height: 600)

    // Убираем нативную серую шапку: тёмный UI идёт до самого верха окна.
    // «Светофор» (close/min/zoom) остаётся; заголовок и фон титлбара скрыты.
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = true

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
