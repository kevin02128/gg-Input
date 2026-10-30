import Foundation

/// Semantic-Enhanced Part-of-Speech (POS) Tags for gg input method.
/// Uses compact UInt8 encoding (<= 32 tags) for instant L1-cache lookups.
public enum POSTag: UInt8, CaseIterable, Sendable {
    case none = 0

    // Semantic Verbs (VC / VA / VB / VE / VJ / VH)
    case vcGeneral = 1   // Transitive general action (帶, 拿, 買, 借, 吃, 喝, 找, 寄, 寫, 領, 付, 裝, 檢查...)
    case vcWear = 2      // Wearable action (戴, 穿, 披, 佩, 著, 配戴, 佩戴, 穿著, 戴上, 穿上...)
    case va = 3          // Intransitive action (走, 跑, 來, 去, 睡, 休息, 集合, 出發, 站, 坐...)
    case vb = 4          // Ditransitive verb (給, 送給, 借給, 遞給, 匯給, 寄給...)
    case ve = 5          // Cognitive / communication verb (說, 講, 覺得, 認為, 知道, 想, 希望, 打算, 決定...)
    case vj = 6          // Relational / state verb (是, 有, 沒有, 像, 適合, 屬於, 等於...)
    case vh = 7          // State intransitive / adjective (好, 大, 小, 多, 少, 貴, 便宜, 快, 慢, 冷, 熱...)

    // Nouns (Na / Nc / Nd / Nh / Nb)
    case naGeneral = 8   // Common entity/item nouns (手機, 鑰匙, 錢包, 水壺, 便當, 雨傘, 電腦, 筆記本, 行李, 書...)
    case naWearable = 9  // Wearable items (眼鏡, 手錶, 帽子, 耳機, 口罩, 手套, 雨衣, 安全帽, 外套, 鞋子, 襪子...)
    case nc = 10         // Locative / place nouns (學校, 台北, 台灣, 家裡, 辦公室, 車站, 捷運站, 店裡, 路上, 門...)
    case nd = 11         // Temporal nouns (今天, 明天, 昨天, 現在, 剛才, 出發前, 等一下, 稍後, 以後, 之前...)
    case nh = 12         // Pronouns (我, 你, 妳, 他, 她, 它, 我們, 你們, 他們, 大家, 自己, 您...)
    case nb = 13         // Proper nouns / Names

    // Functional & Closed-Class Words
    case d = 14          // General adverbs (很, 非常, 立刻, 已經, 正在, 隨時, 永遠, 常常, 一直, 倒, 就, 才...)
    case p = 15          // General prepositions (從, 由, 向, 往, 被, 讓, 照, 比, 隨, 沿...)
    case pDai = 16       // Specialized preposition / substitute: 代 (stripped of standalone VC status)
    case pZai = 17       // Specialized preposition: 在 (在台北, 在家裡, 在學校)
    case dZai = 18       // Specialized adverb: 再 (再走, 再看, 再檢查一次, 等一下再)
    case c = 19          // Conjunctions (和, 與, 跟, 以及, 但是, 可是, 而且, 雖然, 因為, 所以, 如果...)
    case de = 20         // Particles: 的, 得, 地
    case t = 21          // Sentence-final particles (嗎, 呢, 吧, 啦, 啊, 哇, 耶, 喔, 囉, 唄)
    case neu = 22        // Numerals (一, 二, 三, 四, 五, 六, 七, 八, 九, 十, 百, 千, 萬, 兩, 幾...)
    case nf = 23         // Classifiers / Measure words (個, 隻, 支, 本, 條, 件, 張, 塊, 把, 雙, 輛, 台, 份...)
    case nep = 24        // Demonstratives (這, 那, 這個, 那個, 這些, 那些...)
}
