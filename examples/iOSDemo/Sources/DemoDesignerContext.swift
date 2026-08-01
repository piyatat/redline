import RedlineShared
import SwiftUI

struct DemoDesignerContext: DesignerContext {
    func pins(screen: String, region: String) -> [DesignerPin] {
        switch region {
        case "Header":
            return [DesignerPin(component: "Title", pin: "size=lg")]
        case "CTA":
            return [DesignerPin(component: "Button", pin: "color=red, fillWidth=true")]
        default:
            return []
        }
    }
}
