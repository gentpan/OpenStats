import Testing
@testable import Localization

@Suite(.serialized) struct LocalizationTests {
    @Test func translatesExactAndTemplates() {
        L10n.configure(.english)
        defer { L10n.configure(.chinese) }
        #expect(tr("内存") == "Memory")
        #expect(tr("12 个进程") == "12 processes")
        #expect(tr("OpenStats") == "OpenStats")
        L10n.configure(.chinese)
        #expect(tr("内存") == "内存")
    }

    @Test func resolvesSystemLanguage() {
        #expect(AppLanguage.chinese.resolved == .chinese)
        #expect(AppLanguage.english.resolved == .english)
    }
}
