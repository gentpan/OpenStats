import SwiftUI

// MARK: - 全局加载

/// 需要等待、期间不宜继续操作的任务（清理、卸载、导出诊断、修改 DNS）：
/// 整个窗口压暗，中间浮一块加载框，写明正在做什么；任务结束自动消失
struct LoadingHUD: View {
    let message: String

    var body: some View {
        ZStack {
            // 压暗并拦住点击，避免任务进行中又触发别的操作
            Rectangle()
                .fill(DS.Palette.scrim)
                .contentShape(Rectangle())
                .onTapGesture {}

            HStack(spacing: DS.Space.s3) {
                ProgressView().controlSize(.regular)
                Text(verbatim: message)
                    .dsFont(.base, weight: .medium)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, DS.Space.s8)
            .padding(.vertical, DS.Space.s6)
            .frame(minWidth: DS.Size.sidebarWidth + DS.Space.s16)
            .background {
                // 先垫一层不透明的页面底色：深色磨砂里 elevated 是半透明的，单独用会透出后面的页面
                let shape = RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                shape.fill(DS.Palette.background)
                shape.fill(DS.Palette.elevated)
            }
            .dsShadow(DS.Shadow.level2)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
        }
        .transition(.opacity)
    }
}

extension View {
    /// 有文字时在上方盖一层全局加载框
    func loadingHUD(_ message: String?) -> some View {
        overlay {
            if let message { LoadingHUD(message: message) }
        }
        .animation(DS.Motion.quick, value: message)
    }
}
