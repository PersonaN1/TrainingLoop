import SwiftData
import SwiftUI

/// iOS-style bulk delete for a list: Select / Done, Select All, Delete (N) with confirmation.
struct SelectionToolbar: ViewModifier {
    @Binding var editMode: EditMode
    @Binding var selection: Set<PersistentIdentifier>
    let allIDs: [PersistentIdentifier]
    let confirmationTitle: (Int) -> Text
    let delete: (Set<PersistentIdentifier>) -> Void

    @State private var confirmingSelection = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                // Select All takes the place of Select, next to Done, instead of jumping to the left.
                if editMode.isEditing {
                    ToolbarItem(placement: .topBarTrailing) {
                        let allSelected = !allIDs.isEmpty && selection.count == allIDs.count
                        Button(allSelected ? "Deselect All" : "Select All") {
                            selection = allSelected ? [] : Set(allIDs)
                        }
                    }
                    // iOS 26 would merge both into one glass capsule.
                    if #available(iOS 26, *) {
                        ToolbarSpacer(.fixed, placement: .topBarTrailing)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editMode.isEditing ? "Done" : "Select") { setEditing(!editMode.isEditing) }
                        .disabled(allIDs.isEmpty && !editMode.isEditing)
                }
                if editMode.isEditing {
                    ToolbarItem(placement: .bottomBar) {
                        Button(role: .destructive) {
                            confirmingSelection = true
                        } label: {
                            Text("Delete (\(selection.count))")
                        }
                        .disabled(selection.isEmpty)
                        // Its own dialog, so the iOS 26+ popover points at this button.
                        .confirmationDialog(confirmationTitle(selection.count), isPresented: $confirmingSelection,
                                            titleVisibility: .visible) {
                            Button("Delete", role: .destructive) { confirmDelete(selection) }
                        }
                    }
                }
            }
            // As in Files and Photos: the tab bar gives way to the selection actions.
            .toolbar(editMode.isEditing ? .hidden : .automatic, for: .tabBar)
            .onChange(of: allIDs) { selection.formIntersection($1) }
            // Set last so the list and everything around it share one edit mode.
            .environment(\.editMode, $editMode)
    }

    private func confirmDelete(_ ids: Set<PersistentIdentifier>) {
        delete(ids)
        selection.subtract(ids)
        if allIDs.count == ids.count { setEditing(false) }
    }

    private func setEditing(_ editing: Bool) {
        withAnimation {
            editMode = editing ? .active : .inactive
            selection = []
        }
    }
}

extension View {
    func selectionToolbar(
        editMode: Binding<EditMode>,
        selection: Binding<Set<PersistentIdentifier>>,
        allIDs: [PersistentIdentifier],
        confirmationTitle: @escaping (Int) -> Text,
        delete: @escaping (Set<PersistentIdentifier>) -> Void
    ) -> some View {
        modifier(SelectionToolbar(
            editMode: editMode, selection: selection,
            allIDs: allIDs, confirmationTitle: confirmationTitle, delete: delete
        ))
    }
}

extension ModelContext {
    func delete(ids: Set<PersistentIdentifier>) {
        for id in ids { delete(model(for: id)) }
        saveOrReport()
    }
}
