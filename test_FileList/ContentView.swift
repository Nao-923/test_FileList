import SwiftUI
import WebKit
import Down
import RealmSwift

var baseUrl = "http://192.168.11.3:8081"

struct ContentView: View {
    @State private var searchText = ""
    @State private var availableFiles: [File] = []
    @State private var showOptionView = false
    @State private var isPresented = false
    @State private var selectedItem: File? // 追加
    
    var filteredFiles: [File] {
        if searchText.isEmpty {
            return availableFiles
        } else {
            return availableFiles.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        NavigationView {
            List(filteredFiles, id: \.self) { file in
                NavigationLink(destination: ContentsView(file: file, isPresented: $isPresented)) {
                    VStack(alignment: .leading) {
                        Text(file.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(25))
                            .font(.title3)
                            .allowsHitTesting(false)
                        Text(file.dateString)
                            .font(.caption)
                            .allowsHitTesting(false)
                    }
                }
                .simultaneousGesture(
                    TapGesture()
                        .onEnded {
                            // シングルタップ時の処理を記述
                        }
                )
                .onLongPressGesture {
                    self.selectedItem = file // 追加
                }
                .alert(item: $selectedItem) { selectedItem in
                    // selectedItem が設定されたらアラートを表示
                    Alert(
                        title: Text("Delete"),
                        message: Text("Are you sure you want to delete \(selectedItem.name)?"),
                        primaryButton: .destructive(Text("OK")) {
                            deleteFile(file: selectedItem)
                        },
                        secondaryButton: .cancel()
                    )
                }
            }
            .navigationTitle("File List")
            .searchable(text: $searchText)
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    HStack {
                        Button(action: {
                            self.showOptionView.toggle()
                        }) {
                            Image(systemName: "gearshape")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 32, height: 32)
                        }
                        .padding()
                        .sheet(isPresented: $showOptionView) {
                            OptionView(show: $showOptionView)
                                .presentationDetents([
                                    .height(200)
                                ])
                        }
                        
                        Button(action: { getFileList() }) {
                            Image(systemName: "arrow.clockwise")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 32, height: 32)
                        }
                        .padding()
                        
                        Button(action: { fetchAndSaveFiles() }) {
                            Image(systemName: "icloud.and.arrow.down")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 32, height: 32)
                        }
                        .padding()
                    }
                    
                }
            }
        }
        .onAppear {
            // アプリ起動時にRealmからデータを読み込む
            loadFilesFromRealm()
        }
    }
    private func fetchAndSaveFiles() { // メソッド名を修正
        guard let url = URL(string: "\(baseUrl)/get_markdown") else { // ファイル名一覧を取得するためのURL
            print("Invalid URL")
            return
        }
        
        guard let fileListData = try? Data(contentsOf: url) else { // ファイル名一覧のデータを取得
            print("Failed to fetch file list")
            return
        }
        
        guard let fileList = try? JSONDecoder().decode([String].self, from: fileListData) else { // ファイル名一覧をJSON形式から復元
            print("Failed to decode file list")
            return
        }
        
        let realm = try! Realm()
        
        for fileName in fileList {
            if let existingContent = realm.objects(ContentsModel.self).filter("title == %@", fileName).first {
                // Realmに同じファイル名がある場合はファイル内容を更新
                fetchAndUpdateContent(fileName: fileName, existingContent: existingContent)
            } else {
                // Realmに同じファイル名がない場合はファイル内容を保存
                fetchAndSaveContent(fileName: fileName)
            }
        }
        getFileList()
    }
    
    private func fetchAndUpdateContent(fileName: String, existingContent: ContentsModel) {
        let encodedFileName = fileName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        guard let url = URL(string: "\(baseUrl)/get_markdown/\(encodedFileName ?? "")") else {
            print("Invalid URL")
            return
        }
        
        guard let markdownData = try? Data(contentsOf: url) else {
            print("Failed to load markdown data for file: \(fileName)")
            return
        }
        
        guard let markdownString = String(data: markdownData, encoding: .utf8) else {
            print("Failed to convert markdown data to string for file: \(fileName)")
            return
        }
        
        let realm = try! Realm()
        try! realm.write {
            existingContent.contents = markdownString // ファイル内容を更新
            existingContent.date = getDateString() // 日付を更新
        }
    }
    
    private func fetchAndSaveContent(fileName: String) {
        let encodedFileName = fileName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        guard let url = URL(string: "\(baseUrl)/get_markdown/\(encodedFileName ?? "")") else {
            print("Invalid URL")
            return
        }
        
        guard let markdownData = try? Data(contentsOf: url) else {
            print("Failed to load markdown data for file: \(fileName)")
            return
        }
        
        guard let markdownString = String(data: markdownData, encoding: .utf8) else {
            print("Failed to convert markdown data to string for file: \(fileName)")
            return
        }
        
        let realm = try! Realm()
        let contentsModel = ContentsModel()
        contentsModel.title = fileName
        contentsModel.date = getDateString()
        contentsModel.contents = markdownString
        
        try! realm.write {
            realm.add(contentsModel) // ファイル内容を保存
        }
    }


    func loadFilesFromRealm() {
        let realm = try! Realm()
        // Realmからファイルリストを取得
        let contentsModels = realm.objects(ContentsModel.self)
        var files: [File] = []
        for contentsModel in contentsModels {
            let file = File(name: contentsModel.title, dateString: contentsModel.date)
            files.append(file)
        }
        // メインスレッドで画面を更新
        DispatchQueue.main.async {
            self.availableFiles = files
        }
    }

    private func getFileList() {
        // データベースを再度チェックして、リストを更新
        loadFilesFromRealm()
    }

    private func decodeUnicode(_ string: String) -> String {
        var result = ""
        var chars = string.utf16.makeIterator()
        while let char = chars.next() {
            if char == 0x5C, let nextChar = chars.next(), nextChar == 0x75 {
                var codeUnit: UInt16 = 0
                for _ in 0..<4 {
                    guard let nextChar = chars.next(), let digit = UInt16(String(UnicodeScalar(nextChar)!), radix: 16) else {
                        break
                    }
                    codeUnit = codeUnit * 16 + digit
                }
                if let unicodeScalar = UnicodeScalar(codeUnit) {
                    result.append(String(unicodeScalar))
                }
            } else {
                result.append(Character(UnicodeScalar(char)!))
            }
        }
        return result
    }

    private func getDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd/HH:mm:ss"
        return formatter.string(from: Date())
    }
    private func deleteFile(file: File) {
        let realm = try! Realm()
        
        // Realmから対応するContentsModelを取得
        if let contentToDelete = realm.objects(ContentsModel.self).filter("title == %@", file.name).first {
            do {
                try realm.write {
                    // ContentsModelを削除
                    realm.delete(contentToDelete)
                }
                
                // ファイルリストを更新
                getFileList()
            } catch {
                print("Error deleting file: \(error)")
            }
        }
    }
}

