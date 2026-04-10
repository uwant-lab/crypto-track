import SwiftUI

struct InlineNavigationTitle: ViewModifier {
    func body(content: Content) -> some View {
        content
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

extension View {
    func inlineNavigationTitle() -> some View {
        modifier(InlineNavigationTitle())
    }
}
