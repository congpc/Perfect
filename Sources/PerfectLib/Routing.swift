//
//  Routing.swift
//  PerfectLib
//
//  Created by Kyle Jessup on 2015-12-11.
//  Copyright © 2015 PerfectlySoft. All rights reserved.
//
//===----------------------------------------------------------------------===//
//
// This source file is part of the Perfect.org open source project
//
// Copyright (c) 2015 - 2016 PerfectlySoft Inc. and the Perfect project authors
// Licensed under Apache License v2.0
//
// See http://perfect.org/licensing.html for license information
//
//===----------------------------------------------------------------------===//
//


/// Holds the registered routes.
public struct RouteMap: CustomStringConvertible {
	
	public typealias RequestHandler = (WebRequest, WebResponse) -> ()
	
	/// Pretty prints all route information.
	public var description: String {
		var s = self.root.description
		for (method, root) in self.methodRoots {
			s.append("\n" + method + ":\n" + root.description)
		}
		return s
	}
	
	private let root = RouteNode() // root node for any request method
	private var methodRoots = [String:RouteNode]() // by convention, use all upper cased method names for inserts/lookups
	
	// Lookup a route based on the URL path.
	// Returns the handler generator if found.
	subscript(path: String, webResponse: WebResponse) -> RequestHandler? {
		get {
			let components = path.lowercased().pathComponents
			var g = components.makeIterator()
			let _ = g.next() // "/"
			
			let method = webResponse.request.requestMethod!.uppercased()
			if let root = self.methodRoots[method] {
				if let handler = root.findHandler("", generator: g, webResponse: webResponse) {
					return handler
				}
			}
			return self.root.findHandler("", generator: g, webResponse: webResponse)
		}
	}
	
	/// Add a route to the system.
	/// `Routing.Routes["/foo/*/baz"] = { _ in return ExampleHandler() }`
	public subscript(path: String) -> RequestHandler? {
		get {
			return nil // Swift does not currently allow set-only subscripts
		}
		set {
			self.root.addPathSegments(path.lowercased().pathComponents.makeIterator(), h: newValue!)
		}
	}
	
	/// Add an array of routes for a given handler.
	/// `Routing.Routes[ ["/", "index.html"] ] = { _ in return ExampleHandler() }`
	public subscript(paths: [String]) -> RequestHandler? {
		get {
			return nil
		}
		set {
			for path in paths {
				self[path] = newValue
			}
		}
	}
	
	/// Add a route to the system using the indicated HTTP request method.
	/// `Routing.Routes["GET", "/foo/*/baz"] = { _ in return ExampleHandler() }`
	public subscript(method: String, path: String) -> RequestHandler? {
		get {
			return nil // Swift does not currently allow set-only subscripts
		}
		set {
			let uppered = method.uppercased()
			if let root = self.methodRoots[uppered] {
				root.addPathSegments(path.lowercased().pathComponents.makeIterator(), h: newValue!)
			} else {
				let root = RouteNode()
				self.methodRoots[uppered] = root
				root.addPathSegments(path.lowercased().pathComponents.makeIterator(), h: newValue!)
			}
		}
	}
	
	/// Add an array of routes for a given handler using the indicated HTTP request method.
	/// `Routing.Routes["GET", ["/", "index.html"] ] = { _ in return ExampleHandler() }`
	public subscript(method: String, paths: [String]) -> RequestHandler? {
		get {
			return nil // Swift does not currently allow set-only subscripts
		}
		set {
			for path in paths {
				self[method, path] = newValue
			}
		}
	}
}

/// This wraps up the routing related functionality.
/// Enable the routing system by calling:
/// ```
/// Routing.Handler.registerGlobally()
/// ```
/// This should be done in your `PerfectServerModuleInit` function.
/// The system supports HTTP method based routing, wildcards and variables.
///
/// Add routes in the following manner:
/// ```
/// 	Routing.Routes["GET", ["/", "index.html"] ] = { (_:WebResponse) in return IndexHandler() }
/// 	Routing.Routes["/foo/*/baz"] = { _ in return EchoHandler() }
/// 	Routing.Routes["/foo/bar/baz"] = { _ in return EchoHandler() }
/// 	Routing.Routes["GET", "/user/{id}/baz"] = { _ in return Echo2Handler() }
/// 	Routing.Routes["POST", "/user/{id}/baz"] = { _ in return Echo3Handler() }
/// ```
/// The closure you provide should return an instance of `PageHandler`. It is provided the WebResponse object to permit further customization.
/// Variables set by the routing process can be accessed through the `WebRequest.urlVariables` dictionary.
/// Note that a PageHandler *MUST* call `WebResponse.requestCompleted()` when the request has completed.
/// This does not need to be done within the `handleRequest` method.
public class Routing {
	
	/// The routes which have been configured.
	static public var Routes = RouteMap()
	
	private init() {}
	
	/// Handle the request, triggering the routing system.
	/// If a route is discovered the request is sent to the new handler.
	public static func handleRequest(request: WebRequest, response: WebResponse) {
		let pathInfo = request.requestURI?.characters.split(separator: "?").map { String($0) }.first ?? "/"
		
		if let handler = Routing.Routes[pathInfo, response] {
			handler(request, response)
		} else {
			response.setStatus(404, message: "NOT FOUND")
			response.appendBodyString("The file \(pathInfo) was not found.")
			response.requestCompleted()
		}
	}
	
}

class RouteNode: CustomStringConvertible {
	
	#if swift(>=3.0)
	typealias ComponentGenerator = IndexingIterator<[String]>
	#else
	typealias ComponentGenerator = IndexingGenerator<[String]>
	#endif
	
