// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.


import PackageDescription



let package = Package(
	name: "PopClipTimeline",
	
	platforms: [
		.iOS(.v17),
		.macOS(.v14)
	],
	

	products: [
		.library(
			name: "PopClipTimeline",
			targets: [
				"PopClipTimeline"
			]),
	],
	
	
	dependencies: [
		.package(url: "https://github.com/NewChromantics/PopCommon.SwiftPackage", branch: "main" ),
		.package(url: "https://github.com/NewChromantics/PopMetalView.SwiftPackage", branch: "main" ),		
	],
	
	targets: [

		.target(
			name: "PopClipTimeline",
			dependencies: 
				[
					.product(name: "PopCommon", package: "PopCommon.SwiftPackage"),
					.product(name: "PopMetalView", package: "PopMetalView.SwiftPackage"),
				]
		)
	]
)
