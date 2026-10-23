import SwiftUI

struct SizeReaderModifier<Value: Equatable>: ViewModifier {
  @Binding var value: Value
  let mapper: (CGSize) -> Value

  func body(content: Content) -> some View {
    content.onGeometryChange(for: Value.self) { proxy in
      mapper(proxy.size)
    } action: { newValue in
      value = newValue
    }
  }
}

fileprivate extension Binding {
  init<State>(
    _ object: State,
    keyPath: ReferenceWritableKeyPath<State, Value>
  ) {
    self.init(
      get: { object[keyPath: keyPath] },
      set: { object[keyPath: keyPath] = $0 }
    )
  }
}

extension View {
  func readHeight<State>(
    _ state: State,
    into keyPath: ReferenceWritableKeyPath<State, CGFloat>
  ) -> some View {
    readHeight(Binding(state, keyPath: keyPath))
  }

  func readHeight(_ value: Binding<CGFloat>) -> some View {
    modifier(SizeReaderModifier(value: value, mapper: \.height))
  }
}
