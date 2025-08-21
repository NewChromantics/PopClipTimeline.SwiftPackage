import SwiftUI
import PopMetalView
import MetalKit
import MouseTracking
import PopCommon



public struct ClipTimelineError: LocalizedError
{
	let description: String
	
	public init(_ description: String) {
		self.description = description
	}
	
	public var errorDescription: String? {
		description
	}
}


//	match shader
public struct Clip : Equatable
{
	var column : UInt32
	var width : UInt32
	var row : UInt32
	var type : UInt32	//	selected etc
	
	public init(column: UInt32, width: UInt32, row: UInt32, type: UInt32) 
	{
		self.column = column
		self.width = width
		self.row = row
		self.type = type
	}
}

public struct TimelineCoord
{
	var x : Int32 = 0
	var y : Int32 = 0
	
	init(_ x:Int32,_ y:Int32)
	{
		self.x = x
		self.y = y
	}
}

public struct TimelineViewMeta
{
	var leftColumn : Int32 = 0
	var rowHeightPx : UInt32 = 40
	var rowGapPx : UInt32 = 1
	var columnWidthPx : Float = 5
	static var minColumnWidthPx : Float {	0.1	}
	static var maxColumnWidthPx : Float {	10	}
	
	//	todo: make functions here that match shader pixel<>data conversion for accurate UI conversion
	
	//	todo: y is wrong as pixel is upside down - need view height
	func PixelToCoord(_ x:CGFloat,_ y:CGFloat) -> TimelineCoord
	{
		//	apply zoom
		var xf = x / CGFloat(columnWidthPx)
		let yf = y / CGFloat(rowHeightPx+rowGapPx)
		
		//	apply scroll
		xf += CGFloat(leftColumn)
		
		
		return TimelineCoord( Int32(xf), Int32(yf) )
	}
}

//	gr: are little self contained render structs like this useful?
struct ClipBoxContentRenderDescriptor
{
	//	config per-shader implementation
	static var vertexShaderName = "ClipBoxVertex"
	var vertexBuffer_clips = 0
	var vertexBuffer_timelineViewMeta = 1
	var vertexBuffer_screenSize = 2
	static var fragShaderName = "ColourFrag"
	
	var descriptor : MTLRenderPipelineDescriptor
	var state : MTLRenderPipelineState
	
	
	init(metalView:MTKView,shaderLibrary:MTLLibrary?=nil) throws
	{
		let shaderLibrary = try shaderLibrary ?? (try metalView.device!.makeDefaultLibrary(bundle: Bundle.module))
		
		self.descriptor = try Self.CreateDescriptor(metalView:metalView, shaderLibrary: shaderLibrary)
		self.state = try metalView.device!.makeRenderPipelineState(descriptor: self.descriptor)
	}
	
	
	static private func CreateDescriptor(metalView:MTKView,shaderLibrary:MTLLibrary) throws -> MTLRenderPipelineDescriptor
	{
		let device = metalView.device!
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
	
	
	func Render(clips:[Clip],trackViewMeta:TimelineViewMeta,metalView: MTKView,viewportSize:CGSize,commandEncoder: any MTLRenderCommandEncoder) throws
	{
		let geometryPipelineState = self.state

		commandEncoder.setRenderPipelineState( geometryPipelineState )
		
		//	viewport in pixel space
		//actor.enableDepthReadWrite(commandEncoder)
		
		var clips = clips
		commandEncoder.setVertexBytes(&clips, length: MemoryLayout<Clip>.stride * clips.count, index:self.vertexBuffer_clips )
		
		var trackViewMeta = trackViewMeta
		commandEncoder.setVertexBytes(&trackViewMeta, index:self.vertexBuffer_timelineViewMeta )
		
		var screenSize = [Float(viewportSize.width),Float(viewportSize.height)]
		commandEncoder.setVertexBytes(&screenSize, length: MemoryLayout<Float>.stride*2, index:self.vertexBuffer_screenSize )
		
		let instanceCount = clips.count
		if instanceCount > 0
		{
			commandEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: instanceCount )
		}
	}
	
}


