
import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

    private let uwbManager = UWBManager()

    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        return super.application(
            application,
            didFinishLaunchingWithOptions: launchOptions
        )
    }

    func didInitializeImplicitFlutterEngine(
        _ engineBridge: FlutterImplicitEngineBridge
    ) {
        GeneratedPluginRegistrant.register(
            with: engineBridge.pluginRegistry
        )

        let messenger = engineBridge.applicationRegistrar.messenger()

        let methods = FlutterMethodChannel(
            name: "uwb_locator/methods",
            binaryMessenger: messenger
        )

        let events = FlutterEventChannel(
            name: "uwb_locator/events",
            binaryMessenger: messenger
        )

        methodChannel = methods
        eventChannel = events

        events.setStreamHandler(uwbManager)

        methods.setMethodCallHandler { [weak self] call, result in
            guard let self else {
                result(
                    FlutterError(
                        code: "UNAVAILABLE",
                        message: "UWB manager unavailable",
                        details: nil
                    )
                )
                return
            }

            switch call.method {

            case "startDiscovery":
                self.uwbManager.startDiscovery()
                result(nil)

            case "stopDiscovery":
                self.uwbManager.stopDiscovery()
                result(nil)

            case "connect":
                guard
                    let arguments = call.arguments as? [String: Any],
                    let peerId = arguments["peerId"] as? String
                else {
                    result(
                        FlutterError(
                            code: "INVALID_ARGUMENT",
                            message: "peerId is required",
                            details: nil
                        )
                    )
                    return
                }

                self.uwbManager.connect(to: peerId)
                result(nil)

            case "disconnect":
                self.uwbManager.disconnect()
                result(nil)

            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
}
