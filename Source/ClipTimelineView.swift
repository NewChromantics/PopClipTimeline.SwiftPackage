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
public struct Marker : Equatable
{
	var column : UInt32
	var type : UInt32
	
	public init(column: UInt32,type: UInt32) 
	{
		self.column = column
		self.type = type
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
	public var x : Int32 = 0
	public var y : Int32 = 0
	
	public init(_ x:Int32,_ y:Int32)
	{
		self.x = x
		self.y = y
	}
}

public struct TimelineViewMeta : Equatable
{
	public var leftColumn : Int32 = 0
	public var rowHeightPx : UInt32 = 40
	public var rowGapPx : UInt32 = 1
	public var columnWidthPx : Float
	public static var minColumnWidthPx : Float {	0.1	}
	public static var maxColumnWidthPx : Float {	10	}
	
	public init(columnWidthPx:Float=5)
	{
		self.columnWidthPx = columnWidthPx
	}
	
	//	todo: make functions here that match shader pixel<>data conversion for accurate UI conversion

	public func PixelToCoord(_ pos:CGPoint) -> TimelineCoord
	{
		return PixelToCoord( pos.x, pos.y )
	}
	
	//	todo: y is wrong as pixel is upside down - need view height
	public func PixelToCoord(_ x:CGFloat,_ y:CGFloat) -> TimelineCoord
	{
		//	apply zoom
		var xf = x / CGFloat(columnWidthPx)
		let yf = y / CGFloat(rowHeightPx+rowGapPx)
		
		//	apply scroll
		xf += CGFloat(leftColumn)
		
		
		return TimelineCoord( Int32(xf), Int32(yf) )
	}
}



struct ClipBoxContentRenderDescriptor : RenderCommand
{
	var descriptorAndState : MTLRenderDescriptorAndState!
	
	//	config per-shader implementation
	static var vertexShaderName = "ClipBoxVertex"
	var vertexBuffer_clips = 0
	var vertexBuffer_timelineViewMeta = 1
	var vertexBuffer_screenSize = 2
	static var fragShaderName = "ColourFrag"
	
	init(metalView: MTKView, shaderInBundle: Bundle) throws 
	{
		try self.initDescriptor(metalView: metalView, shaderInBundle:shaderInBundle)
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


struct MarkerRenderDescriptor : RenderCommand
{
	var descriptorAndState : MTLRenderDescriptorAndState!
	
	//	config per-shader implementation
	static var vertexShaderName = "MarkerVertex"
	var vertexBuffer_markers = 0
	var vertexBuffer_timelineViewMeta = 1
	var vertexBuffer_screenSize = 2
	static var fragShaderName = "MarkerFrag"
	
	init(metalView: MTKView, shaderInBundle: Bundle) throws 
	{
		try self.initDescriptor(metalView: metalView, shaderInBundle:shaderInBundle)
	}
	
	
	func Render(markers:[Marker],trackViewMeta:TimelineViewMeta,metalView: MTKView,viewportSize:CGSize,commandEncoder: any MTLRenderCommandEncoder) throws
	{
		let geometryPipelineState = self.state
		
		commandEncoder.setRenderPipelineState( geometryPipelineState )
		
		//	viewport in pixel space
		//actor.enableDepthReadWrite(commandEncoder)
		
		var markers = markers
		commandEncoder.setVertexBytes(&markers, length: MemoryLayout<Marker>.stride * markers.count, index:self.vertexBuffer_markers )
		
		var trackViewMeta = trackViewMeta
		commandEncoder.setVertexBytes(&trackViewMeta, index:self.vertexBuffer_timelineViewMeta )
		
		var screenSize = [Float(viewportSize.width),Float(viewportSize.height)]
		commandEncoder.setVertexBytes(&screenSize, length: MemoryLayout<Float>.stride*2, index:self.vertexBuffer_screenSize )
		
		let instanceCount = markers.count
		if instanceCount > 0
		{
			commandEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: instanceCount )
		}
	}
	
}



class TrackContentRenderer : ContentRenderer, ObservableObject
{
	//	view meta is cache
	var viewMeta = TimelineViewMeta()
	var clipCache = [Clip]()
	var markerCache = [Marker]()
	
	var clipBoxContentRenderDescriptor : ClipBoxContentRenderDescriptor?
	var markerRenderDescriptor : MarkerRenderDescriptor?
	
	init()
	{
	}
	
	func SetupView(metalView: MTKView) 
	{
		metalView.depthStencilPixelFormat = .depth32Float
		metalView.clearColor = MTLClearColor(red: 0,green: 0,blue: 0,alpha: 0.0)
	}
	
	func Draw(metalView: MTKView, size: CGSize, commandEncoder: any MTLRenderCommandEncoder) throws 
	{
		clipBoxContentRenderDescriptor = try clipBoxContentRenderDescriptor ?? ClipBoxContentRenderDescriptor(metalView: metalView, shaderInBundle: .module)
		try clipBoxContentRenderDescriptor!.Render(clips: self.clipCache, trackViewMeta: self.viewMeta, metalView: metalView, viewportSize: size, commandEncoder: commandEncoder)

		markerRenderDescriptor = try markerRenderDescriptor ?? MarkerRenderDescriptor(metalView: metalView, shaderInBundle: .module)
		try markerRenderDescriptor!.Render(markers: self.markerCache, trackViewMeta: self.viewMeta, metalView: metalView, viewportSize: size, commandEncoder: commandEncoder)
	}
}

//	read-only
public struct ClipTimelineView : View 
{
	//	viewmeta is external, so that parent views can do Pixel<>Coord conversions - or show view zoom/range
	@Binding var viewMeta : TimelineViewMeta
	@StateObject var trackRenderer = TrackContentRenderer()
	var clips : [Clip]
	var markers : [Marker]

	//	make binding for user?
	@State var hoverCoord = TimelineCoord(0,0)

	@State private var rightDragStart : (TimelineViewMeta,CGPoint)? = nil

	public init(clips:[Clip],markers:[Marker],viewMeta:Binding<TimelineViewMeta>)
	{
		self.clips = clips
		self.markers = markers
		self._viewMeta = viewMeta
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
			OnClipsChanged()
		}
		.onChange(of: markers)
		{
			OnMarkersChanged()
		}
		.onChange(of: viewMeta)
		{
			OnViewMetaChanged()
		}
		.onAppear
		{
			OnMarkersChanged()
			OnClipsChanged()
			OnViewMetaChanged()
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
			.allowsHitTesting(false)
		}
	}
	
	func OnMarkersChanged()
	{
		print("Markers data changed")
		trackRenderer.markerCache = self.markers
	}
	
	func OnClipsChanged()
	{
		print("Clip data changed")
		trackRenderer.clipCache = self.clips
	}
	
	func OnViewMetaChanged()
	{
		print("ViewMeta changed")
		trackRenderer.viewMeta = self.viewMeta
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
		Clip(column: t*2, width: (t+1)*1, row: t % 10, type: t)
	}
}

func MakeFakeMarkers() -> [Marker]
{
	return Array(0..<100).map
	{
		t in
		Marker(column: t * 3, type: t)
	}
}


#Preview 
{
	@Previewable @State var clips = MakeFakeClips()
	@Previewable @State var markers = MakeFakeMarkers()
	@Previewable @State var viewMeta = TimelineViewMeta()
	
	ClipTimelineView(clips: clips,markers:markers,viewMeta: $viewMeta)
}