struct File: Hashable, Identifiable { // Identifiable プロトコルに準拠させる
    let id = UUID() // id プロパティの追加
    let name: String
    let dateString: String
}

struct ContentsView: View {
    let file: File
    @State private var htmlString: String = ""
    let realm = try! Realm()
    @Binding var isPresented: Bool
        

    var body: some View {
        VStack {
            ZStack {
                Text(file.dateString.prefix(20))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
//                Button(action: { deleteFile(file: file)}) {
//                    Image(systemName: "trash")
//                        .resizable()
//                        .scaledToFit()
//                        .frame(width: 24, height: 24)
//                        .background(.white)
//                }
//                .frame(maxWidth: .infinity, alignment: .trailing)
//                .padding()
            }
            .navigationTitle(file.name)
            Divider()
            if !htmlString.isEmpty {
                WebView(htmlString: htmlString)
                    .padding()
            } else {
                ProgressView()
                    .padding()
            }
        }
        .onAppear {
            loadMarkdownContent()
        }
    }

    private func loadMarkdownContent() {
        if let contentsModel = realm.objects(ContentsModel.self).filter("title == %@", file.name).first {
            htmlString = parseMarkdownToHTML(markdownText: contentsModel.contents)
        }
    }

    private func parseMarkdownToHTML(markdownText: String) -> String {
        do {
            let down = Down(markdownString: markdownText)
            let htmlString = try down.toHTML()
            return htmlString
        } catch {
            print("Error parsing markdown: \(error)")
            return ""
        }
    }
}

struct WebView: UIViewRepresentable {
    let htmlString: String

    func makeUIView(context: Context) -> WKWebView {
        return WKWebView()
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.loadHTMLString(htmlString, baseURL: nil)
    }
}

func parseMarkdownToHTML(markdownText: String) -> String {
    do {
        let down = Down(markdownString: markdownText)
        let htmlString = try down.toHTML()
        return htmlString
    } catch {
        print("Error parsing markdown: \(error)")
        return ""
    }
}

struct OptionView: View {
    @State private var url = ""
    @Binding var show:Bool
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            Spacer()
            TextField("\(baseUrl)", text: $url)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            Button(action: {
                baseUrl = url
                show.toggle()
            }) {
                Text("Confirm")
                    .padding()
                    .foregroundColor(.white)
                    .background(Color.blue)
                    .cornerRadius(8)
            }
            .padding()
            
            Spacer()
        }
        .padding()
    }
}

// Preview のコードは省略
#Preview{
    ContentView()
}
