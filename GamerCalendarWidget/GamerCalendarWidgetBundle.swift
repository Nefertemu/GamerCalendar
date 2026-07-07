
import WidgetKit
import SwiftUI

@main
struct GamerCalendarWidgetBundle: WidgetBundle {
    var body: some Widget {
        GamerCalendarWidget()
        if #available(iOS 16.2, *) {
            ReleaseLiveActivity()
        }
    }
}
