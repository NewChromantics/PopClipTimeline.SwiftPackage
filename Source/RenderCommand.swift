import SwiftUI
import PopMetalView
import MetalKit
import MouseTracking
import PopCommon


public struct MTLRenderDescriptorAndState
{
	var descriptor : MTLRenderPipelineDescriptor
	var state : MTLRenderPipelineState
	
	public init(metalView:MTKView,shaderInBundle:Bundle,vertexShaderName:String,fragShaderName:String) throws
	{
		let shaderLibrary = try shaderInBundle.GetShaderLibrary(metalView: metalView)
		self.descriptor = try Self.CreateDescriptor(metalView:metalView, shaderLibrary: shaderLibrary, vertexShaderName: vertexShaderName, fragShaderName: fragShaderName)
		self.state = try metalView.device!.makeRenderPipelineState(descriptor: self.descriptor)
	}
	
	static private func CreateDescriptor(metalView:MTKView,shaderLibrary:MTLLibrary,vertexShaderName:String,fragShaderName:String) throws -> MTLRenderPipelineDescriptor
	{
		//let device = metalView.device!
		let pipelineDescriptor = MTLRenderPipelineDescriptor()
		
		guard let vertexFunc = shaderLibrary.makeFunction(name: vertexShaderName) else
		{
			throw RuntimeError("Missing function \(vertexShaderName)")
		}
		guard let fragFunc = shaderLibrary.makeFunction(name: fragShaderName) else
		{
			throw RuntimeError("Missing function \(fragShaderName)")
		}
		pipelineDescriptor.vertexFunction = vertexFunc
		pipelineDescriptor.fragmentFunction = fragFunc		
		let attachment = pipelineDescriptor.colorAttachments[0]!
		attachment.pixelFormat = metalView.colorPixelFormat
		
		
		pipelineDescriptor.depthAttachmentPixelFormat = metalView.depthStencilPixelFormat
		
		attachment.isBlendingEnabled = true
		attachment.rgbBlendOperation = .add
		attachment.alphaBlendOperation = .add
		attachment.sourceRGBBlendFactor = .sourceAlpha
		attachment.sourceAlphaBlendFactor = .one
		attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
		attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
		
		return pipelineDescriptor
	}
}

//	to make render-command/shader function bundles simpler, conform to this protocol
public protocol RenderCommand
{
	//	config per-shader implementation
	static var vertexShaderName : String { get }
	//var vertexBuffer_clips = 0
	static var fragShaderName : String { get }
	
	var descriptorAndState : MTLRenderDescriptorAndState!	{ get set }
	//var descriptor : MTLRenderPipelineDescriptor { get }
	//var state : MTLRenderPipelineState { get }
	
	//init(metalView:MTKView,shaderLibrary:MTLLibrary) throws
	init(metalView:MTKView,shaderInBundle:Bundle) throws
}

public extension RenderCommand
{
	var descriptor : MTLRenderPipelineDescriptor { descriptorAndState.descriptor }
	var state : MTLRenderPipelineState { descriptorAndState.state }
	

	mutating func initDescriptor(metalView:MTKView,shaderInBundle:Bundle) throws
	{
		self.descriptorAndState = try MTLRenderDescriptorAndState(metalView: metalView, shaderInBundle: shaderInBundle, vertexShaderName: Self.vertexShaderName, fragShaderName: Self.fragShaderName)
	}
	
}

public extension Bundle
{
	func GetShaderLibrary(metalView:MTKView) throws -> MTLLibrary
	{
		return try GetShaderLibrary(device: metalView.device!)
	}
	
	func GetShaderLibrary(device:MTLDevice) throws -> MTLLibrary
	{
		return try device.makeDefaultLibrary(bundle: self)
	}
}
