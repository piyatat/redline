import RedlineShared
import SwiftUI

struct DemoDesignerContext: DesignerContext {
    func pins(screen: String, region: String) -> [DesignerPin] {
        switch region {
        case "Header":
            return [DesignerPin(component: "Title", pin: "size=lg")]
        case "Hero":
            return [DesignerPin(component: "Card", pin: "elevation=2")]
        case "CTA":
            return [DesignerPin(component: "Button", pin: "color=red, fillWidth=true")]
        default:
            return []
        }
    }
}
