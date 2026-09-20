import Foundation
public import RiveRuntime

/// A decoded, local file. Retain this at the feature's lifetime to share parsing and its worker.
/// Every call to makeSession creates independent mutable playback and data-binding state.
@MainActor
public final class RiveResource {
    private let file: RiveRuntime.File

    private init(file: RiveRuntime.File) { self.file = file }

    public static func load(named name: String, in bundle: Bundle) async throws -> RiveResource {
        try Task.checkCancellation()
        let worker = try await Worker()
        try Task.checkCancellation()
        let file = try await RiveRuntime.File(source: .local(name, bundle), worker: worker)
        try Task.checkCancellation()
        return RiveResource(file: file)
    }

    public func makeSession(_ contract: RiveContract) async throws -> RiveSession {
        try Task.checkCancellation()
        let properties = try await file.getProperties(of: contract.viewModel)
        try Task.checkCancellation()
        for (name, type) in contract.properties {
            guard properties.contains(where: { $0.name == name && $0.type == type }) else {
                throw RiveContractError.property(viewModel: contract.viewModel, name: name)
            }
        }
        let artboard = try await file.createArtboard(contract.artboard)
        try Task.checkCancellation()
        let machine = try await artboard.createStateMachine(contract.stateMachine)
        try Task.checkCancellation()
        let instance = try await file.createViewModelInstance(.viewModelDefault(from: .name(contract.viewModel)))
        try Task.checkCancellation()
        let rive = try await Rive(file: file, artboard: artboard, stateMachine: machine, dataBind: .instance(instance))
        try Task.checkCancellation()
        return RiveSession(rive: rive, data: instance)
    }
}

/// Required root properties are checked against the actual exported file, before display.
public struct RiveContract: Sendable {
    public let artboard: String
    public let stateMachine: String
    public let viewModel: String
    public let properties: [String: ViewModelProperty.DataType]

    public init(artboard: String, stateMachine: String, viewModel: String,
                properties: [String: ViewModelProperty.DataType]) {
        self.artboard = artboard
        self.stateMachine = stateMachine
        self.viewModel = viewModel
        self.properties = properties
    }
}

public enum RiveContractError: Error {
    case property(viewModel: String, name: String)
}

/// One display owns one session. A session must never be mounted in two views at once.
@MainActor
public final class RiveSession {
    public let rive: Rive
    public let data: ViewModelInstance

    init(rive: Rive, data: ViewModelInstance) {
        self.rive = rive
        self.data = data
    }
}
