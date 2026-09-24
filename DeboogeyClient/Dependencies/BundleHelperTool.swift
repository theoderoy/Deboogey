//
//  BundleHelperTool.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 13/09/2026.
//

import Foundation

enum BundleHelperTool {
    enum ResolveError: Error {
        case notFound
        case outsideExpectedDirectory(path: String)
        case notExecutable(path: String)
    }

    static func path(
        resource: String?,
        auxiliaryExecutable: String? = nil,
        expectedDirectory: String
    ) throws -> String {
        let resolved: String?
        if let auxiliaryExecutable,
           let url = Bundle.main.url(forAuxiliaryExecutable: auxiliaryExecutable) {
            resolved = url.path
        } else if let resource {
            resolved = Bundle.main.path(forResource: resource, ofType: nil)
                ?? Bundle.main.url(forResource: resource, withExtension: nil)?.path
        } else {
            resolved = nil
        }
        guard let path = resolved else { throw ResolveError.notFound }
        if !path.contains(expectedDirectory) {
            throw ResolveError.outsideExpectedDirectory(path: path)
        }
        if !FileManager.default.isExecutableFile(atPath: path) {
            throw ResolveError.notExecutable(path: path)
        }
        return path
    }

    static func pathMapped<E: Error>(
        resource: String?,
        auxiliaryExecutable: String? = nil,
        expectedDirectory: String,
        map: (ResolveError) -> E
    ) throws -> String {
        do {
            return try path(
                resource: resource,
                auxiliaryExecutable: auxiliaryExecutable,
                expectedDirectory: expectedDirectory
            )
        } catch let error as ResolveError {
            throw map(error)
        } catch {
            throw map(.notFound)
        }
    }
}
