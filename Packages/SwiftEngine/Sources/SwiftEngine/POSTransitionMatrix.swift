import Foundation

/// Fast O(1) transition matrix for Semantic-Enhanced POS tags.
/// Stored as a contiguous flat array of 32x32 = 1024 Floats (~4 KB), fitting inside L1 Data Cache.
public final class POSTransitionMatrix: Sendable {
    public static let tagDimension: Int = 32
    private let matrix: [Float]

    public init(matrix: [Float]) {
        assert(matrix.count == Self.tagDimension * Self.tagDimension)
        self.matrix = matrix
    }

    @inline(__always)
    public func transitionScore(from: POSTag, to: POSTag) -> Float {
        if from == .none || to == .none { return 0.0 }
        let idx = Int(from.rawValue) * Self.tagDimension + Int(to.rawValue)
        return matrix[idx]
    }

    /// Evaluates the max-margin transition score across primary and secondary POS candidates.
    @inline(__always)
    public func maxTransitionScore(
        prevPrimary: POSTag,
        prevSecondary: POSTag,
        currPrimary: POSTag,
        currSecondary: POSTag
    ) -> Float {
        if prevPrimary == .none || currPrimary == .none { return 0.0 }

        var best = transitionScore(from: prevPrimary, to: currPrimary)
        if currSecondary != .none {
            let s = transitionScore(from: prevPrimary, to: currSecondary)
            if s > best { best = s }
        }
        if prevSecondary != .none {
            let s = transitionScore(from: prevSecondary, to: currPrimary)
            if s > best { best = s }
            if currSecondary != .none {
                let s2 = transitionScore(from: prevSecondary, to: currSecondary)
                if s2 > best { best = s2 }
            }
        }
        return best
    }

