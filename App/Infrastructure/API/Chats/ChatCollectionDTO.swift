struct ChatCollectionDTO: Decodable {
  var chats: [ChatSummaryDTO]
  var pagination: PaginationDTO
}
