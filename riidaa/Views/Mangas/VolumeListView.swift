//
//  VolumeListView.swift
//  riidaa
//
//  Created by Pierre on 2025/02/16.
//

import SwiftUI
import ZIPFoundation
import CoreData

struct VolumeListView: View {
    
    @Environment(\.managedObjectContext) var moc
    
    @ObservedObject var manga: MangaModel
    @State private var isPickingVolume = false
    @StateObject var processingModel = VolumeProcessingModel()
    
    private var dismissDisabled: Bool {
        return processingModel.status == ProcessingStatus.STARTED
    }
    
    @State private var readingVolume: MangaVolumeModel? = nil
    
    @State private var editVolume: MangaVolumeModel? = nil
    @State private var editVolumeNumber: String = ""
    
    @State private var reuploadVolume: MangaVolumeModel? = nil
    
    @State private var refreshID = UUID()
    
    @State private var showMissingFileAlert = false
    @State private var missingFileInfo: (volumeNumber: Int64, fileName: String, pageNumber: Int)? = nil
    @State private var pendingProcessingTask: Task<Void, Never>? = nil
    @State private var skipMissingFiles = false
    
    private var missingFileAlertMessage: Text {
        if let info = missingFileInfo {
            let volumeText = "Volume \(info.volumeNumber), Page \(info.pageNumber):"
            let fileText = "\"\(info.fileName)\" not found in the folder."
            let questionText = "A placeholder image will be created for missing files.\n\nDo you want to continue?"
            return Text("\(volumeText)\n\(fileText)\n\n\(questionText)")
        } else {
            return Text("")
        }
    }
    
    var body: some View {
        mainContent
            .fullScreenCover(item: $readingVolume) { v in
                MangaReader(volume: .constant(v), currentPage: Int(v.lastReadPage))
            }
            .alert("Edit volume", isPresented: editVolumeAlertBinding, actions: editVolumeActions)
            .alert("Missing Image File", isPresented: $showMissingFileAlert, actions: missingFileActions, message: {
                missingFileAlertMessage
            })
    }
    
    private var editVolumeAlertBinding: Binding<Bool> {
        .init(get: { editVolume != nil }, set: { v in
            if !v {
                editVolume = nil
            }
        })
    }
    
    @ViewBuilder
    private func editVolumeActions() -> some View {
        TextField("New Volume Number", text: $editVolumeNumber)
            .keyboardType(.numberPad)
        Button("Cancel", role: .cancel) {
            editVolume = nil
        }
        Button("OK") {
            if let newNumber = Int64(editVolumeNumber.trimmingCharacters(in: .whitespacesAndNewlines)),
               newNumber > 0 {
                editVolume?.changeVolumeNumber(newNumber: newNumber)
                CoreDataManager.shared.saveContext()
            }
            editVolume = nil
        }
    }
    
    @ViewBuilder
    private func missingFileActions() -> some View {
        Button("Cancel Import", role: .cancel) {
            pendingProcessingTask?.cancel()
            processingModel.status = .ERROR
            processingModel.message = "Import cancelled by user"
            missingFileInfo = nil
        }
        Button("Continue with Placeholders") {
            skipMissingFiles = true
            showMissingFileAlert = false
        }
    }
    
