// The module's resources as files. Skip packages them as APK assets under
// piru/module/Resources, which no file API opens, while the shared code hands resource URLs
// to GRDB (the substance catalog) and to Data(contentsOf:). substitutions.txt points
// `Bundle.main.url(forResource:withExtension:)` here.

#if os(Android)
    import AndroidAssetManager
    import Foundation
    import SkipAndroidBridge
    @preconcurrency import SwiftJNI

    nonisolated enum AndroidResources {
        /// Where Skip puts the module's resources, and the folders stage.py copies whole (on iOS
        /// their files sit at the bundle root).
        private static let assetDirectory = "piru/module/Resources"
        private static let subdirectories = ["", "Licenses/"]

        /// The resource copied into Caches/Resources, refreshed whenever this build's copy
        /// differs in size from the one on disk.
        static func url(forResource name: String?, withExtension ext: String?) -> URL? {
            guard let name, let manager = assetManager else { return nil }
            let file = ext.map { "\(name).\($0)" } ?? name
            guard let asset = subdirectories.lazy.compactMap({
                manager.open(from: "\(assetDirectory)/\($0)\(file)", mode: .streaming)
            }).first else { return nil }
            defer { asset.close() }
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            let destination = caches.appendingPathComponent("Resources/\(file)")
            let onDisk = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int) ?? -1
            if onDisk != Int(asset.length) {
                guard let data = asset.read() else { return nil }
                try? FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                guard (try? data.write(to: destination, options: .atomic)) != nil else { return nil }
            }
            return destination
        }

        private static let assetManager: AndroidAssetManager? = {
            let context = ProcessInfo.processInfo.dynamicAndroidContext()
            guard let contextObject = context.toJavaObject(options: []),
                  let contextClass = try? JClass(name: "android/content/Context"),
                  let getResources = contextClass.getMethodID(name: "getResources", sig: "()Landroid/content/res/Resources;"),
                  let resources: JavaObjectPointer = try? JObject(contextObject).call(method: getResources, options: [], args: []),
                  let resourcesClass = try? JClass(name: "android/content/res/Resources"),
                  let getAssets = resourcesClass.getMethodID(name: "getAssets", sig: "()Landroid/content/res/AssetManager;"),
                  let assets: JavaObjectPointer = try? JObject(resources).call(method: getAssets, options: [], args: [])
            else { return nil }
            return JNI.jni.withEnv { _, env in AndroidAssetManager(env: env, peer: assets) }
        }()
    }
#endif