class TrackContentRenderer : ContentRenderer, ObservableObject
{
	@Published var viewMeta = TimelineViewMeta()
	var clipCache = [Clip]()
	
	var clipBoxContentRenderDescriptor : ClipBoxContentRenderDescriptor?
	
	init()
	{
	}
	
	func SetupView(metalView: MTKView) 
	{
		metalView.clearColor = MTLClearColor(red: 0,green: 0,blue: 0,alpha: 0.0)
		clipBoxContentRenderDescriptor = try? ClipBoxContentRenderDescriptor(metalView: metalView)
	}
	
	func Draw(metalView: MTKView, size: CGSize, commandEncoder: any MTLRenderCommandEncoder) throws 
	{
		clipBoxContentRenderDescriptor = try clipBoxContentRenderDescriptor ?? ClipBoxContentRenderDescriptor(metalView: metalView)
		try clipBoxContentRenderDescriptor!.Render(clips: self.clipCache, trackViewMeta: self.viewMeta, metalView: metalView, viewportSize: size, commandEncoder: commandEncoder)
	}
}

//	read-only
public struct ClipTimelineView : View 
{
	@StateObject var trackRenderer = TrackContentRenderer()
	var clips : [Clip]

	//	make binding for user?
	@State var hoverCoord = TimelineCoord(0,0)

	@State private var rightDragStart : (TimelineViewMeta,CGPoint)? = nil

	public init(clips: [Clip])
	{
		self.clips = clips
		//	this modifies state object too early.
		//	covered by OnAppear
		//self.OnDataChanged()	
	}
	
	public var body: some View 
	{
		MetalView(contentRenderer: trackRenderer,showFps: false)
			.mouseTracking(OnMouseStateChanged, onScroll: OnMouseScroll)
			.onChange(of: clips)
		{
			OnDataChanged()
		}
		.onAppear
		{
			OnDataChanged()
		}
		.overlay
		{
			VStack(alignment: .leading)
			{
				Text("Hover (\(hoverCoord.x),\(hoverCoord.y))")
				Text("zoom \(trackRenderer.viewMeta.columnWidthPx)")
				Text("left \(trackRenderer.viewMeta.leftColumn)")
				Spacer()
			}
		}
	}
	
	func OnDataChanged()
	{
		print("Clip data changed")
		trackRenderer.clipCache = clips
	}
	
	
	func OnMouseStateChanged(_ mouseState:MouseState)
	{
		//	drag view around
		if mouseState.rightDown
		{
			let view = self.trackRenderer.viewMeta
			rightDragStart = rightDragStart ?? (self.trackRenderer.viewMeta,mouseState.position)
			let startcoord = view.PixelToCoord(rightDragStart!.1.x,0)
			let nowcoord = view.PixelToCoord(mouseState.position.x,0)
			let changex = startcoord.x - nowcoord.x
			//let changex = (rightDragStart!.1.x - mouseState.position.x) / CGFloat(self.trackRenderer.viewMeta.columnWidthPx) 
			self.trackRenderer.viewMeta.leftColumn = rightDragStart!.0.leftColumn + changex
		}
		else
		{
			rightDragStart = nil
		}
		
		self.hoverCoord = self.trackRenderer.viewMeta.PixelToCoord(mouseState.position.x, mouseState.position.y)
	}
	
	func OnMouseScroll(_ scroll:MouseScrollEvent)
	{
		let zoom = Float(scroll.scrollDelta) * 0.1
		var columnWidthPx = trackRenderer.viewMeta.columnWidthPx + zoom
		columnWidthPx = clamp( columnWidthPx, min:TimelineViewMeta.minColumnWidthPx, max:TimelineViewMeta.maxColumnWidthPx )
		trackRenderer.viewMeta.columnWidthPx = columnWidthPx
	}
}

func MakeFakeClips() -> [Clip]
{
	return Array(0..<100).map
	{
		t in
		Clip(column: t, width: (t+60)*3, row: t, type: t)
	}
}

#Preview 
{
	@Previewable @State var clips = MakeFakeClips()
	
	ClipTimelineView(clips: clips)
}
