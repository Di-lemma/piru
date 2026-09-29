// The module's resources as files. Skip packages them as APK assets under
// piru/module/Resources, which no file API opens, while the shared code hands resource URLs
// to GRDB (the substance catalog) and to Data(contentsOf:). substitutions.txt points
// `Bundle.main.url(forResource:withExtension:)` here.

#if os(Android)
    import AndroidAssetManager
    import Foundation
    import SkipAndroidBridge
    import SkipBridge
    @preconcurrency import SwiftJNI

    nonisolated enum AndroidResources {
        /// The module's resource bundle, backed by the APK assets. SwiftPM's generated
        /// `Bundle.module` builds a Darwin-style `.bundle` URL that no Android bundle answers;
        /// Skip's path initializer maps `<main bundle>/<package>_Piru.resources` to the module.
        static let bundle: Bundle = AndroidBundle(
            path: AndroidBundle.main.bundlePath + "/piru-android_Piru.resources", moduleName: "Piru",
        ) {
            try! AnyDynamicObject(className: "piru.module._ModuleBundleAccessor_Piru").moduleBundle!
        } ?? .main

        /// Where Skip puts the module's resources, and the folders stage.py copies whole (on iOS
        /// their files sit at the bundle root).
        private static let assetDirectory = "piru/module/Resources"
        private static let subdirectories = ["", "Licenses/"]

        /// The resource copied into Caches/Resources on first use.
        static func url(forResource name: String?, withExtension ext: String?) -> URL? {
            guard let name, let manager = assetManager else { return nil }
            let file = ext.map { "\(name).\($0)" } ?? name
            guard let asset = subdirectories.lazy.compactMap({
                manager.open(from: "\(assetDirectory)/\($0)\(file)", mode: .streaming)
            }).first else { return nil }
            defer { asset.close() }
            let destination = copiedResources.appendingPathComponent(file)
            if !FileManager.default.fileExists(atPath: destination.path) {
                guard let data = asset.read() else { return nil }
                try? FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(), withIntermediateDirectories: true,
                )
                guard (try? data.write(to: destination, options: .atomic)) != nil else { return nil }
            }
            return destination
        }

        /// Caches/Resources, emptied whenever the APK's resources differ from the ones copied
        /// out: `PiruResourceStamp` hashes every staged resource, so a rebuilt catalog of the
        /// same size still replaces the old copy.
        private static let copiedResources: URL = {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            let folder = caches.appendingPathComponent("Resources", isDirectory: true)
            let stampFile = folder.appendingPathComponent(".stamp")
            let stamp = AndroidInfoPlist.object(forInfoDictionaryKey: "PiruResourceStamp") as? String ?? ""
            if (try? String(contentsOf: stampFile, encoding: .utf8)) != stamp {
                try? FileManager.default.removeItem(at: folder)
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try? stamp.write(to: stampFile, atomically: true, encoding: .utf8)
            }
            return folder
        }()

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
