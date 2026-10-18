import Foundation
public import RiveRuntime

@MainActor
public final class RiveResource {
    private let file: RiveRuntime.File

    private init(_ file: RiveRuntime.File) { self.file = file }

    public static func load(named name: String, in bundle: Bundle) async throws -> RiveResource {
        try Task.checkCancellation()
        let worker = try await Worker()
        try Task.checkCancellation()
        let decoded = try await RiveRuntime.File(source: .local(name, bundle), worker: worker)
        try Task.checkCancellation()
        return RiveResource(decoded)
    }

    public func makeSession(_ contract: RiveContract) async throws -> RiveSession {
        try await validate(contract)
        let surface = try await file.createArtboard(contract.artboard)
        try Task.checkCancellation()
        let machine = try await surface.createStateMachine(contract.stateMachine)
        try Task.checkCancellation()
        let binding = try await file.createViewModelInstance(.viewModelDefault(from: .name(contract.viewModel)))
        try Task.checkCancellation()
        let playback = try await Rive(file: file, artboard: surface, stateMachine: machine, dataBind: .instance(binding))
        try Task.checkCancellation()
        return RiveSession(rive: playback, data: binding)
    }

    private func validate(_ contract: RiveContract) async throws {
        try Task.checkCancellation()
        let exported = try await file.getProperties(of: contract.viewModel)
        try Task.checkCancellation()
        for name in contract.properties.keys.sorted() {
            guard exported.contains(where: { $0.name == name && $0.type == contract.properties[name] }) else {
                throw RiveContractError.property(viewModel: contract.viewModel, name: name)
            }
        }
    }
}

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

@MainActor
public final class RiveSession {
    public let rive: Rive
    public let data: ViewModelInstance

    init(rive: Rive, data: ViewModelInstance) {
        self.rive = rive
        self.data = data
    }
}
