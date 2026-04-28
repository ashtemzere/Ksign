//
//  FilesView.swift
//  Ksign
//
//  Created by Nagata Asami on 5/22/25.
//

import SwiftUI
import UniformTypeIdentifiers
import QuickLook
import NimbleViews

extension URL: Identifiable {
    public var id: String { self.absoluteString }
}

// MARK: - Main View
struct FilesView: View {
    let directoryURL: URL?
    let isRootView: Bool
    @Namespace private var _namespace
    
    @StateObject private var viewModel: FilesViewModel
    @StateObject private var storeViewModel = StoreViewModel()
    @StateObject private var downloadManager = DownloadManager.shared
    
    @State private var searchText = ""
    @State private var selectedTab = 0 // 0 = App Store, 1 = Local Files
    
    @AppStorage("Feather.useLastExportLocation") private var _useLastExportLocation: Bool = false
    
    @State private var plistFileURL: URL?
    @State private var hexEditorFileURL: URL?
    @State private var textEditorFileURL: URL?
    @State private var quickLookFileURL: URL?
    @State private var moveSingleFile: FileItem?
    @State private var shareItems: [Any] = []
    @State private var navigateToDirectoryURL: URL?
    
    init() {
        self.directoryURL = nil
        self.isRootView = true
        self._viewModel = StateObject(wrappedValue: FilesViewModel())
    }
    
    init(directoryURL: URL) {
        self.directoryURL = directoryURL
        self.isRootView = false
        self._viewModel = StateObject(wrappedValue: FilesViewModel(directory: directoryURL))
    }
    
