import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "QuestopiaAudio") {
      QuestopiaAudioPlugin.register(with: registrar)
    }
  }
}

/// Minimal AVAudioPlayer bridge for the QSP sound engine.
///
/// audioplayers leaves the shared audio session inactive until a sound
/// completes, which can make a freshly started game silent. This bridge
/// activates a `.playback` session on the first sound, so MP3 playback works
/// regardless of the ring/silent switch, and keeps one player per path like the
/// Android implementation.
final class QuestopiaAudioPlugin: NSObject, FlutterPlugin, AVAudioPlayerDelegate {
  private var players: [String: AVAudioPlayer] = [:]

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "questopia/audio",
      binaryMessenger: registrar.messenger()
    )
    let instance = QuestopiaAudioPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]

    switch call.method {
    case "play":
      guard let path = args["path"] as? String else {
        result(FlutterError(code: "bad_args", message: "path missing", details: nil))
        return
      }
      let volume = (args["volume"] as? NSNumber)?.doubleValue ?? 1.0
      result(play(path: path, volume: volume))
    case "pause":
      if let path = args["path"] as? String {
        players[path]?.pause()
      }
      result(nil)
    case "resume":
      if let path = args["path"] as? String {
        activateSession()
        players[path]?.play()
      }
      result(nil)
    case "stop", "dispose":
      if let path = args["path"] as? String {
        players[path]?.stop()
        players.removeValue(forKey: path)
      }
      result(nil)
    case "setVolume":
      if let path = args["path"] as? String {
        let volume = (args["volume"] as? NSNumber)?.doubleValue ?? 1.0
        players[path]?.volume = Float(volume)
      }
      result(nil)
    case "stopAll":
      for player in players.values {
        player.stop()
      }
      players.removeAll()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func play(path: String, volume: Double) -> Bool {
    guard FileManager.default.fileExists(atPath: path) else {
      NSLog("[QuestopiaAudio] missing file: %@", path)
      return false
    }

    activateSession()

    if let player = players[path] {
      player.volume = Float(volume)
      if !player.isPlaying {
        player.play()
      }
      return true
    }

    do {
      let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
      player.delegate = self
      player.volume = Float(volume)
      player.numberOfLoops = 0
      player.prepareToPlay()
      players[path] = player
      let started = player.play()
      if !started {
        NSLog("[QuestopiaAudio] failed to start: %@", path)
        players.removeValue(forKey: path)
      }
      return started
    } catch {
      NSLog("[QuestopiaAudio] cannot open %@: %@", path, String(describing: error))
      return false
    }
  }

  private func activateSession() {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
      try session.setActive(true, options: [])
    } catch {
      NSLog("[QuestopiaAudio] audio session error: %@", String(describing: error))
    }
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    if let key = players.first(where: { $0.value === player })?.key {
      players.removeValue(forKey: key)
    }
  }
}
