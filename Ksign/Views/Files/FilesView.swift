//
//  FilesView.swift
//  Ksign
//
//  Created by Nagata Asami on 5/22/25.
//  Modified for AshteMobile App Store Look
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
    @State private var selectedTab = 0 // 0 = Store, 1 = Files
    
    // شتەکانی تر بۆ فایلەکان
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
                .accentColor(.accentColor)
            } else {
                localFilesContent // ئەگەر چوویتە ناو فۆڵدەرێک، تەنها فایلەکان نیشان بدە
            }
        }
        .onAppear {
            if isRootView {
                storeViewModel.fetchApps()
            }
            viewModel.loadFiles()
        }
    }
    
    // MARK: - Main Content with Tabs
    private var mainContent: some View {
        VStack(spacing: 0) {
            // دیزاینی سەرەوە بۆ گۆڕینی نێوان Store و Files
            Picker("View Mode", selection: $selectedTab) {
                Text("App Store").tag(0)
                Text("My Files").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()
            
            // نیشاندانی ناوەڕۆک بەپێی هەڵبژاردنەکە
            TabView(selection: $selectedTab) {
                appStoreContent
                    .tag(0)
                
                localFilesContent
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never)) // ڕێگە دەدات بە پەنجە ڕایبکێشی (Swipe)
        }
        .navigationTitle(selectedTab == 0 ? "Ashte Store" : "Local Files")
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
    
    // MARK: - 1. App Store View (لە لینکەکەوە دەیهێنێت)
    private var appStoreContent: some View {
        ZStack {
            Color(.systemGroupedBackground).edgesIgnoringSafeArea(.all)
            
            if storeViewModel.isLoading {
                VStack(spacing: 15) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading Apps...")
                        .foregroundColor(.secondary)
                }
            } else if let errorMessage = storeViewModel.errorMessage {
                VStack {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text(errorMessage)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("Retry") {
                        storeViewModel.fetchApps()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(storeViewModel.apps) { app in
                            // دیزاینی کارت بۆ هەر بەرنامەیەک زۆر شاز
                            HStack(spacing: 15) {
                                AsyncImage(url: URL(string: app.iconURL ?? "")) { image in
                                    image.resizable()
                                } placeholder: {
                                    Color.gray.opacity(0.3)
                                        .overlay(ProgressView())
                                }
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 60, height: 60)
                                .cornerRadius(14)
                                .shadow(color: .black.opacity(0.15), radius: 5, x: 0, y: 2)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(app.name)
                                        .font(.system(size: 18, weight: .semibold))
                                        .lineLimit(1)
                                    
                                    Text(app.developerName ?? "AshteMobile")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                GetButton(
                                    fileSize: storeViewModel.formatSize(app.size),
                                    action: {
                                        if let downloadURLString = app.downloadURL, let url = URL(string: downloadURLString) {
                                            print("Start Download for: \(app.name)")
                                            // لێرە کۆدی داگرتن دابنێ بۆ DownloadManager
                                            // let download = downloadManager.startArchive(from: url, id: app.id)
                                        }
                                    }
                                )
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(16)
                            .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
                        }
                    }
                    .padding()
                }
                .refreshable {
                    storeViewModel.fetchApps()
                }
            }
        }
    }
    
    // MARK: - 2. Local Files View (کۆدەکانی پێشووی خۆت)
    private var localFilesContent: some View {
        ZStack {
            List {
                ForEach(filteredFiles) { file in
                    let isSelected = viewModel.selectedItems.contains(file)
                    
                    HStack(spacing: 15) {
                        if viewModel.isEditMode == .active {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(isSelected ? .blue : .gray)
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
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if viewModel.isEditMode == .active {
                            withAnimation {
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
    private func navigateToDirectory(_ url: URL) {
        navigateToDirectoryURL = url
    }
    
    private var addButton: some View {
        Menu {
            Button { viewModel.showingImporter = true } label: { Label("Import", systemImage: "plus") }
        } label: { Image(systemName: "plus") }
    }
    
    private var editButton: some View {
        Button(viewModel.isEditMode == .active ? "Done" : "Edit") {
            viewModel.isEditMode = viewModel.isEditMode == .active ? .inactive : .active
        }
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
            withAnimation(.easeInOut(duration: 0.3)) {
                isDownloading = true
            }
            action()
            
            // شێوەکاری تەواوبوونی داگرتن
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
                    VStack(spacing: 2) {
                        Text("GET")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1)) // باکگراوندی جوانتر
                            .clipShape(Capsule())
                        
                        Text(fileSize)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(width: 60)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - App Store Models & ViewModel
struct AppItem: Codable, Identifiable {
    var id: String { bundleIdentifier ?? name }
    let name: String
    let bundleIdentifier: String?
    let developerName: String?
    let version: String?
    let iconURL: String?
    let downloadURL: String?
    let size: Int64?
}

struct AppStoreResponse: Codable {
    let apps: [AppItem]
}

class StoreViewModel: ObservableObject {
    @Published var apps: [AppItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    func fetchApps() {
        guard let url = URL(string: "https://ashtemobile.tututweak.com/ipa.json") else { return }
        
        isLoading = true
        errorMessage = nil
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    return
                }
                guard let data = data else { return }
                
                do {
                    if let array = try? JSONDecoder().decode([AppItem].self, from: data) {
                        self?.apps = array
                    } else if let dict = try? JSONDecoder().decode(AppStoreResponse.self, from: data) {
                        self?.apps = dict.apps
                    } else {
                        self?.errorMessage = "Invalid JSON format"
                    }
                }
            }
        }.resume()
    }
    
    func formatSize(_ size: Int64?) -> String {
        guard let size = size else { return "" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}
