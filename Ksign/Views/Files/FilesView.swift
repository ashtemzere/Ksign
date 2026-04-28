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

struct FilesView: View {
    let directoryURL: URL?
    let isRootView: Bool
    @Namespace private var _namespace
    
    @StateObject private var viewModel: FilesViewModel
    @StateObject private var downloadManager = DownloadManager.shared
    @State private var searchText = ""

    @AppStorage("Feather.useLastExportLocation") private var _useLastExportLocation: Bool = false

    @State private var plistFileURL: URL?
    @State private var hexEditorFileURL: URL?
    @State private var textEditorFileURL: URL?
    @State private var quickLookFileURL: URL?
    @State private var moveSingleFile: FileItem?
    @State private var shareItems: [Any] = []
    @State private var navigateToDirectoryURL: URL?
    
    // گۆڕاوی نوێ بۆ نیشاندانی فڕۆشگاکە (Store)
    @State private var showStore = false
    
    // MARK: - Initializers
    
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
                    filesBrowserContent
                }
                .accentColor(.accentColor)
            } else {
                filesBrowserContent
            }
        }
        .onAppear {
            setupView()
        }
        .onDisappear {
            if !isRootView {
                NotificationCenter.default.removeObserver(self)
            }
        }
    }
    
    // MARK: - Main Content
    
    private var filesBrowserContent: some View {
        ZStack {
            contentView
                .navigationTitle(navigationTitle)
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
                .refreshable {
                    if isRootView {
                        await withCheckedContinuation { continuation in
                            viewModel.loadFiles()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                continuation.resume()
                            }
                        }
                    }
                }
                .toolbar {
                    // دوگمەی Store لە لای چەپ بۆ شاشەی سەرەکی
                    if isRootView && viewModel.isEditMode != .active {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                showStore = true
                            } label: {
                                Image(systemName: "bag.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        addButton
                        editButton
                    }
                    NBToolbarMenu(
                        systemImage: "line.3.horizontal.decrease",
                        style: .icon,
                        placement: .topBarTrailing
                    ) {
                        _sortActions()
                    }
                    if viewModel.isEditMode == .active {
                        ToolbarItem(placement: .topBarLeading) {
                            HStack(spacing: 12) {
                                selectAllButton
                                moveButton
                                shareButton
                                deleteButton
                            }
                        }
                    }
                }
            
        }
        // کردنەوەی پەڕەی Store کاتێک کلیک لە جانتاکە دەکرێت
        .sheet(isPresented: $showStore) {
            StoreView()
        }
        .sheet(isPresented: $viewModel.showingImporter) {
            FileImporterRepresentableView(
                allowedContentTypes: [UTType.item],
                allowsMultipleSelection: true,
                onDocumentsPicked: { urls in
                    viewModel.importFiles(urls: urls)
                }
            )
        }
        .sheet(item: $moveSingleFile) { item in
            FileExporterRepresentableView(
                urlsToExport: [item.url],
                asCopy: false,
                useLastLocation: _useLastExportLocation,
                onCompletion: { _ in
                    moveSingleFile = nil
                    viewModel.loadFiles()
                }
            )
        }
        .sheet(isPresented: $viewModel.showDirectoryPicker) {
            FileExporterRepresentableView(
                urlsToExport: Array(viewModel.selectedItems.map { $0.url }),
                asCopy: false,
                useLastLocation: _useLastExportLocation,
                onCompletion: { _ in
                    viewModel.selectedItems.removeAll()
                    if viewModel.isEditMode == .active { viewModel.isEditMode = .inactive }
                
                    viewModel.loadFiles()
                }
            )
        }
        .fullScreenCover(item: $plistFileURL) { fileURL in
            PlistEditorView(fileURL: fileURL)
                .compatNavigationTransition(id: fileURL.absoluteString, ns: _namespace)
        }
        .fullScreenCover(item: $hexEditorFileURL) { fileURL in
            HexEditorView(fileURL: fileURL)
                .compatNavigationTransition(id: fileURL.absoluteString, ns: _namespace)
        }
        .fullScreenCover(item: $textEditorFileURL) { fileURL in
            TextEditorView(fileURL: fileURL)
                .compatNavigationTransition(id: fileURL.absoluteString, ns: _namespace)
        }
        .fullScreenCover(item: $quickLookFileURL) { fileURL in
            QuickLookPreview(fileURL: fileURL)
                .compatNavigationTransition(id: fileURL.absoluteString, ns: _namespace)
        }
    }
    
    // MARK: - Content Views
    
    @ViewBuilder
    private var contentView: some View {
        List {
            ForEach(filteredFiles) { file in
                let isSelected = viewModel.selectedItems.contains(file)
                
                // دیزاینی App Store
                HStack(spacing: 15) {
                    if viewModel.isEditMode == .active {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundColor(isSelected ? .blue : .gray)
                            .padding(.trailing, 5)
                            .transition(.scale)
                    }
                    
                    Image(systemName: file.isAppDirectory ? "app.dashed" : (file.isDirectory ? "folder.fill" : "doc.fill"))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 45, height: 45)
                        .foregroundColor(file.isAppDirectory ? .purple : (file.isDirectory ? .blue : .gray))
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(file.name)
                            .font(.headline)
                            .lineLimit(1)
                        
                        Text(file.isAppDirectory ? "App / Package" : (file.isDirectory ? "Folder" : "Document"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if viewModel.isEditMode != .active {
                        GetButton(
                            fileSize: getFileSize(url: file.url),
                            action: {
                                if file.isAppDirectory {
                                    packageAppAsIPA(file)
                                } else if file.isArchive {
                                    extractArchive(file)
                                } else {
                                    importIpaToLibrary(file)
                                }
                            }
                        )
                    }
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .onTapGesture {
                    if viewModel.isEditMode == .active {
                        withAnimation(.spring()) {
                            if isSelected {
                                viewModel.selectedItems.remove(file)
                            } else {
                                viewModel.selectedItems.insert(file)
                            }
                        }
                    } else {
                        if file.isDirectory {
                            navigateToDirectory(file.url)
                        } else {
                            quickLookFileURL = file.url
                        }
                    }
                }
                .swipeActions(edge: .trailing) {
                    swipeActions(for: file)
                }
                .compatMatchedTransitionSource(id: file.url.absoluteString, ns: _namespace)
            }
        }
        .listStyle(.inset)
        .environment(\.editMode, $viewModel.isEditMode)
        .navigationDestination(isPresented: Binding(
            get: { navigateToDirectoryURL != nil },
            set: { if !$0 { navigateToDirectoryURL = nil } }
        )) {
            if let url = navigateToDirectoryURL {
                FilesView(directoryURL: url)
            }
        }
        .overlay {
            if filteredFiles.isEmpty {
                if #available(iOS 17, *) {
                    ContentUnavailableView {
                        Label(String(localized: "No Files"), systemImage: "folder.fill.badge.questionmark")
                    } description: {
                        Text(String(localized: "Get started by importing your first file."))
                    } actions: {
                        Button {
                            viewModel.showingImporter = true
                        } label: {
                            Text("Import Files")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(10)
                        }
                    }
                }
            }
        }
    }
    
    private var navigationTitle: String {
        if isRootView {
            return "Home"
        } else {
            if let directoryURL = directoryURL {
                return directoryURL.lastPathComponent
            } else {
                return viewModel.currentDirectory.lastPathComponent
            }
        }
    }
    
    private func getFileSize(url: URL) -> String {
        do {
            let resources = try url.resourceValues(forKeys: [.fileSizeKey])
            if let size = resources.fileSize {
                let formatter = ByteCountFormatter()
                formatter.allowedUnits = [.useMB, .useGB, .useKB]
                formatter.countStyle = .file
                return formatter.string(fromByteCount: Int64(size))
            }
        } catch {
            return "Unknown"
        }
        return "0 KB"
    }

    private func setupView() {
        viewModel.loadFiles()
    }
    
    private var addButton: some View {
        Menu {
            Button {
                viewModel.showingImporter = true
            } label: {
                Label(String(localized: "Import Files"), systemImage: "doc.badge.plus")
            }
            Button {
                UIAlertController.showAlertWithTextBox(
                    title: .localized("New Folder"),
                    message: .localized("Enter a name for the new folder"),
                    textFieldPlaceholder: .localized("Folder name"),
                    submit: .localized("Create"),
                    cancel: .localized("Cancel"),
                    onSubmit: { name in
                        viewModel.createNewFolder(name: name)
                    }
                )
            } label: {
                Label(String(localized: "New Folder"), systemImage: "folder.badge.plus")
            }
            Button {
                UIAlertController.showAlertWithTextBox(
                    title: .localized("New Text File"),
                    message: .localized("Enter a name for the new text file"),
                    textFieldPlaceholder: .localized("Text file name"),
                    textFieldText: "Unnamed.txt",
                    submit: .localized("Create"),
                    cancel: .localized("Cancel"),
                    onSubmit: { name in
                       viewModel.createNewTextFile(name: name)
                    }
                )
            } label: {
                Label(String(localized: "New Text File"), systemImage: "doc.badge.plus")
            }
        } label: {
            Image(systemName: "plus")
        }
        .menuStyle(BorderlessButtonMenuStyle())
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
    }
    
    private var editButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                viewModel.isEditMode = viewModel.isEditMode == .active ? .inactive : .active
                if viewModel.isEditMode == .inactive {
                    viewModel.selectedItems.removeAll()
                }
            }
        } label: {
            Text(viewModel.isEditMode == .active ? String(localized: "Done") : String(localized: "Edit"))
        }
    }
    
    private var selectAllButton: some View {
        Button {
            if viewModel.selectedItems.isEmpty {
                for file in viewModel.files {
                    viewModel.selectedItems.insert(file)
                }
            } else {
                viewModel.selectedItems.removeAll()
            }
        } label: {
            Image(systemName: viewModel.selectedItems.isEmpty ? "checklist.checked" : "checklist.unchecked")
        }
    }
    
    private var moveButton: some View {
        Button {
            viewModel.showDirectoryPicker = true
        } label: {
            Label(String(localized: "Move"), systemImage: "folder")
        }
        .disabled(viewModel.selectedItems.isEmpty)
    }
    
    private var shareButton: some View {
        Button {
            if !viewModel.selectedItems.isEmpty {
                let urls = viewModel.selectedItems.map { $0.url }
                shareItems = urls
                UIActivityViewController.show(activityItems: shareItems)
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .disabled(viewModel.selectedItems.isEmpty)
    }
    
    private var deleteButton: some View {
        Button(role: .destructive) {
            viewModel.deleteSelectedItems()
        } label: {
            Image(systemName: "trash")
        }
        .tint(.red)
        .disabled(viewModel.selectedItems.isEmpty)
    }
    
    private func navigateToDirectory(_ url: URL) {
        navigateToDirectoryURL = url
    }
    
    private func extractArchive(_ file: FileItem) {
        guard file.isArchive else { return }
        
        let extractItem = ExtractManager.shared.start(fileName: file.name)
        ExtractionService.extractArchive(
            file,
            to: viewModel.currentDirectory,
            progressCallback: { progress in
                DispatchQueue.main.async {
                    ExtractManager.shared.updateProgress(for: extractItem, progress: progress)
                }
            }
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    withAnimation {
                        self.viewModel.loadFiles()
                    }
                case .failure:
                    UIAlertController.showAlertWithOk(title: .localized("Error"), message: .localized("Whoops!, something went wrong when extracting the file."))
                }
                ExtractManager.shared.finish(item: extractItem)
            }
        }
    }
    
    private func packageAppAsIPA(_ file: FileItem) {
        guard file.isAppDirectory else { return }
        
        let extractItem = ExtractManager.shared.start(fileName: file.name)
        ExtractionService.packageAppAsIPA(
            file,
            to: viewModel.currentDirectory,
            progressCallback: { progress in
                DispatchQueue.main.async {
                    ExtractManager.shared.updateProgress(for: extractItem, progress: progress)
                }
            }
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let ipaFileName):
                    self.viewModel.loadFiles()
                    UIAlertController.showAlertWithOk(title: .localized("Success"), message: .localized("Successfully packaged \(file.name) as \(ipaFileName)"))
                case .failure(let error):
                    UIAlertController.showAlertWithOk(title: .localized("Error"), message: .localized("Failed to package IPA: \(error.localizedDescription)"))
                }
                ExtractManager.shared.finish(item: extractItem)
            }
        }
    }
    
    private func importIpaToLibrary(_ file: FileItem) {
        let id = "FeatherManualDownload_\(UUID().uuidString)"
        let download = self.downloadManager.startArchive(from: file.url, id: id)
        downloadManager.handlePachageFile(url: file.url, dl: download) { err in
            DispatchQueue.main.async {
                if let error = err {
                    UIAlertController.showAlertWithOk(title: .localized("Error"), message: .localized("Whoops!, something went wrong when extracting the file."))
                }
                if let index = DownloadManager.shared.getDownloadIndex(by: download.id) {
                    DownloadManager.shared.downloads.remove(at: index)
                }
            }
        }
    }

    @ViewBuilder
    private func swipeActions(for file: FileItem) -> some View {
        FileUIHelpers.swipeActions(for: file, viewModel: viewModel)
    }

    @ViewBuilder
    private func _sortActions() -> some View {
        Section(.localized("Filter by")) {
            ForEach(FilesViewModel.SortOption.allCases, id: \.displayName) { opt in
                _sortButton(for: opt)
            }
        }
    }

    private func _sortButton(for option: FilesViewModel.SortOption) -> some View {
        Button {
            if viewModel.sortOption == option {
                viewModel.updateSort(option: option, ascending: !viewModel.sortAscending)
            } else {
                viewModel.updateSort(option: option, ascending: true)
            }
        } label: {
            HStack {
                Text(option.displayName)
                Spacer()
                if viewModel.sortOption == option {
                    Image(systemName: viewModel.sortAscending ? "chevron.up" : "chevron.down")
                }
            }
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
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    isDownloading = false
                }
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
                            .background(Color(.systemGray6))
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

// MARK: - App Store Models & Views

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
                    self?.errorMessage = "هەڵە هەیە: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else { return }
                
                do {
                    // ئەگەر فایلەکەت لیستی ئەپەکانە بەبێ وشەی 'apps' ئەوا بەم شێوەیە دەیخوێنینەوە:
                    if let decodedArray = try? JSONDecoder().decode([AppItem].self, from: data) {
                        self?.apps = decodedArray
                    } 
                    // ئەگەر بە شێوەی Object ە، بەم شێوەیە دەیخوێنینەوە:
                    else if let decodedResponse = try? JSONDecoder().decode(AppStoreResponse.self, from: data) {
                        self?.apps = decodedResponse.apps
                    } else {
                        self?.errorMessage = "نەتوانرا داتاکان بخوێنرێتەوە."
                    }
                }
            }
        }.resume()
    }
    
    func formatSize(_ size: Int64?) -> String {
        guard let size = size else { return "Unknown" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

struct StoreView: View {
    @StateObject private var viewModel = StoreViewModel()
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                if viewModel.isLoading {
                    ProgressView("خەریکی هێنانی یارییەکانە...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                        .scaleEffect(1.2)
                } else if let errorMessage = viewModel.errorMessage {
                    VStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundColor(.red)
                        Text(errorMessage)
                            .multilineTextAlignment(.center)
                            .padding()
                        Button("دووبارە هەوڵبدەرەوە") {
                            viewModel.fetchApps()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(viewModel.apps) { app in
                            HStack(spacing: 15) {
                                AsyncImage(url: URL(string: app.iconURL ?? "")) { image in
                                    image.resizable()
                                } placeholder: {
                                    Color.gray.opacity(0.3)
                                        .overlay(ProgressView())
                                }
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 55, height: 55)
                                .cornerRadius(12)
                                .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 2)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(app.name)
                                        .font(.headline)
                                        .lineLimit(1)
                                    
                                    Text(app.developerName ?? "AshteMobile")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                GetButton(
                                    fileSize: viewModel.formatSize(app.size),
                                    action: {
                                        // لێرەدا دەتوانیت فەرمانی داگرتن بنێریت بۆ DownloadManager
                                        if let downloadURLString = app.downloadURL, let url = URL(string: downloadURLString) {
                                            print("دەست بە داگرتن کرا لە: \(url)")
                                            // بۆ نموونە: DownloadManager.shared.startDownload(...)
                                        }
                                    }
                                )
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Store")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("داخستن") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                if viewModel.apps.isEmpty {
                    viewModel.fetchApps()
                }
            }
        }
    }
}