    /// Default production matrix trained and tuned for standard Traditional Chinese syntax
    /// and disambiguation of spoken and written homophones.
    public static let `default`: POSTransitionMatrix = {
        var table = Array(repeating: Float(0.0), count: tagDimension * tagDimension)

        func set(_ from: POSTag, _ to: POSTag, _ score: Float) {
            table[Int(from.rawValue) * tagDimension + Int(to.rawValue)] = score
        }

        // --- Transitive Verb General (帶, 拿, 買, 借, 吃, 喝, 找, 寄, 寫, 裝...) ---
        set(.vcGeneral, .naGeneral, 1.2)   // 帶手機, 帶鑰匙, 帶便當, 買水壺, 拿東西
        set(.vcGeneral, .naWearable, 0.8)  // 帶手錶, 帶雨衣, 帶外套 (valid collocation)
        set(.vcGeneral, .nh, 0.6)          // 帶我們, 找你, 借他
        set(.vcGeneral, .nep, 0.5)         // 帶這個, 拿那個
        set(.vcGeneral, .neu, 0.5)         // 買一個, 拿兩本
        set(.vcGeneral, .nc, 0.3)          // 去學校, 到台北
        set(.vcGeneral, .de, 0.4)          // 買的, 吃的

        // --- Transitive Wearable Verb (戴, 穿, 披, 佩, 著, 配戴...) ---
        set(.vcWear, .naWearable, 1.8)     // 戴手錶, 戴眼鏡, 穿雨衣, 戴安全帽, 戴口罩 (critical reward)
        set(.vcWear, .naGeneral, -1.8)     // 戴手機, 戴鑰匙, 戴錢包, 戴便當 (critical penalty!)
        set(.vcWear, .nc, -1.5)            // 戴學校, 穿台北
        set(.vcWear, .va, -1.5)            // 戴走, 穿跑
        set(.vcWear, .de, 0.4)             // 穿的, 戴的

        // --- Single character 代 (Specialized Preposition / Substitute) ---
        // Strictly stripped of VC privileges.
        set(.pDai, .nh, 1.0)               // 代我, 代你, 代表大家
        set(.pDai, .nb, 0.8)               // 代王先生
        set(.pDai, .naGeneral, -1.8)       // 代鑰匙, 代手機, 代水壺, 代東西 (critical penalty!)
        set(.pDai, .naWearable, -1.8)      // 代手錶, 代眼鏡 (critical penalty!)
        set(.pDai, .nc, -1.5)              // 代學校
        set(.pDai, .va, -1.5)              // 代走, 代出發

        // --- Preposition 在 (pZai) ---
        set(.pZai, .nc, 1.8)               // 在台北, 在家裡, 在學校, 在辦公室 (high reward)
        set(.pZai, .nd, 0.8)               // 在今天, 在出發前, 在目前
        set(.pZai, .naGeneral, -1.2)       // 在鑰匙, 在手機 (penalty)
        set(.pZai, .va, -1.8)              // 在走, 在看, 在去 (syntactic error! "再走" is correct)
        set(.pZai, .vcGeneral, -1.5)       // 在檢查, 在確認 (syntactic error! "再" is correct)

        // --- Adverb 再 (dZai) ---
        set(.dZai, .va, 1.8)               // 再走, 再跑, 再去, 再來, 再出發 (high reward)
        set(.dZai, .vcGeneral, 1.5)        // 再買, 再看, 再吃, 再檢查, 再確認 (high reward)
        set(.dZai, .vcWear, 1.2)           // 再穿, 再戴
        set(.dZai, .naGeneral, -1.2)       // 再鑰匙, 再手機 (penalty)
        set(.dZai, .nc, -1.2)              // 再台北, 再家裡

        // --- Temporal Nd (今天, 現在, 出發前, 等一下, 剛才...) ---
        set(.nd, .dZai, 1.2)               // 出發前再, 等一下再, 稍後再, 明天再 (natural sequence)
        set(.nd, .pZai, 0.5)               // 現在在, 今天在
        set(.nd, .d, 0.8)                  // 今天先, 現在就
        set(.nd, .nh, 0.8)                 // 今天我們, 現在大家
        set(.nd, .vcGeneral, 0.8)          // 等一下買, 出發前檢查
        set(.nd, .va, 0.8)                 // 等一下走, 現在出發

        // --- Adverb D (很, 非常, 立刻, 已經, 先, 又, 常常, 一直...) ---
        set(.d, .va, 1.5)                  // 先走, 常常來, 立刻出發
        set(.d, .vcGeneral, 1.4)           // 先買, 常吃, 立刻寫
        set(.d, .vcWear, 1.2)              // 先穿, 常常戴
        set(.d, .vh, 1.5)                  // 很好, 非常快, 很漂亮
        set(.d, .dZai, 1.2)                // 先再, 又再, 總算再

        // --- Intransitive Verb VA (走, 跑, 來, 去, 睡, 休息, 出發...) ---
        set(.va, .d, 0.6)                  // 走了又, 來了就
        set(.va, .nc, 0.8)                 // 走到學校, 來台北
        set(.va, .de, 1.0)                 // 走得, 跑得
        set(.va, .t, 0.8)                  // 走了吧, 走吧, 來啦

        // --- Prepositions P (從, 由, 向, 往, 給, 幫, 替...) ---
        set(.p, .nc, 1.5)                  // 從台北, 往學校, 向窗外
        set(.p, .nh, 1.2)                  // 給我, 幫你, 替他
        set(.p, .naGeneral, 0.6)           // 由政府, 向警方

        // --- Pronouns Nh (我, 你, 他, 我們, 大家...) ---
        set(.nh, .vcGeneral, 1.0)          // 我帶, 他拿, 你買
        set(.nh, .vcWear, 0.8)             // 我戴, 他穿
        set(.nh, .va, 1.0)                 // 我們走, 他們跑
        set(.nh, .d, 1.0)                  // 我再, 你先, 他又
        set(.nh, .pZai, 0.8)               // 我在, 他在
        set(.nh, .vj, 0.8)                 // 我有, 我們是
        set(.nh, .de, 1.0)                 // 我的, 你的, 他的

        // --- Particles DE (的, 得, 地) ---
        set(.de, .naGeneral, 1.2)          // 我的手機, 漂亮的鑰匙, 實用的東西
        set(.de, .naWearable, 1.2)         // 他的手錶, 防水雨衣
        set(.de, .nc, 0.8)                 // 我們的學校, 台北的街道
        set(.de, .vh, 1.0)                 // 跑得快, 玩得開心, 變得更好

        // --- Numerals & Classifiers (neu, nf) ---
        set(.neu, .nf, 1.8)                // 一個, 兩隻, 三把, 四本
        set(.nf, .naGeneral, 1.5)          // 一把鑰匙, 一支手機, 一個便當
        set(.nf, .naWearable, 1.5)         // 一隻手錶, 一頂安全帽, 一件雨衣
        set(.nep, .nf, 1.5)                // 這個, 那隻, 這把
        set(.nep, .naGeneral, 1.0)         // 這手機, 那鑰匙

        // --- Conjunctions C (和, 與, 跟, 以及...) ---
        set(.c, .naGeneral, 1.0)           // 和手機, 與鑰匙
        set(.c, .naWearable, 1.0)          // 和手錶
        set(.c, .nh, 1.0)                  // 和我, 跟他

        // --- State Adjective VH (好, 大, 快, 慢, 潛在, 漂亮...) ---
        set(.vh, .naGeneral, 0.8)          // 潛在危機, 漂亮物品
        set(.vh, .de, 1.2)                 // 跑得快, 漂亮地
        set(.vh, .vcGeneral, -1.5)         // 潛在確認, 乾淨買 (syntactic violation)
        set(.vh, .va, -1.5)                // 潛在走, 漂亮跑 (syntactic violation)
        set(.vh, .vcWear, -1.5)            // 潛在穿

        return POSTransitionMatrix(matrix: table)
    }()
}
