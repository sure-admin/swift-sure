enum ConnectionPresentation: String, Identifiable {
  case settings, signIn
  var id: Self { self }
}