	var description: String {
		return self.descriptionTabbed(0)
	}
	
	private func putTabs(count: Int) -> String {
		var s = ""
		for _ in 0..<count {
			s.append("\t")
		}
		return s
	}
	
	func descriptionTabbedInner(tabCount: Int) -> String {
		var s = ""
		for (_, node) in self.subNodes {
			s.append("\(self.putTabs(tabCount))\(node.descriptionTabbed(tabCount+1))")
		}
		for node in self.variables {
			s.append("\(self.putTabs(tabCount))\(node.descriptionTabbed(tabCount+1))")
		}
		if let node = self.wildCard {
			s.append("\(self.putTabs(tabCount))\(node.descriptionTabbed(tabCount+1))")
		}
		return s
	}
	
	func descriptionTabbed(tabCount: Int) -> String {
		var s = ""
		if let _ = self.handler {
			s.append("/+h\n")
		}
		s.append(self.descriptionTabbedInner(tabCount))
		return s
	}
	
	var handler: RouteMap.RequestHandler?
	var wildCard: RouteNode?
	var variables = [RouteNode]()
	var subNodes = [String:RouteNode]()
	
	func findHandler(currentComponent: String, generator: ComponentGenerator, webResponse: WebResponse) -> RouteMap.RequestHandler? {
		var m = generator
		if let p = m.next() where p != "/" {
			
			// variables
			for node in self.variables {
				if let h = node.findHandler(p, generator: m, webResponse: webResponse) {
					return self.successfulRoute(currentComponent, handler: node.successfulRoute(p, handler: h, webResponse: webResponse), webResponse: webResponse)
				}
			}
			
			// paths
			if let node = self.subNodes[p] {
				if let h = node.findHandler(p, generator: m, webResponse: webResponse) {
					return self.successfulRoute(currentComponent, handler: node.successfulRoute(p, handler: h, webResponse: webResponse), webResponse: webResponse)
				}
			}
			
			// wildcards
			if let node = self.wildCard {
				if let h = node.findHandler(p, generator: m, webResponse: webResponse) {
					return self.successfulRoute(currentComponent, handler: node.successfulRoute(p, handler: h, webResponse: webResponse), webResponse: webResponse)
				}
			}
			
		} else if self.handler != nil {
			
			return self.handler
			
		} else {
			// wildcards
			if let node = self.wildCard {
				if let h = node.findHandler("", generator: m, webResponse: webResponse) {
					return self.successfulRoute(currentComponent, handler: node.successfulRoute("", handler: h, webResponse: webResponse), webResponse: webResponse)
				}
			}
		}
		return nil
	}
	
	func successfulRoute(currentComponent: String, handler: RouteMap.RequestHandler, webResponse: WebResponse) -> RouteMap.RequestHandler {
		return handler
	}
	
	func addPathSegments(g: ComponentGenerator, h: RouteMap.RequestHandler) {
		var m = g
		if let p = m.next() {
			if p == "/" {
				self.addPathSegments(m, h: h)
			} else {
				self.addPathSegment(p, g: m, h: h)
			}
		} else {
			self.handler = h
		}
	}
	
	private func addPathSegment(component: String, g: ComponentGenerator, h: RouteMap.RequestHandler) {
		if let node = self.nodeForComponent(component) {
			node.addPathSegments(g, h: h)
		}
	}
	
	private func nodeForComponent(component: String) -> RouteNode? {
		guard !component.isEmpty else {
			return nil
		}
		if component == "*" {
			if self.wildCard == nil {
				self.wildCard = RouteWildCard()
			}
			return self.wildCard
		}
		if component.characters.count >= 3 && component[component.startIndex] == "{" && component[component.endIndex.predecessor()] == "}" {
			let node = RouteVariable(name: component.substringWith(component.startIndex.successor()..<component.endIndex.predecessor()))
			self.variables.append(node)
			return node
		}
		if let node = self.subNodes[component] {
			return node
		}
		let node = RoutePath(name: component)
		self.subNodes[component] = node
		return node
	}
	
}

class RoutePath: RouteNode {
	
	let name: String
	init(name: String) {
		self.name = name
	}
	
	override func descriptionTabbed(tabCount: Int) -> String {
		var s = "/\(self.name)"
		
		if let _ = self.handler {
			s.append("+h\n")
		} else {
			s.append("\n")
		}
		s.append(self.descriptionTabbedInner(tabCount))
		return s
	}
	
	// RoutePaths don't need to perform any special checking.
	// Their path is validated by the fact that they exist in their parent's `subNodes` dict.
}

class RouteWildCard: RouteNode {
	
	override func descriptionTabbed(tabCount: Int) -> String {
		var s = "/*"
		
		if let _ = self.handler {
			s.append("+h\n")
		} else {
			s.append("\n")
		}
		s.append(self.descriptionTabbedInner(tabCount))
		return s
	}
	
}

class RouteVariable: RouteNode {
	
	let name: String
	init(name: String) {
		self.name = name
	}
	
	override func descriptionTabbed(tabCount: Int) -> String {
		var s = "/{\(self.name)}"
		
		if let _ = self.handler {
			s.append("+h\n")
		} else {
			s.append("\n")
		}
		s.append(self.descriptionTabbedInner(tabCount))
		return s
	}
	
	override func successfulRoute(currentComponent: String, handler: RouteMap.RequestHandler, webResponse: WebResponse) -> RouteMap.RequestHandler {
		let request = webResponse.request
		if let decodedComponent = currentComponent.stringByDecodingURL {
			request.urlVariables[self.name] = decodedComponent
		} else {
			request.urlVariables[self.name] = currentComponent
		}
		return handler
	}
	
}







