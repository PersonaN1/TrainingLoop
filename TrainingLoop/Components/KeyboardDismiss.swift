import SwiftUI

extension View {
    /// A "hide keyboard" button above the keyboard, and the keyboard follows a drag down the form.
    /// Number pads have no return key, and return in a multi-line note adds a line, so without it
    /// the keyboard can't be closed. Once per screen, inside its NavigationStack: two would show two buttons.
    func keyboardDismissButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Hide Keyboard", systemImage: "keyboard.chevron.compact.down") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                    to: nil, from: nil, for: nil)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }
}
