//  TodoBoardColumnView.swift
//  ProWork
//  Created by Pronomi.
import SwiftUI
import UniformTypeIdentifiers

struct TodoBoardColumnView: View {
    let status: TodoStatus
    let todos: [TodoListItem]
    let onEdit: (TodoListItem) -> Void
    let onShowSessions: (TodoListItem) -> Void
    let onStartWork: (TodoListItem) -> Void
    let onStopWork: (TodoListItem) -> Void
    let onDelete: (TodoListItem) -> Void
    let onMoveTodo: (TodoListItem, TodoStatus) -> Void

    @State private var isDropTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(todos) { todo in
                        TodoBoardCardView(
                            todo: todo,
                            onEdit: {
                                onEdit(todo)
                            },
                            onShowSessions: {
                                onShowSessions(todo)
                            },
                            onStartWork: {
                                onStartWork(todo)
                            },
                            onStopWork: {
                                onStopWork(todo)
                            },
                            onDelete: {
                                onDelete(todo)
                            }
                        )
                        .transition(.scale(scale: 0.98).combined(with: .opacity))
                        .onDrag {
                            // NSItemProvider's
                            // `init(object:)` takes a legacy
                            // NSItemProviderWriting type. Wrap the
                            // String id in a public UTF-8 plain-text
                            // representation explicitly so future
                            // drop handlers (or external apps in
                            // SwiftUI 16+) get a clean type
                            // identifier instead of the
                            // NSString-bridged "binary plist"
                            // payload the legacy bridge produces.
                            let provider = NSItemProvider()
                            let identifier = todo.id
                            provider.registerDataRepresentation(
                                forTypeIdentifier: "public.utf8-plain-text",
                                visibility: .all
                            ) { completion in
                                completion(Data(identifier.utf8), nil)
                                return nil
                            }
                            return provider
                        }
                    }
                }
                .padding(.bottom, 8)
                .proWorkFrame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(12)
        .proWorkFrame(width: 280)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(isDropTarget ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.quaternary.opacity(0.25)))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    isDropTarget ? Color.accentColor : Color.secondary.opacity(0.18),
                    lineWidth: isDropTarget ? 2 : 1
                )
        )
        .onDrop(
            of: [UTType.text],
            isTargeted: $isDropTarget
        ) { providers in
            handleDrop(providers)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(ProWorkColors.fromName(status.color))
                .proWorkFrame(width: 10, height: 10)

            Text(status.name)
                .proWorkTextStyle(.headline)
                .lineLimit(1)

            Spacer()

            Text("\(todos.count)")
                .proWorkTextStyle(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.background.opacity(0.8))
                .clipShape(Capsule())
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
            let todoId: String?

            if let data = item as? Data {
                todoId = String(data: data, encoding: .utf8)
            } else if let string = item as? String {
                todoId = string
            } else if let nsString = item as? NSString {
                todoId = nsString as String
            } else {
                todoId = nil
            }

            guard let todoId else {
                return
            }

            DispatchQueue.main.async {
                onMoveTodo(
                    TodoListItem.placeholder(id: todoId),
                    status
                )
            }
        }

        return true
    }
}

private extension TodoListItem {
    /// Factory accepts a `referenceDate` (defaults to a
    /// constant epoch) instead of capturing `Date()` at call time. The
    /// placeholder is a transient drag-state stand-in; using "now" as
    /// the timestamp made it look like a brand-new row to anything
    /// downstream that sorted by createdAt and accidentally re-renders
    /// kept producing non-equal placeholder values for the same `id`.
    /// `Date(timeIntervalSince1970: 0)` is intentionally distinct from
    /// real persisted rows so a leaked placeholder is obvious.
    static func placeholder(id: String, referenceDate: Date = Date(timeIntervalSince1970: 0)) -> TodoListItem {
        TodoListItem(
            id: id,
            customerId: nil,
            customerName: nil,
            projectId: nil,
            projectName: nil,
            categoryId: "",
            categoryName: "",
            categoryColor: nil,
            statusId: "",
            statusName: "",
            statusColor: nil,
            statusStartsTimer: false,
            statusStopsTimer: false,
            statusMarksOpen: true,
            statusMarksCompleted: false,
            statusMarksCancelled: false,
            title: "",
            description: nil,
            priority: "normal",
            plannedDate: nil,
            dueDate: nil,
            estimatedMinutes: nil,
            totalTrackedSeconds: 0,
            activeSessionStartedAt: nil,
            isBillable: true,
            createdAt: referenceDate,
            updatedAt: referenceDate,
            completedAt: nil
        )
    }
}
