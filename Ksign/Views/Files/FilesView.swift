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
                localFilesContent // If inside a folder
            }
        }
        .onAppear {
            if isRootView {
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
        .navigationTitle(selectedTab == 0 ? "Ashte Store" : "Files")
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
    
    // MARK: - 1. App Store View (Design similar to the image)
    private var appStoreContent: some View {
        ZStack {
            Color(UIColor.secondarySystemBackground).edgesIgnoringSafeArea(.all)
            
            if storeViewModel.isLoading {
                VStack {
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding()
                    Text("خەریکی هێنانی بەرنامەکانە...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            } else if let errorMessage = storeViewModel.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.red)
                    Text("کێشەیەک ڕوویدا")
                        .font(.title3.bold())
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("دووبارە هەوڵبدەرەوە") {
                        storeViewModel.fetchApps()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .padding(.top, 10)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(storeViewModel.apps) { app in
                            HStack(spacing: 16) {
                                // App Icon
                                AsyncImage(url: URL(string: app.iconURL ?? "")) { phase in
                                    switch phase {
                                    case .empty:
                                        Color.gray.opacity(0.2)
                                            .overlay(ProgressView().scaleEffect(0.8))
                                    case .success(let image):
                                        image.resizable().scaledToFit()
                                    case .failure:
                                        Image(systemName: "app.dashed")
                                            .resizable()
                                            .scaledToFit()
                                            .padding(10)
                                            .foregroundColor(.gray)
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                                .frame(width: 65, height: 65)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                                
                                // App Info
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(app.name ?? "Unknown App")
                                        .font(.system(size: 17, weight: .semibold))
                                        .lineLimit(1)
                                    
                                    Text(app.developerName ?? "AshteMobile Team")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                // Get Button
                                GetButton(
                                    fileSize: storeViewModel.formatSize(app.size),
                                    action: {
                                        if let downloadURLString = app.downloadURL, let url = URL(string: downloadURLString) {
                                            print("Downloading from: \(url)")
                                            // TODO: Pass this to your DownloadManager
                                            // e.g. let _ = downloadManager.startArchive(from: url, id: app.id)
                                        }
                                    }
                                )
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color(UIColor.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.vertical)
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
                                .transition(.scale)
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

// MARK: - Get Button Component (Animated App Store Button)
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
                    VStack(spacing: 2) {
                        Text("GET")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.12))
                            .clipShape(Capsule())
                        
                        if !fileSize.isEmpty {
                            Text(fileSize)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .frame(width: 65)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - App Store Models & ViewModel

struct AppItem: Codable, Identifiable {
    var id: String { bundleIdentifier ?? name ?? UUID().uuidString }
    
    // Everything is optional to prevent JSON decoding errors
    let name: String?
    let bundleIdentifier: String?
    let developerName: String?
    let version: String?
    let iconURL: String?
    let downloadURL: String?
    let size: Int64?
    
    // Check for different possible JSON key names
    enum CodingKeys: String, CodingKey {
        case name, version, size
        case bundleIdentifier = "bundleIdentifier"
        case developerName = "developerName"
        case iconURL = "iconURL"
        case downloadURL = "downloadURL"
    }
}

struct AppStoreResponse: Codable {
    let apps: [AppItem]?
}

class StoreViewModel: ObservableObject {
    @Published var apps: [AppItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    func fetchApps() {
        guard let url = URL(string: "https://ashtemobile.tututweak.com/ipa.json") else { return }
        
        isLoading = true
        errorMessage = nil
        
        // Use a standard browser User-Agent so the server doesn't block the request
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.httpMethod = "GET"
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    return
                }
                
                guard let data = data else {
                    self?.errorMessage = "داتایەک نەدۆزرایەوە."
                    return
                }
                
                // Flexible JSON Decoding
                do {
                    // Try 1: Is it an array of apps?
                    if let array = try? JSONDecoder().decode([AppItem].self, from: data) {
                        self?.apps = array.filter { $0.name != nil }
                    }
                    // Try 2: Is it an object containing an "apps" array?
                    else if let dict = try? JSONDecoder().decode(AppStoreResponse.self, from: data), let fetchedApps = dict.apps {
                        self?.apps = fetchedApps.filter { $0.name != nil }
                    }
                    // Failure: Could not read it
                    else {
                        self?.errorMessage = "نەتوانرا فایلە JSONـەکە بخوێنرێتەوە. دڵنیابە لە دروستی فایلەکە."
                    }
                    
                    if self?.apps.isEmpty == true && self?.errorMessage == nil {
                        self?.errorMessage = "هیچ بەرنامەیەک لە فایلەکەدا نەدۆزرایەوە."
                    }
                }
            }
        }.resume()
    }
    
    func formatSize(_ size: Int64?) -> String {
        guard let size = size, size > 0 else { return "APP" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}
