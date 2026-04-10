import Foundation

// MARK: - Generic Response Wrapper

/// OKX V5 API 공통 응답 래퍼
/// 모든 OKX 응답은 {"code":"0","data":[...]} 형식을 사용합니다.
struct OKXResponse<T: Decodable>: Decodable {
    /// 응답 코드 ("0"은 성공)
    let code: String
    /// 응답 메시지
    let msg: String
    /// 응답 데이터 배열
    let data: [T]

    /// 성공 여부
    var isSuccess: Bool {
        code == "0"
    }
}

// MARK: - Balance Response

/// OKX GET /api/v5/account/balance 응답의 계좌 모델
struct OKXAccountBalance: Decodable {
    /// 보유 자산 목록
    let details: [OKXBalanceDetail]
}

/// OKX 개별 자산 잔고 모델
struct OKXBalanceDetail: Decodable {
    /// 코인 심볼 (예: "BTC", "ETH")
    let ccy: String
    /// 사용 가능 잔고
    let availBal: String
    /// 동결된 잔고
    let frozenBal: String

    /// 실제 보유 수량 (availBal + frozenBal)
    var totalBalance: Double {
        (Double(availBal) ?? 0) + (Double(frozenBal) ?? 0)
    }
}

// MARK: - Ticker Response

/// OKX GET /api/v5/market/tickers 응답의 시세 모델
struct OKXTicker: Decodable {
    /// 거래 쌍 (예: "BTC-USDT")
    let instId: String
    /// 최근 거래 가격
    let last: String
    /// 24시간 가격 변동률 (%)
    let sodUtc8: String?
    /// 24시간 거래량 (코인 기준)
    let vol24h: String

    /// 기반 코인 심볼 추출 (예: "BTC-USDT" → "BTC")
    var baseSymbol: String {
        instId.components(separatedBy: "-").first ?? instId
    }
}

// MARK: - Kline Response

/// OKX GET /api/v5/market/candles 응답 파서
/// 응답 형식: {"code":"0","data":[[ts, o, h, l, c, vol, ...], ...]}
struct OKXKlineResponse: Decodable {
    let code: String
    let msg: String
    let data: [[String]]

    var isSuccess: Bool { code == "0" }
}

extension OKXKlineResponse {
    func toKlines(symbol: String, timeframe: ChartTimeframe) -> [Kline] {
        data.compactMap { row -> Kline? in
            guard row.count >= 6,
                  let ts = Int64(row[0]),
                  let open = Double(row[1]),
                  let high = Double(row[2]),
                  let low = Double(row[3]),
                  let close = Double(row[4]),
                  let volume = Double(row[5])
            else { return nil }
            return Kline(
                id: "okx-\(symbol)-\(ts)",
                timestamp: Date(timeIntervalSince1970: Double(ts) / 1000),
                open: open,
                high: high,
                low: low,
                close: close,
                volume: volume,
                timeframe: timeframe,
                exchange: .okx,
                symbol: symbol
            )
        }
    }
}

// MARK: - Mapping Extensions

extension OKXBalanceDetail {
    /// OKXBalanceDetail → 공통 Asset 모델로 변환
    func toAsset() -> Asset {
        Asset(
            id: "okx-\(ccy.lowercased())",
            symbol: ccy,
            balance: totalBalance,
            averageBuyPrice: 0,
            exchange: .okx,
            lastUpdated: Date()
        )
    }
}

extension OKXTicker {
    /// OKXTicker → 공통 Ticker 모델로 변환
    func toTicker() -> Ticker {
        // sodUtc8은 UTC+8 기준 당일 시가 대비 변동률 (소수 형식, 예: "0.025" = +2.5%)
        let changeRate = (Double(sodUtc8 ?? "0") ?? 0) * 100

        return Ticker(
            id: "okx-\(instId.lowercased())",
            symbol: baseSymbol,
            currentPrice: Double(last) ?? 0,
            changeRate24h: changeRate,
            volume24h: Double(vol24h) ?? 0,
            exchange: .okx,
            timestamp: Date()
        )
    }
}
