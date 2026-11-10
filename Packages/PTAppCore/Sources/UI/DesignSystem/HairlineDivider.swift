import SwiftUI
import UIKit

public struct HairlineDivider: View {
    public init() {}
    public var body: some View {
        Rectangle()
            .fill(AppColor.hairline)
            .frame(height: 1 / UIScreen.main.scale)
    }
}
