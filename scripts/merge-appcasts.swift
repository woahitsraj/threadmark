#!/usr/bin/env swift

import Foundation

guard CommandLine.arguments.count == 4 else {
    fatalError("Usage: merge-appcasts.swift <primary> <secondary> <output>")
}

let primary = try XMLDocument(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let secondary = try XMLDocument(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
guard let channel = try primary.nodes(forXPath: "/rss/channel").first as? XMLElement else {
    fatalError("Primary appcast has no channel")
}

for item in try secondary.nodes(forXPath: "/rss/channel/item") {
    channel.addChild(item.copy() as! XMLNode)
}

try primary.xmlData(options: .nodePrettyPrint).write(
    to: URL(fileURLWithPath: CommandLine.arguments[3]),
    options: .atomic
)
