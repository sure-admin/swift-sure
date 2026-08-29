struct AccountCollectionDTO: Decodable, Equatable {
  var accounts: [AccountDTO]
  var pagination: PaginationDTO
}
