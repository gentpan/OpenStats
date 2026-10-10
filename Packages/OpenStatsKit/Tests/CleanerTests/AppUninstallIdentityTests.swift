import Foundation
import Testing
@testable import Cleaner

@Suite struct AppUninstallIdentityTests {
    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("uninstall-identity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.resolvingSymlinksInPath()
    }

    private func makeBundle(at url: URL, identifier: String, name: String, displayName: String? = nil, executable: String? = nil) throws {
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var plist: [String: Any] = ["CFBundleIdentifier": identifier, "CFBundleName": name]
        if let displayName { plist["CFBundleDisplayName"] = displayName }
        if let executable { plist["CFBundleExecutable"] = executable }
        // 未签名的 Info.plist 中宣称的 entitlement 不能用来选择共享容器。
        plist["com.apple.security.application-groups"] = ["group.untrusted.plist"]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }

    private func app(at url: URL, identifier: String = "com.example.foo", name: String = "Displayed App") -> InstalledApp {
        InstalledApp(url: url, name: name, bundleIdentifier: identifier, version: nil, teamIdentifier: nil)
    }

    @Test func readsMainBundleNamesAndEmbeddedIdentifiersWithoutHelperNames() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("File Name.app")
        try makeBundle(at: root, identifier: "com.example.foo", name: "Sentry Name", displayName: "Localized Name", executable: "Main Process")
        let bundles = [
            ("Contents/Frameworks/Widget.framework/Versions/A/Helpers/Worker.app", "com.example.worker", "CrashHandler"),
            ("Contents/XPCServices/Service.xpc", "com.example.service", "Service"),
            ("Contents/PlugIns/Extension.appex", "com.example.extension", "Extension"),
            ("Contents/Library/LoginItems/Launcher.app", "com.vendor.loginlauncher", "Login Helper"),
        ]
        for (path, identifier, name) in bundles {
            try makeBundle(at: root.appendingPathComponent(path), identifier: identifier, name: name)
        }
        // 扫描根之外的普通资源 bundle 不作为嵌套应用身份。
        try makeBundle(at: root.appendingPathComponent("Contents/Resources/Other.app"), identifier: "com.other.resource", name: "Other")

