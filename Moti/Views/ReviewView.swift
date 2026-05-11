import SwiftData
import SwiftUI

struct ReviewView: View {
    @Query(sort: \WorkItem.createdAt, order: .reverse) private var workItems: [WorkItem]

    private var reviewItems: [WorkItem] {
        workItems.filter(\.needsReview)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(reviewItems) { item in
                    NavigationLink {
                        WorkItemDetailView(item: item)
                    } label: {
                        WorkItemCard(item: item, showRawInput: true)
                    }
                }
            }
            .overlay {
                if reviewItems.isEmpty {
                    ContentUnavailableView("Nothing needs review", systemImage: "tray", description: Text("Ambiguous captures will wait here until they have timing."))
                }
            }
            .navigationTitle("Review")
        }
    }
}
