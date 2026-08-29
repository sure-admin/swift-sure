struct CurrencyCode: Hashable, Sendable {
  let rawValue: String

  init?(_ value: String) {
    let normalized = value.uppercased()
    guard Self.supportedCurrencies.contains(normalized) else {
      return nil
    }
    rawValue = normalized
  }

  var minorUnitConversion: Int64 {
    if Self.unitCurrencies.contains(rawValue) { return 1 }
    if Self.fiveToOneCurrencies.contains(rawValue) { return 5 }
    if Self.thousandToOneCurrencies.contains(rawValue) { return 1_000 }
    if rawValue == "CLF" { return 10_000 }
    if Self.hundredMillionToOneCurrencies.contains(rawValue) { return 100_000_000 }
    return 100
  }

  var minorUnitDigits: Int {
    switch minorUnitConversion {
    case 1: 0
    case 5: 1
    case 100: 2
    case 1_000: 3
    case 10_000: 4
    case 100_000_000: 8
    default: 2
    }
  }

  private static let unitCurrencies: Set<String> = [
    "BIF", "BYR", "CLP", "DJF", "GBX", "GNF", "HUF", "ISK", "JPY",
    "KMF", "KRW", "PYG", "RWF", "UGX", "VND", "VUV", "XAF", "XAG",
    "XAU", "XBA", "XBB", "XBC", "XBD", "XDR", "XOF", "XPD", "XPF",
    "XPT", "XTS"
  ]

  private static let fiveToOneCurrencies: Set<String> = ["MGA", "MRU"]

  private static let thousandToOneCurrencies: Set<String> = [
    "BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND"
  ]

  private static let hundredMillionToOneCurrencies: Set<String> = ["BTC", "DOGE"]

  // Mirrors config/currencies.yml at the pinned Sure revision. Keeping this
  // deterministic avoids rejecting server-supported crypto and regional codes
  // or assigning an invented scale to an unknown code.
  private static let supportedCurrencies = Set(
    """
    AED AFN ALL AMD ANG AOA ARS AUD AWG AZN BAM BBD BDT BGN BHD BIF BMD BND BOB BRL BSD BTC BTN BWP BYN BYR BZD CAD CDF CHF CLF CLP CNH CNY COP CRC CUC CUP CVE CZK DJF DKK DOGE DOP DZD EGP ERN ETB EUR FJD FKP GBP GBX GEL GGP GHS GIP GMD GNF GTQ GYD HKD HNL HTG HUF IDR ILS IMP INR IQD IRR ISK JEP JMD JOD JPY KES KGS KHR KMF KPW KRW KWD KYD KZT LAK LBP LKR LRD LSL LYD MAD MDL MGA MKD MMK MNT MOP MRU MUR MVR MWK MXN MYR MZN NAD NGN NIO NOK NPR NZD OMR PAB PEN PGK PHP PKR PLN PYG QAR RON RSD RUB RWF SAR SBD SCR SDG SEK SGD SHP SKK SLE SLL SOS SRD SSP STD STN SVC SYP SZL THB TJS TMT TND TOP TRY TTD TWD TZS UAH UGX USD USDC UYU UZS VES VND VUV WST XAF XAG XAU XBA XBB XBC XBD XCD XDR XFU XOF XPD XPF XPT XTS YER ZAR ZMK ZMW
    """.split(whereSeparator: \Character.isWhitespace).map(String.init)
  )
}