    private var filteredFiles: [FileItem] {
        if searchText.isEmpty {
            return viewModel.files
        } else {
            return viewModel.files.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        Group {
            if isRootView {
                NavigationStack {
                    mainContent
                }
                .accentColor(.blue)
            } else {
                localFilesContent
            }
        }
        .onAppear {
            if isRootView && storeViewModel.apps.isEmpty {
                storeViewModel.fetchApps()
            }
            viewModel.loadFiles()
        }
    }
    
    // MARK: - App Store / Files Segment Content
    private var mainContent: some View {
        VStack(spacing: 0) {
            Picker("View Mode", selection: $selectedTab) {
                Text("App Store").tag(0)
                Text("My Files").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(UIColor.systemBackground))
            
            TabView(selection: $selectedTab) {
                appStoreContent
                    .tag(0)
                
                localFilesContent
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .navigationTitle(selectedTab == 0 ? "Home" : "Files") // ناوی شاشە گۆڕا بۆ Home
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if selectedTab == 1 {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    addButton
                    editButton
                }
            }
        }
    }
    
    // MARK: - 1. App Store View (ڕێک وەک وێنەکە دیزاین کراوە)
    private var appStoreContent: some View {
        ZStack {
            Color(UIColor.systemBackground).edgesIgnoringSafeArea(.all)
            
            if storeViewModel.isLoading {
                VStack {
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding()
                    Text("خەریکی هێنانی داتاکانە...")
                        .foregroundColor(.secondary)
                }
            } else if let errorMessage = storeViewModel.errorMessage {
                VStack(spacing: 15) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.red)
                    Text("کێشەیەک ڕوویدا")
                        .font(.title3.bold())
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                    
                    Button {
                        storeViewModel.fetchApps()
                    } label: {
                        Text("دووبارە هەوڵبدەرەوە")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 25)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                    .padding(.top, 10)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 25) {
                        
                        // باکگراوندی سەرەوە (Banner)
                        ZStack(alignment: .bottomLeading) {
                            RoundedRectangle(cornerRadius: 15)
                                .fill(LinearGradient(gradient: Gradient(colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.8)]), startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(height: 180)
                            
                            VStack(alignment: .leading) {
                                Text("NEW")
                                    .font(.caption2).bold()
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .clipShape(Capsule())
                                
                                Text("AshteMobile Apps")
                                    .font(.title2).bold()
                                    .foregroundColor(.white)
                                
                                Text("باشترین بەرنامەکان لێرە داگرە")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            .padding()
                        }
                        .padding(.horizontal)
                        
                        // بەشی Apps
                        VStack(alignment: .leading, spacing: 15) {
                            Text("Apps")
                                .font(.title2).bold()
                                .padding(.horizontal)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 15) {
                                    // بۆ ئەوەی جوان دەربکەوێت، نیوەی سەرەتای ئەپەکان لێرە نیشان دەدەین
                                    ForEach(storeViewModel.apps) { app in
                                        AppStoreCard(app: app, viewModel: storeViewModel)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        
                        // بەشی Games
                        VStack(alignment: .leading, spacing: 15) {
                            Text("Games")
                                .font(.title2).bold()
                                .padding(.horizontal)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 15) {
                                    // نیشاندانی ئەپەکان بە پێچەوانەوە بۆ ئەوەی جیاواز دەربکەوێت
                                    ForEach(storeViewModel.apps.reversed()) { app in
                                        AppStoreCard(app: app, viewModel: storeViewModel)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.top, 10)
                }
                .refreshable {
                    storeViewModel.fetchApps()
                }
            }
        }
    }
    
    // MARK: - 2. Local Files View
    private var localFilesContent: some View {
        ZStack {
            List {
                ForEach(filteredFiles) { file in
                    let isSelected = viewModel.selectedItems.contains(file)
                    
                    HStack(spacing: 15) {
                        if viewModel.isEditMode == .active {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(isSelected ? .blue : .gray)
                                .font(.title3)
                        }
                        
                        Image(systemName: file.isAppDirectory ? "app.dashed" : (file.isDirectory ? "folder.fill" : "doc.fill"))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 45, height: 45)
                            .foregroundColor(file.isAppDirectory ? .purple : (file.isDirectory ? .blue : .gray))
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(file.name).font(.headline).lineLimit(1)
                            Text(file.isDirectory ? "Folder" : "File").font(.subheadline).foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if viewModel.isEditMode == .active {
                            withAnimation(.spring()) {
                                if isSelected { viewModel.selectedItems.remove(file) }
                                else { viewModel.selectedItems.insert(file) }
                            }
                        } else {
                            if file.isDirectory { navigateToDirectory(file.url) }
                            else { quickLookFileURL = file.url }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        FileUIHelpers.swipeActions(for: file, viewModel: viewModel)
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        }
        .navigationDestination(isPresented: Binding(
            get: { navigateToDirectoryURL != nil },
            set: { if !$0 { navigateToDirectoryURL = nil } }
        )) {
            if let url = navigateToDirectoryURL {
                FilesView(directoryURL: url)
            }
        }
    }
    
    // MARK: - Helpers & Toolbars
    private func navigateToDirectory(_ url: URL) { navigateToDirectoryURL = url }
    private func setupView() { viewModel.loadFiles() }
    
    private var addButton: some View {
        Menu {
            Button { viewModel.showingImporter = true } label: { Label("Import", systemImage: "plus") }
        } label: { Image(systemName: "plus") }
    }
    
    private var editButton: some View {
        Button(viewModel.isEditMode == .active ? "Done" : "Edit") {
            withAnimation {
                viewModel.isEditMode = viewModel.isEditMode == .active ? .inactive : .active
            }
        }
    }
}

// MARK: - App Card Component (ڕێک وەک وێنەکە)
struct AppStoreCard: View {
    let app: AppItem
    let viewModel: StoreViewModel
    
    var body: some View {
        VStack(spacing: 8) {
            // App Icon
            AsyncImage(url: URL(string: app.iconURL)) { phase in
                switch phase {
                case .empty:
                    Color.gray.opacity(0.2)
                        .overlay(ProgressView().scaleEffect(0.8))
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    // لۆگۆی دیفۆڵت ئەگەر وێنە نەبوو
                    Image(systemName: "app.fill")
                        .resizable()
                        .scaledToFit()
                        .padding(15)
                        .foregroundColor(.blue.opacity(0.5))
                        .background(Color(.systemGray6))
                @unknown default:
                    EmptyView()
                }
            }
            .frame(width: 85, height: 85)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 2)
            
            // App Name
            Text(app.name)
                .font(.system(size: 14, weight: .bold))
                .lineLimit(1)
                .frame(width: 85)
            
            // Rating / Info
            HStack(spacing: 2) {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                    .font(.system(size: 10))
                Text("4.6") // ژمارەی وەهمی بۆ دیزاین
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            // Get Button
            GetButton(
                fileSize: viewModel.formatSize(app.size),
                action: {
                    if let url = URL(string: app.downloadURL) {
                        print("Downloading from: \(url)")
                        // DownloadManager.shared.startArchive(...)
                    }
                }
            )
        }
        .frame(width: 100)
    }
}

// MARK: - Get Button Component
struct GetButton: View {
    let fileSize: String
    let action: () -> Void
    
    @State private var isDownloading = false
    @State private var rotation: Double = 0
    
    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.3)) { isDownloading = true }
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation { isDownloading = false }
            }
        }) {
            ZStack {
                if isDownloading {
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .frame(width: 28, height: 28)
                        .rotationEffect(.degrees(rotation))
                        .onAppear {
                            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                                rotation = 360
                            }
                        }
                } else {
                    Text("Get")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.blue)
                        .frame(width: 70, height: 28)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - App Store Models & Bulletproof ViewModel

// مۆدێلێکی زۆر سادە کە بە دەست دروست دەکرێت، پێویستی بە Codable نییە
struct AppItem: Identifiable {
    var id: String
    let name: String
    let developerName: String
    let iconURL: String
    let downloadURL: String
    let size: Int64
}

class StoreViewModel: ObservableObject {
    @Published var apps: [AppItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    func fetchApps() {
        guard let url = URL(string: "https://ashtemobile.tututweak.com/ipa.json") else { return }
        
        isLoading = true
        errorMessage = nil
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.httpMethod = "GET"
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    return
                }
                
                guard let data = data else {
                    self?.errorMessage = "هیچ داتایەک نەگەڕایەوە."
                    return
                }
                
                // بەکارهێنانی Manual Parsing کە هەرگیز کێشەی بۆ دروست نابێت
                do {
                    var extractedApps: [[String: Any]] = []
                    
                    if let jsonObject = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        // گەڕان بۆ لیستی ئەپەکان لە ناو فایلەکەدا
                        if let appsArray = jsonObject["apps"] as? [[String: Any]] {
                            extractedApps = appsArray
                        } else if let appsArray = jsonObject["app"] as? [[String: Any]] {
                            extractedApps = appsArray
                        } else {
                            // ئەگەر ناوی فۆڵدەرەکەش نەزانین، بۆی دەگەڕێین
                            for (_, value) in jsonObject {
                                if let arr = value as? [[String: Any]] {
                                    extractedApps = arr
                                    break
                                }
                            }
                        }
                    } else if let jsonArray = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] {
                        // ئەگەر فایلەکە ڕاستەوخۆ لیستێک بێت
                        extractedApps = jsonArray
                    }
                    
                    var tempApps: [AppItem] = []
                    for dict in extractedApps {
                        // دەرهێنانی ناوەکان بە هەموو شێوەیەک
                        let name = dict["name"] as? String ?? dict["title"] as? String ?? "Unknown App"
                        let icon = dict["iconURL"] as? String ?? dict["icon"] as? String ?? dict["image"] as? String ?? ""
                        let download = dict["downloadURL"] as? String ?? dict["url"] as? String ?? dict["ipa"] as? String ?? ""
                        let dev = dict["developerName"] as? String ?? dict["developer"] as? String ?? "AshteMobile"
                        let bundleId = dict["bundleIdentifier"] as? String ?? UUID().uuidString
                        
                        var sizeVal: Int64 = 0
                        if let s = dict["size"] as? Int64 { sizeVal = s }
                        else if let sStr = dict["size"] as? String, let s = Int64(sStr) { sizeVal = s }
                        
                        let item = AppItem(
                            id: bundleId,
                            name: name,
                            developerName: dev,
                            iconURL: icon,
                            downloadURL: download,
                            size: sizeVal
                        )
                        tempApps.append(item)
                    }
                    
                    self?.apps = tempApps
                    
                    if tempApps.isEmpty {
                        // ئەگەر داتاکە HTML بێت نەک JSON (وەک Cloudflare)
                        if let str = String(data: data, encoding: .utf8), str.contains("<html") {
                            self?.errorMessage = "سێرڤەرەکە ڕێگە نادات (Cloudflare Protection) تکایە لینکەکە بگۆڕە."
                        } else {
                            self?.errorMessage = "فایلەکە کرایەوە، بەڵام هیچ یاری یان بەرنامەیەک نەدۆزرایەوە."
                        }
                    }
                    
                } catch {
                    // ئەگەر بە هیچ جۆرێک نەخوێنرایەوە
                    if let str = String(data: data, encoding: .utf8), str.contains("<html") {
                        self?.errorMessage = "سێرڤەرەکە بلۆکی کردووە (Cloudflare). دەبێت لینکی ڕاستەوخۆ بەکاربێنی."
                    } else {
                        self?.errorMessage = "شێوازی فایلی JSON هەڵەیە."
                    }
                }
            }
        }.resume()
    }
    
    func formatSize(_ size: Int64?) -> String {
        guard let size = size, size > 0 else { return "" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}
