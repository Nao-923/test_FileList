import Foundation
import RealmSwift

class DataModel: Object {
    @objc dynamic var lastDate: String = ""
    @objc dynamic var contents: ContentsModel?
}

class ContentsModel: Object {
    @objc dynamic var title: String = ""
    @objc dynamic var date: String = ""
    @objc dynamic var contents: String = ""
}