    private var mainContent: some View {
        ScrollView {
            // TODO: word tracker
            ForEach((manga.volumes.array as! [MangaVolumeModel]).sorted()) { volume in
                Button {
                    readingVolume = volume
                } label: {
                    VolumeComponent(volume: volume, refreshTrigger: refreshID)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal)
                .padding(.vertical, 5)
                .contextMenu {
                    if volumeHasImages(volume) {
                        Button(role: .destructive) {
                            deleteVolume(volume)
                        } label: {
                            Label("Delete volume", systemImage: "trash")
                        }
                    } else {
                        Button {
                            reuploadVolume = volume
                            isPickingVolume = true
                        } label: {
                            Label("Reupload volume", systemImage: "arrow.clockwise")
                        }
                    }
                    Button {
                        editVolume = volume
                        editVolumeNumber = String(volume.number)
                    } label: {
                        Label("Edit volume number", systemImage: "pencil")
                    }
                }
            }
        }
        .navigationTitle(manga.title)
        .toolbar {
            Button(action: {
                self.isPickingVolume = true
            }) {
                Image(systemName: "plus")
            }
        }
        .fileImporter(isPresented: $isPickingVolume, allowedContentTypes: [.zip]) { result in
            self.processingModel.message = "Processing volume..."
            self.processingModel.status = ProcessingStatus.STARTED
            self.processingModel.progressValue = 0
            self.processingModel.progressMaxValue = 0
            switch result {
            case .success(let file):
                skipMissingFiles = false
                let volumeToReupload = reuploadVolume
                reuploadVolume = nil  // Clear the reupload state
                pendingProcessingTask = Task {
                    await processZipFile(path: file, reuploadingVolume: volumeToReupload)
                }
            case .failure(let error):
                print("error while picking volume file: \(error)")
            }
        }
        .sheet(
            isPresented: .init(get: {
                return self.processingModel.status != ProcessingStatus.NOTHING && !showMissingFileAlert
            }, set: { _ in }),
            onDismiss: {
                if self.processingModel.status != ProcessingStatus.STARTED {
                    self.processingModel.status = ProcessingStatus.NOTHING
                }
            }
            
        ) {
            VolumeProcessing(processingModel: processingModel)
                .interactiveDismissDisabled(dismissDisabled)
        }
    }
    
    func volumeHasImages(_ volume: MangaVolumeModel) -> Bool {
        let fileManager = FileManager.default
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("mangas")
        let volumeFolder = documents.appendingPathComponent(manga.id.uuidString).appendingPathComponent(String(volume.number))
        return fileManager.fileExists(atPath: volumeFolder.path)
    }
    
    func deleteVolume(_ volume: MangaVolumeModel) {
        // Only delete image files from disk, keep metadata for reading history
        let fileManager = FileManager.default
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("mangas")
        let volumeFolder = documents.appendingPathComponent(manga.id.uuidString).appendingPathComponent(String(volume.number))
        
        do {
            if fileManager.fileExists(atPath: volumeFolder.path) {
                try fileManager.removeItem(at: volumeFolder)
                print("Deleted volume images: \(volumeFolder.path)")
            }
        } catch {
            print("Error deleting volume files: \(error)")
        }
        
        // Trigger UI refresh to show "No Images" state
        refreshID = UUID()
        
        // Keep CoreData metadata (reading history, progress, etc.)
        // If user re-uploads, images will be restored to existing structure
    }
}

extension VolumeListView {
    
