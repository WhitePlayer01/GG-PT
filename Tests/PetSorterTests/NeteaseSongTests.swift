import Foundation

@main struct NeteaseSongTests {
    static func main() throws {
        func queue(_ entries: [[String: Any]]) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["list": entries.map { ["track": $0] }])
        }
        let song: [String: Any] = ["name": "2.14", "artists": [["name": "大宝西"]],
                                   "album": ["name": "测试专辑"], "duration": 180_000]
        let data = try queue([song])
        let found = NeteaseSongMatcher.match(lines: ["2.14", "大宝西", "100w+"], queueData: data)
        precondition(found?.title == "2.14" && found?.artist == "大宝西")
        precondition(found?.album == "测试专辑" && found?.duration == 180)
        precondition(NeteaseSongMatcher.match(lines: ["2.14"], queueData: data) == nil)
        precondition(NeteaseSongMatcher.match(lines: ["大宝西"], queueData: data) == nil)
        precondition(NeteaseSongMatcher.match(lines: ["旧歌曲", "大宝西"], queueData: data) == nil)
        precondition(NeteaseSongMatcher.match(lines: ["2.14", "其他歌手"], queueData: data) == nil)
        precondition(NeteaseSongMatcher.match(lines: ["2.14", "大宝西"], queueData: Data("broken".utf8)) == nil)
        var second = song; second["album"] = ["name": "另一专辑"]
        let ambiguous = try queue([song, second])
        precondition(NeteaseSongMatcher.match(lines: ["2.14", "大宝西"], queueData: ambiguous) == nil)
        let repeated = try queue([song, song])
        precondition(NeteaseSongMatcher.match(lines: ["2.14", "大宝西"], queueData: repeated) != nil)
        print("网易云歌曲匹配：完整信息、缺失字段、旧歌曲、同名歧义、重复队列、损坏数据均通过")
    }
}