        let identity = AppUninstallIdentity(app: app(at: root))
        #expect(identity.identifiers == ["com.example.foo", "com.example.worker", "com.example.service", "com.example.extension", "com.vendor.loginlauncher"])
        #expect(identity.names == ["Displayed App", "File Name", "Sentry Name", "Localized Name", "Main Process"])
        #expect(identity.matchesName("main-process"))
        #expect(!identity.matchesName("login-helper"))
        #expect(identity.applicationGroups.isEmpty)
        #expect(identity.teamIdentifier == nil)
    }

    @Test func filtersUnsafeMetadataAndInjectedIdentities() {
        let identity = AppUninstallIdentity(
            identifiers: ["com.example.foo", "com", "org", "group", "", ".", "..", ".com.foo", "com..foo", "com.foo/other", "com.foo\\other", "com.foo\n"],
            names: [" Foo ", "中文应用", "", " ", ".", "..", "../Other", "a/b", "a\\b", "Bad\0Name", "Bad\n"],
            applicationGroups: ["group.com.example.foo", "com", "org", "group", "", ".", "../outside", "group.*"],
            teamIdentifier: "TEAM/OTHER")
        #expect(identity.identifiers == ["com.example.foo"])
        #expect(identity.names == ["Foo", "中文应用"])
        #expect(identity.applicationGroups == ["group.com.example.foo"])
        #expect(identity.teamIdentifier == nil)
        let groups = AppUninstallIdentity.applicationGroups(from: [
            "com.apple.security.application-groups": ["TEAM123.com.example.shared", "group.com.example.foo", "../outside", "group.*", 42] as [Any],
            "com.apple.developer.icloud-container-identifiers": ["iCloud.com.example.foo"],
            "keychain-access-groups": ["TEAM123.*"],
        ])
        #expect(groups == ["TEAM123.com.example.shared", "group.com.example.foo"])
    }

    @Test func refusesSymlinkBundlesDirectoriesAndMetadata() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("Foo.app")
        let outside = directory.appendingPathComponent("Outside.app")
        try makeBundle(at: root, identifier: "com.example.foo", name: "Foo")
        try makeBundle(at: outside, identifier: "com.other.outside", name: "Outside")
        let manager = FileManager.default
        let frameworks = root.appendingPathComponent("Contents/Frameworks")
        try manager.createDirectory(at: frameworks, withIntermediateDirectories: true)
        try manager.createSymbolicLink(at: frameworks.appendingPathComponent("Linked.app"), withDestinationURL: outside)

        let externalServices = directory.appendingPathComponent("ExternalServices")
        try makeBundle(at: externalServices.appendingPathComponent("Other.xpc"), identifier: "com.other.service", name: "Other")
        try manager.createSymbolicLink(at: root.appendingPathComponent("Contents/XPCServices"), withDestinationURL: externalServices)

        let externalLoginItems = directory.appendingPathComponent("ExternalLoginItems")
        try makeBundle(at: externalLoginItems.appendingPathComponent("Launcher.app"), identifier: "com.other.launcher", name: "Launcher")
        try manager.createDirectory(at: root.appendingPathComponent("Contents/Library"), withIntermediateDirectories: true)
        try manager.createSymbolicLink(at: root.appendingPathComponent("Contents/Library/LoginItems"), withDestinationURL: externalLoginItems)

        let linkedMetadata = root.appendingPathComponent("Contents/PlugIns/Linked.appex/Contents")
        try manager.createDirectory(at: linkedMetadata, withIntermediateDirectories: true)
        try manager.createSymbolicLink(at: linkedMetadata.appendingPathComponent("Info.plist"),
                                      withDestinationURL: outside.appendingPathComponent("Contents/Info.plist"))
        let identity = AppUninstallIdentity(app: app(at: root, name: "Foo"))
        #expect(identity.identifiers == ["com.example.foo"])
        #expect(identity.names == ["Foo"])
        #expect(AppUninstallIdentity.embeddedBundles(in: root).isEmpty)
        #expect(!AppUninstallIdentity.isSafeURL(outside, inside: root))
        #expect(!AppUninstallIdentity.isSafeURL(frameworks.appendingPathComponent("Linked.app"), inside: root))
    }

    @Test func recognizesWholeNameFormatsWithoutDroppingChannelsOrProductBoundaries() {
        let identity = AppUninstallIdentity(identifiers: ["com.example.studio"], names: ["Maestro Studio", "Zed Nightly", "QQ", "微信"])

        for name in ["Maestro Studio", "maestro studio", "MAESTROSTUDIO", "maestro-studio", "Maestro_Studio"] {
            #expect(identity.matchesName(name))
        }
        #expect(identity.matchesName("zed-nightly"))
        #expect(!identity.matchesName("Zed"))
        #expect(!identity.matchesName("Maestro Studio Beta"))
        #expect(!identity.matchesName("MaestroStudioOther"))
        #expect(identity.matchesName("QQ"))
        #expect(identity.matchesName("微信"))
        #expect(!identity.matchesName("../Maestro Studio"))
    }

    @Test func reportNamesRequireACompleteProductNameOrAnExplicitBoundary() {
        let identity = AppUninstallIdentity(identifiers: ["com.example.foo"], names: ["Foo App"])

        #expect(identity.matchesReportName("Foo App"))
        #expect(identity.matchesReportName("FooApp_12345678-1234-1234-1234-123456789ABC"))
        #expect(identity.matchesReportName("FOO-APP-2026-10-10"))
        #expect(!identity.matchesReportName("FooApplication_2026-10-10"))
        #expect(!identity.matchesReportName("Foo AppOther_2026-10-10"))
        #expect(!identity.matchesReportName("Other Foo App_2026-10-10"))
        #expect(!identity.matchesReportName("Foo App/Outside"))
    }

    @Test func rejectsGenericRuntimeAndSharedRootNamesBeforeGeneratingVariants() {
        let identity = AppUninstallIdentity(identifiers: ["com.example.foo"],
            names: ["A", "X", "Helper", "Runner", "Electron", "Electron Helper", "Application Support", "Group Containers", "Code", "Foo"])

        #expect(identity.nameVariants == ["foo"])
        #expect(!identity.matchesReportName("Helper_1234"))
        #expect(!identity.matchesName("electronhelper"))
        #expect(!identity.matchesName("application-support"))
        #expect(AppUninstallIdentity.safeNameVariants(for: "crash-handler").isEmpty)
        #expect(AppUninstallIdentity.safeNameVariants(for: "../Outside").isEmpty)
        #expect(AppUninstallIdentity.safeNameVariants(for: "Foo\nBar").isEmpty)
    }

    @Test func mainExecutableNamesRejectPathsAndGenericProcessNames() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("Foo.app")
        try makeBundle(at: root, identifier: "com.example.foo", name: "Foo", executable: "../Outside")
        #expect(!AppUninstallIdentity(app: app(at: root, name: "Foo")).names.contains("../Outside"))

        try makeBundle(at: root, identifier: "com.example.foo", name: "Foo", executable: "Electron")
        let identity = AppUninstallIdentity(app: app(at: root, name: "Foo"))
        #expect(identity.names.contains("Electron"))
        #expect(!identity.matchesName("electron"))
        #expect(identity.matchesName("Foo"))
    }

    @Test func readsLowercaseBundleMetadataAndLoginItemsOnCaseInsensitiveVolumes() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("Foo.app")
        let contents = root.appendingPathComponent("contents")
        let loginHelper = contents.appendingPathComponent("library/loginitems/Startup.app")
        let helperContents = loginHelper.appendingPathComponent("contents")
        try FileManager.default.createDirectory(at: helperContents, withIntermediateDirectories: true)
        let metadata: [String: Any] = [
            "CFBundleIdentifier": "com.example.foo",
            "CFBundleName": "Product Name",
            "CFBundleExecutable": "Main Product",
        ]
        try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("info.plist"))
        try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleIdentifier": "com.vendor.startup",
            "CFBundleName": "Shared Helper",
        ], format: .xml, options: 0).write(to: helperContents.appendingPathComponent("info.plist"))
        let usualMetadataPath = root.appendingPathComponent("Contents/Info.plist")
        // 此回归针对 macOS 默认大小写不敏感卷；其他卷没有这个等价路径。
        guard FileManager.default.fileExists(atPath: usualMetadataPath.path) else { return }

        let identity = AppUninstallIdentity(app: app(at: root, name: "Foo"))

        #expect(AppUninstallIdentity.isSafeURL(usualMetadataPath, inside: root))
        #expect(identity.identifiers == ["com.example.foo", "com.vendor.startup"])
        #expect(identity.names.contains("Product Name"))
        #expect(identity.matchesName("main-product"))
        #expect(!identity.names.contains("Shared Helper"))
    }

    @Test func refusesLinkedMainBundleButPreservesSuppliedBasicIdentity() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outside = directory.appendingPathComponent("Outside.app")
        let linked = directory.appendingPathComponent("Linked.app")
        try makeBundle(at: outside, identifier: "com.other.outside", name: "Outside")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: outside)
        let identity = AppUninstallIdentity(app: app(at: linked, name: "Displayed App"))
        #expect(identity.identifiers == ["com.example.foo"])
        #expect(identity.names == ["Displayed App", "Linked"])
        #expect(identity.applicationGroups.isEmpty)
    }

    @Test func boundsTraversalDepth() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("Foo.app")
        try makeBundle(at: root, identifier: "com.example.foo", name: "Foo")
        let nestedPath = "Contents/Frameworks/" + Array(repeating: "level", count: 12).joined(separator: "/") + "/Deep.app"
        try makeBundle(at: root.appendingPathComponent(nestedPath), identifier: "com.other.deep", name: "Deep")
        #expect(AppUninstallIdentity(app: app(at: root)).identifiers == ["com.example.foo"])
    }

    @Test func readsSignedGroupsAndRejectsThemAfterSignatureIsBroken() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("Signed Fixture.app")
        let macos = root.appendingPathComponent("Contents/MacOS")
        let executable = macos.appendingPathComponent("Fixture")
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        // 写入副本字节，避免把系统二进制的受保护文件标记复制到测试目录。
        try Data(contentsOf: URL(fileURLWithPath: "/usr/bin/true")).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let plistURL = root.appendingPathComponent("Contents/Info.plist")
        var metadata: [String: Any] = [
            "CFBundleIdentifier": "com.example.signaturefixture",
            "CFBundleName": "Signed Fixture",
            "CFBundlePackageType": "APPL",
            "CFBundleExecutable": "Fixture",
            "CFBundleVersion": "1",
        ]
        try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0).write(to: plistURL)
        let entitlements = directory.appendingPathComponent("entitlements.plist")
        try PropertyListSerialization.data(fromPropertyList: [
            "com.apple.security.application-groups": ["group.com.example.signaturefixture"],
        ], format: .xml, options: 0).write(to: entitlements)

        // 只给临时 bundle 重新签名；无需证书、网络或运行这个二进制。
        let signer = Process()
        let diagnostics = Pipe()
        signer.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        signer.arguments = ["--force", "--sign", "-", "--timestamp=none", "--entitlements", entitlements.path, root.path]
        signer.standardOutput = FileHandle.nullDevice
        signer.standardError = diagnostics
        try signer.run()
        let output = String(decoding: diagnostics.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        signer.waitUntilExit()
        try #require(signer.terminationStatus == 0, "codesign failed: \(output)")

        let fixture = app(at: root, identifier: "com.example.signaturefixture", name: "Signed Fixture")
        let signed = AppUninstallIdentity(app: fixture)
        #expect(signed.applicationGroups == ["group.com.example.signaturefixture"])
        #expect(signed.teamIdentifier == nil) // ad-hoc 签名没有开发团队。

        // 保持 plist 格式有效，只改签名覆盖的内容，确保不会接受失效签名中的 group。
        metadata["CFBundleName"] = "Changed Fixture"
        try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0).write(to: plistURL)
        let broken = AppUninstallIdentity(app: fixture)
        #expect(broken.applicationGroups.isEmpty)
        #expect(broken.identifiers == ["com.example.signaturefixture"])
        #expect(broken.names.contains("Changed Fixture"))
    }
}
