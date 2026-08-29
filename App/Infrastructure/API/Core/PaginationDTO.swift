struct PaginationDTO: Decodable, Equatable {
  var page: Int
  var perPage: Int
  var totalCount: Int
  var totalPages: Int

  enum CodingKeys: String, CodingKey {
    case page
    case perPage = "per_page"
    case totalCount = "total_count"
    case totalPages = "total_pages"
  }
}