    // Create a placeholder image with "Missing" text
    nonisolated func createMissingPlaceholder(width: Int32, height: Int32, fileName: String) -> UIImage {
        let size = CGSize(width: Int(width), height: Int(height))
        let renderer = UIGraphicsImageRenderer(size: size)
        
        let image = renderer.image { context in
            // Background
            UIColor.systemGray5.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            
            // Border
            UIColor.systemGray3.setStroke()
            context.cgContext.setLineWidth(4)
            context.cgContext.stroke(CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2))
            
            // Text
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            
            let mainText = "Missing Image"
            let fileText = fileName
            
            let mainAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: min(CGFloat(width) / 15, 60)),
                .foregroundColor: UIColor.systemGray,
                .paragraphStyle: paragraphStyle
            ]
            
            let fileAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: min(CGFloat(width) / 25, 40)),
                .foregroundColor: UIColor.systemGray2,
                .paragraphStyle: paragraphStyle
            ]
            
            let mainTextSize = mainText.size(withAttributes: mainAttrs)
            let fileTextSize = fileText.size(withAttributes: fileAttrs)
            
            let mainY = (size.height - mainTextSize.height - fileTextSize.height - 20) / 2
            let fileY = mainY + mainTextSize.height + 20
            
            mainText.draw(in: CGRect(x: 0, y: mainY, width: size.width, height: mainTextSize.height), withAttributes: mainAttrs)
            fileText.draw(in: CGRect(x: 0, y: fileY, width: size.width, height: fileTextSize.height), withAttributes: fileAttrs)
        }
        
        return image
    }
    
    nonisolated func processZipFile(path: URL, reuploadingVolume: MangaVolumeModel? = nil) async {
        let mangaId = await manga.id
        let reuploadVolumeNumber: Int64? = await reuploadingVolume?.number
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let backgroundContext = CoreDataManager.shared.container.newBackgroundContext()
        
        do {
            var mangaInContext: MangaModel? = nil
            try await backgroundContext.perform {
                let fetchRequest: NSFetchRequest<MangaModel> = MangaModel.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", mangaId as CVarArg)
                mangaInContext = try backgroundContext.fetch(fetchRequest).first
            }
            guard let mangaInContext = mangaInContext else {
                throw NSError(domain: "VolumeProcessing", code: 0, userInfo: [NSLocalizedDescriptionKey: "Manga not found ??"])
            }
            
            if !path.startAccessingSecurityScopedResource() {
                throw NSError(domain: "VolumeProcessing", code: 0, userInfo: [NSLocalizedDescriptionKey: "Permission denied"])
            }
            defer {
                path.stopAccessingSecurityScopedResource()
            }
            try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            await MainActor.run {
                self.processingModel.message = "Extracting zip file..."
                self.processingModel.progressMaxValue = 1
            }
            try fileManager.unzipItem(at: path, to: tempDirectory)
            await MainActor.run {
                self.processingModel.message = "Extracted zip file."
                self.processingModel.progressValue = 1
            }
            
            var extractedItems = try fileManager.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent != "__MACOSX" }
            
            if extractedItems.count == 1,
               fileManager.isDirectory(at: extractedItems[0]) {
                let nestedFolder = extractedItems[0]
                extractedItems = try fileManager.contentsOfDirectory(at: nestedFolder, includingPropertiesForKeys: nil)
            }
            defer {
                try? fileManager.removeItem(at: tempDirectory)
            }
            
            let mokuroFiles = extractedItems.filter { $0.pathExtension == "mokuro" }
            for mokuroFile in mokuroFiles {
                let imagesFolder = URL(string: mokuroFile.absoluteString.replacingOccurrences(of: ".\(mokuroFile.pathExtension)", with: ""))
                guard let imagesFolder = imagesFolder else {
                    throw NSError(domain: "VolumeProcessing", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(mokuroFile) doesn't have an associated image folder"])
                }
                if !fileManager.isDirectory(at: imagesFolder) {
                    continue
                }
                let mokuroData = try Data(contentsOf: mokuroFile)
                guard let mokuroJson = try JSONSerialization.jsonObject(with: mokuroData, options: []) as? [String: Any] else {
                    throw NSError(domain: "VolumeProcessing", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON format"])
                }
                
                guard let volumeName = mokuroJson["volume"] as? String,
                      let titleName = mokuroJson["title"] as? String else {
                    throw NSError(domain: "VolumeProcessing", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing 'volume' or 'title' in mokuro \(mokuroFile)"])
                }
                let volumeNum: Int64?
                
                let regex = try! NSRegularExpression(pattern: "\\d+")
                let matches = regex.matches(in: volumeName, range: NSRange(volumeName.startIndex..., in: volumeName))

                if let lastMatch = matches.last,
                   let range = Range(lastMatch.range, in: volumeName) {
                    let numberString = String(volumeName[range])
                    volumeNum = Int64(numberString)
                } else {
                    let v1 = volumeName.replacingOccurrences(of: titleName, with: "").dropFirst(2)
                    volumeNum = Int64(v1)
                }
                guard let volumeNumber = volumeNum else {
                    throw NSError(domain: "VolumeProcessing", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid volume number in: \(volumeName)"])
                }
                print("volume \(volumeNumber)")
                
                // Check if volume already exists (for re-upload scenario)
                var existingVolume: MangaVolumeModel? = nil
                await backgroundContext.perform {
                    for vol in mangaInContext.volumes.array as! [MangaVolumeModel] {
                        if vol.number == volumeNumber {
                            existingVolume = vol
                            break
                        }
                    }
                }
                
                // If reuploading a specific volume, force use of that volume
                if let reuploadNum = reuploadVolumeNumber, reuploadNum == volumeNumber {
                    if existingVolume == nil {
                        throw NSError(domain: "VolumeProcessing", code: 5, userInfo: [NSLocalizedDescriptionKey: "Cannot find volume \(volumeNumber) to reupload"])
                    }
                    print("Forcing reupload of volume \(volumeNumber)")
                }
                // If volume exists and NOT explicitly reuploading, check if images are present
                else if let existing = existingVolume {
                    let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("mangas")
                    let existingVolumeFolder = documents.appendingPathComponent(mangaInContext.id.uuidString).appendingPathComponent(String(volumeNumber))
                    
                    if fileManager.fileExists(atPath: existingVolumeFolder.path) {
                        // Images exist, don't allow re-upload
                        throw NSError(domain: "VolumeProcessing", code: 5, userInfo: [NSLocalizedDescriptionKey: "Volume \(volumeNumber) already exists with images. Delete it first to re-upload."])
                    } else {
                        // Images were deleted, allow re-upload
                        print("Re-uploading images for existing volume \(volumeNumber)")
                    }
                }
                
                var newVolume: MangaVolumeModel? = nil
                if let existing = existingVolume {
                    // Re-use existing volume (re-upload scenario)
                    newVolume = existing
                    print("Re-using existing volume \(volumeNumber) metadata")
                } else {
                    // Create new volume
                    await backgroundContext.perform {
                        newVolume = MangaVolumeModel(context: backgroundContext)
                        newVolume!.number = volumeNumber
                        mangaInContext.addToVolumes(newVolume!)
                    }
                }
                guard let newVolume = newVolume else {
                    throw NSError(domain: "VolumeProcessing", code: 0, userInfo: [NSLocalizedDescriptionKey: "Volume is nil"])
                }
                
                // If re-uploading, clear old pages first
                if existingVolume != nil {
                    await backgroundContext.perform {
                        // Remove all existing pages
                        let pagesToRemove = newVolume.pages.array as! [MangaPageModel]
                        for page in pagesToRemove {
                            backgroundContext.delete(page)
                        }
                    }
                }
                
                // pages
                guard let pages = mokuroJson["pages"] as? [[String: Any]] else {
                    throw NSError(domain: "VolumeProcessing", code: 6, userInfo: [NSLocalizedDescriptionKey: "Missing pages in mokuro"])
                }
                
                await MainActor.run {
                    self.processingModel.message = "Processing volume \(volumeNumber)."
                    self.processingModel.progressMaxValue = pages.count
                }
                
                let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("mangas")
                let volumeDirectory = documents.appendingPathComponent(mangaInContext.id.uuidString).appendingPathComponent(String(newVolume.number))
                
                // If reuploading, delete old images first
                if existingVolume != nil && fileManager.fileExists(atPath: volumeDirectory.path) {
                    try? fileManager.removeItem(at: volumeDirectory)
                    print("Removed old volume images for reupload")
                }
                
                try fileManager.createDirectory(at: volumeDirectory, withIntermediateDirectories: true)
                
                for (i, page) in pages.enumerated() {
                    guard let img_path = page["img_path"] as? String,
                          let img_width = page["img_width"] as? Int32,
                          let img_height = page["img_height"] as? Int32 else {
                        throw NSError(domain: "VolumeProcessing", code: 6, userInfo: [NSLocalizedDescriptionKey: "Missing image infos"])
                    }
                    let img = imagesFolder.appendingPathComponent(img_path)
                    let destImg = volumeDirectory.appendingPathComponent(img_path)
                    
                    // Check if source image exists before trying to move it
                    if !fileManager.fileExists(atPath: img.path) {
                        print("Warning: Image file not found - Volume \(volumeNumber), Page \(i + 1): \(img_path)")
                        
                        // Check if user has chosen to skip missing files
                        let shouldSkip = await MainActor.run { self.skipMissingFiles }
                        
                        // If user hasn't chosen to skip missing files yet, prompt them
                        if !shouldSkip {
                            await MainActor.run {
                                self.missingFileInfo = (volumeNumber: volumeNumber, fileName: img_path, pageNumber: i + 1)
                                self.showMissingFileAlert = true
                            }
                            
                            // Wait for user decision
                            while true {
                                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                                
                                let skip = await MainActor.run { self.skipMissingFiles }
                                let alertStillShowing = await MainActor.run { self.showMissingFileAlert }
                                
                                // User tapped Skip & Continue
                                if skip {
                                    break
                                }
                                
                                // User tapped Cancel (alert dismissed without setting skip)
                                if !alertStillShowing {
                                    throw NSError(domain: "VolumeProcessing", code: 7, userInfo: [NSLocalizedDescriptionKey: "Import cancelled by user"])
                                }
                            }
                        }
                        
                        // Create placeholder image for missing file
                        let placeholder = createMissingPlaceholder(width: img_width, height: img_height, fileName: img_path)
                        guard let pngData = placeholder.pngData() else {
                            throw NSError(domain: "VolumeProcessing", code: 8, userInfo: [NSLocalizedDescriptionKey: "Failed to create placeholder image"])
                        }
                        
                        try? fileManager.removeItem(at: destImg)
                        try pngData.write(to: destImg)
                        print("Created placeholder image for: \(img_path)")
                    } else {
                        // Move actual image file
                        try? fileManager.removeItem(at: destImg)
                        print("Source image path: \(img.path), exists: \(fileManager.fileExists(atPath: img.path))")
                        print("image path: \(imagesFolder.path), exists: \(fileManager.fileExists(atPath: imagesFolder.path))")
                        print("Destination image path: \(destImg.path), exists: \(fileManager.fileExists(atPath: destImg.path))")
                        try fileManager.moveItem(at: img, to: destImg)
                    }
                    
                    var newPage: MangaPageModel? = nil
                    await backgroundContext.perform {
                        newPage = MangaPageModel(context: backgroundContext)
                        newVolume.addToPages(newPage!)
                        newPage!.number = Int64(i + 1)
                        newPage!.image = img_path
                        newPage!.width = img_width
                        newPage!.height = img_height
                    }
                    guard let newPage = newPage else {
                        throw NSError(domain: "VolumeProcessing", code: 6, userInfo: [NSLocalizedDescriptionKey: "newPage is nil"])
                    }
                    
                    // Text boxes
                    guard let blocks = page["blocks"] as? [[String: Any]] else {
                        continue
                    }
                    
                    for block in blocks {
                        guard let box = block["box"] as? [Int32], let lines = block["lines"] as? [String] else {
                            throw NSError(domain: "VolumeProcessing", code: 6, userInfo: [NSLocalizedDescriptionKey: "Error while parsing OCR block"])
                        }
                        let rotation = block["rotation"] as? Double
                        
                        await backgroundContext.perform {
                            let pageBlock = PageBoxModel(context: backgroundContext)
                            pageBlock.x = box[0]
                            pageBlock.y = box[1]
                            pageBlock.width = (box[2] - box[0])
                            pageBlock.height = (box[3] - box[1])
                            pageBlock.text = lines.joined()
                            pageBlock.rotation = rotation ?? 0
                            
                            newPage.addToBoxes(pageBlock)
                        }
                    }
                    await MainActor.run {
                        self.processingModel.progressValue = i
                    }
                }
            }
            
            try await backgroundContext.perform {
                try backgroundContext.save()
            }
        } catch {
            await MainActor.run {
                self.processingModel.status = ProcessingStatus.ERROR
                self.processingModel.message = error.localizedDescription
            }
        }
        await MainActor.run {
            if self.processingModel.status != ProcessingStatus.ERROR {
                self.processingModel.status = ProcessingStatus.FINISHED
                // Refresh UI to update volume indicators
                self.refreshID = UUID()
            }
        }
    }
    
}

enum ProcessingStatus {
    case NOTHING,
         STARTED,
         FINISHED,
         ERROR
}

class VolumeProcessingModel: ObservableObject {
    @Published var status: ProcessingStatus = .NOTHING
    @Published var message: String = "Processing volume..."
    @Published var progressValue: Int = 0
    @Published var progressMaxValue: Int = 0
}


struct VolumeProcessing: View {
    
    @ObservedObject var processingModel: VolumeProcessingModel
    
    var body: some View {
        VStack(spacing: 40) {
            switch processingModel.status {
            case .STARTED:
                CircularProgressView(progress: processingModel.progressValue, progressMax: processingModel.progressMaxValue)
                    .frame(width: 150, height: 150)
                
            case .FINISHED:
                Image(systemName: "checkmark")
                    .scaleEffect(4)
                    .frame(width: 150, height: 150)
            case .ERROR:
                Image(systemName: "xmark")
                    .scaleEffect(4)
                    .frame(width: 150, height: 150)
            case .NOTHING:
                EmptyView()
            }
            Text(processingModel.message)
                .font(.largeTitle)
                .multilineTextAlignment(.center)
                .padding()
            
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
}

#Preview {
    VolumeListView(
        manga: CoreDataManager.sampleManga
    )
    .environment(\.managedObjectContext, CoreDataManager.shared.container.viewContext)
    .onAppear(perform: {
        print(CoreDataManager.sampleManga)
    })
}
