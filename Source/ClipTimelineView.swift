import SwiftUI
import PopMetalView
import MetalKit
import MouseTracking
import PopCommon


public typealias ClipId = UInt32

extension ClipId
{
	init()
	{
		self = UInt32( abs(UUID().hashValue) % 100000 )
	}
}

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
	var column : Int32
	var colour : simd_float4
	
	public init(column: Int32,colour:Color) 
	{
		self.column = column
		self.colour = colour.rgba ?? simd_float4.one
	}
}

//	match shader
public struct Notch : Equatable
{
	var frame : Int32
	
	public init(frame: Int32) 
	{
		self.frame = frame
	}
}

public extension Collection
{
	//	x = array[safeIndex:999] ?? 123
	subscript(safeIndex i: Index) -> Element? 
	{
		get 
		{
			if i >= self.endIndex
			{
				return nil
			}
			//guard self.indices.contains(i) else { return nil }
			return self[i]
		}
	}
}

public extension Color
{
	var rgba : simd_float4?
	{
		let uic = UIColor(self)
		guard let components = uic.cgColor.components, components.count > 0 else 
		{
			return nil
		}

		//	handle sub-3 component colours (monochrome)
		let r = components[0]
		let g = components[safeIndex: 1] ?? r
		let b = components[safeIndex: 2] ?? r
		let a = components[safeIndex: 3] ?? 1
		return simd_float4(Float(r),Float(g),Float(b),Float(a))
	}
}

//	match shader
public struct NotchMeta : Equatable
{
	var colour : simd_float4
	var notchRow : UInt32
	var minWidthPx : UInt32
	
	public init(notchRow: UInt32,colour:Color,minWidthPx:UInt32=1) 
	{
		self.notchRow = notchRow
		self.colour = colour.rgba ?? simd_float4.one
		self.minWidthPx = minWidthPx
	}
}

public struct NotchBatch
{
	var meta : NotchMeta
	var notches : [Notch]
	
	public init(meta: NotchMeta, notches: [Notch]) 
	{
		self.meta = meta
		self.notches = notches
	}
}


//	match shader
public struct Clip : Equatable, Identifiable
{
	var column : UInt32
	var width : UInt32
	var lastColumn : UInt32	{	column + (max(1,width)-1)	}
	var row : UInt32
	var colour : simd_float4
	//var type : UInt32	//	selected etc
	public var id : ClipId
	
	public init(id:ClipId,column: UInt32, width: UInt32, row: UInt32, colour: Color) 
	{
		self.id = id
		self.column = column
		self.width = width
		self.row = row
		self.colour = colour.rgba ?? simd_float4.one
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
	
	//	this is a cache, but we need it to flip coords
	public var lastViewSize : CGSize = .zero
	
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
		//	flip coords
		var y = y
		y = lastViewSize.height - y
		
		//	apply zoom
		var xf = x / CGFloat(columnWidthPx)
		let yf = y / CGFloat(rowHeightPx+rowGapPx)
		
		//	apply scroll
		xf += CGFloat(leftColumn)
		
		return TimelineCoord( Int32(xf), Int32(yf) )
	}
}




struct ClipNotchRenderDescriptor : RenderCommand
{
	var descriptorAndState : MTLRenderDescriptorAndState!
	
	//	config per-shader implementation
	static var vertexShaderName = "NotchVertex"
	var vertexBuffer_notchs = 0
	var vertexBuffer_notchMeta = 1
	var vertexBuffer_clip = 2
	var vertexBuffer_timelineViewMeta = 3
	var vertexBuffer_screenSize = 4
	static var fragShaderName = "ClipNotchFrag"
	var fragBuffer_notchMeta = 0
	
	init(metalView: MTKView, shaderInBundle: Bundle) throws 
	{
		try self.initDescriptor(metalView: metalView, shaderInBundle:shaderInBundle)
	}
	
	
	func Render(notchBatch:NotchBatch,clip:Clip,trackViewMeta:TimelineViewMeta,metalView: MTKView,viewportSize:CGSize,commandEncoder: any MTLRenderCommandEncoder) throws
	{
		var notches = notchBatch.notches
		if notches.isEmpty
		{
			return
		}
		let geometryPipelineState = self.state
		
		commandEncoder.setRenderPipelineState( geometryPipelineState )
		
		//	viewport in pixel space
		//actor.enableDepthReadWrite(commandEncoder)
		
		var clip = clip
		var notchMeta = notchBatch.meta
		commandEncoder.setVertexBytes( &notches, length: MemoryLayout<Notch>.stride * notches.count, index:self.vertexBuffer_notchs )
		commandEncoder.setVertexBytes( &notchMeta, index:self.vertexBuffer_notchMeta )
		commandEncoder.setFragmentBytes( &notchMeta, index:self.fragBuffer_notchMeta )
		commandEncoder.setVertexBytes( &clip, index:self.vertexBuffer_clip )
		
		var trackViewMeta = trackViewMeta
		commandEncoder.setVertexBytes(&trackViewMeta, index:self.vertexBuffer_timelineViewMeta )
		
		var screenSize = [Float(viewportSize.width),Float(viewportSize.height)]
		commandEncoder.setVertexBytes(&screenSize, length: MemoryLayout<Float>.stride*2, index:self.vertexBuffer_screenSize )
		
		commandEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: notches.count )
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
	static var fragShaderName = "ClipBoxFrag"
	
	init(metalView: MTKView, shaderInBundle: Bundle) throws 
	{
		print("ClipBoxContentRenderDescriptor init")
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
	@Published var lastRenderSize : CGSize = .zero
	
	//	view meta is cache
	var viewMeta = TimelineViewMeta()
	var clipCache = [Clip]()
	var markerCache = [Marker]()
	
	var clipBoxContentRenderDescriptor : ClipBoxContentRenderDescriptor?
	var clipNotchRenderDescriptor : ClipNotchRenderDescriptor?
	var markerRenderDescriptor : MarkerRenderDescriptor?
	var getClipNotches : (ClipId) -> [NotchBatch]
	
	init(getClipNotches:@escaping(ClipId) -> [NotchBatch])
	{
		print("new TrackContentRenderer()")
		self.getClipNotches = getClipNotches
	}
	
	func SetupView(metalView: MTKView) 
	{
		metalView.depthStencilPixelFormat = .depth32Float
		metalView.clearColor = MTLClearColor(red: 0,green: 0,blue: 0,alpha: 0.0)
		DispatchQueue.main.async
		{
			self.lastRenderSize = metalView.drawableSize
		}
	}
	
	func Draw(metalView: MTKView, size: CGSize, commandEncoder: any MTLRenderCommandEncoder) throws 
	{
		lastRenderSize = size

		clipBoxContentRenderDescriptor = try clipBoxContentRenderDescriptor ?? ClipBoxContentRenderDescriptor(metalView: metalView, shaderInBundle: .module)
		try clipBoxContentRenderDescriptor!.Render(clips: self.clipCache, trackViewMeta: self.viewMeta, metalView: metalView, viewportSize: size, commandEncoder: commandEncoder)

		//	render notches on top
		//	todo: one giant batch?
		clipNotchRenderDescriptor = try clipNotchRenderDescriptor ?? ClipNotchRenderDescriptor(metalView: metalView, shaderInBundle: .module)
		for clip in clipCache
		{
			let notchBatches = getClipNotches(clip.id)
			for notchBatch in notchBatches 
			{
				try clipNotchRenderDescriptor!.Render(notchBatch:notchBatch,clip: clip, trackViewMeta: self.viewMeta, metalView: metalView, viewportSize: size, commandEncoder: commandEncoder)
			}
		}
		
			
		markerRenderDescriptor = try markerRenderDescriptor ?? MarkerRenderDescriptor(metalView: metalView, shaderInBundle: .module)
		try markerRenderDescriptor!.Render(markers: self.markerCache, trackViewMeta: self.viewMeta, metalView: metalView, viewportSize: size, commandEncoder: commandEncoder)
	}
}

//	read-only
public struct ClipTimelineView : View 
{
	//	viewmeta is external, so that parent views can do Pixel<>Coord conversions - or show view zoom/range
	@Binding var viewMeta : TimelineViewMeta
	@StateObject var trackRenderer : TrackContentRenderer
	@Binding var selectedClip : ClipId?
	@Binding var hoveredClip : ClipId?
	var clips : [Clip]
	var markers : [Marker]
	var renderHeight : CGFloat	{	CGFloat(GetLargestClipRow()) * CGFloat((viewMeta.rowHeightPx+viewMeta.rowGapPx))	}

	//	make binding for user?
	@State var hoverCoord = TimelineCoord(0,0)

	@State private var rightDragStart : (TimelineViewMeta,CGPoint)? = nil
	@State private var leftDragStart : (TimelineViewMeta,CGPoint)? = nil

	var onClickedEmptySpace : (TimelineCoord)->Void
	var getClipNotches : (ClipId)->[NotchBatch]
	
	public init(clips:[Clip],markers:[Marker],viewMeta:Binding<TimelineViewMeta>,selectedClip:Binding<ClipId?>,hoveredClip:Binding<ClipId?>,onClickedEmptySpace:@escaping(TimelineCoord)->Void,getClipNotches:@escaping ((ClipId)->[NotchBatch]))
	{
		self.clips = clips
		self.markers = markers
		self._viewMeta = viewMeta
		self._selectedClip = selectedClip
		self._hoveredClip = hoveredClip
		self.onClickedEmptySpace = onClickedEmptySpace
		//	this modifies state object too early.
		//	covered by OnAppear
		//self.OnDataChanged()	
		self.getClipNotches = getClipNotches
		//print("Setting get notches from \(self._trackRenderer.wrappedValue.getNotches) to \(self.getClipNotches)")
		self._trackRenderer = StateObject(wrappedValue: TrackContentRenderer(getClipNotches:getClipNotches) )
		//print("get notches is now \(self._trackRenderer.wrappedValue.getNotches)")
	}
	
	
	public var body: some View 
	{
		MetalView(contentRenderer: trackRenderer,showFps: false)
			.mouseTracking(OnMouseStateChanged, onScroll: OnMouseScroll)
			.onChange(of: clips, OnClipsChanged)
			.onChange(of: markers, OnMarkersChanged)
			.onChange(of: selectedClip, OnSelectedClipChanged)
			.onChange(of: viewMeta, OnViewMetaChanged)
			.onAppear
			{
				OnMarkersChanged()
				OnClipsChanged()
				OnSelectedClipChanged()
				OnViewMetaChanged()
			}
			.overlay
			{
				/*
				VStack(alignment: .leading)
				{
					Text("clips x\(clips.count)")
					Text("Hover (\(hoverCoord.x),\(hoverCoord.y))")
					Text("zoom \(trackRenderer.viewMeta.columnWidthPx)")
					Text("left \(trackRenderer.viewMeta.leftColumn)")
					Spacer()
				}
				.foregroundStyle(.white)
				.background(.blue.opacity(0.5))
				.allowsHitTesting(false)
				 */
			}
			.frame(minHeight: renderHeight)
			.onChange(of: trackRenderer.lastRenderSize)
		{
			newSize in
			self.viewMeta.lastViewSize = newSize
		}
	}
		
	func OnMarkersChanged()
	{
		//print("Markers data changed")
		trackRenderer.markerCache = self.markers
	}
	
	func OnSelectedClipChanged()
	{
	}
	
	func OnClipsChanged()
	{
		print("Clip data changed x\(self.clips.count)")
		trackRenderer.clipCache = self.clips
	}
	
	func OnViewMetaChanged()
	{
		//print("ViewMeta changed")
		trackRenderer.viewMeta = self.viewMeta
	}
	
	
	func OnMouseStateChanged(_ mouseState:MouseState)
	{
		//	drag view around
		if mouseState.rightDown
		{
			rightDragStart = rightDragStart ?? (viewMeta,mouseState.position)
			let startcoord = viewMeta.PixelToCoord(rightDragStart!.1.x,0)
			let nowcoord = viewMeta.PixelToCoord(mouseState.position.x,0)
			let changex = startcoord.x - nowcoord.x
			//let changex = (rightDragStart!.1.x - mouseState.position.x) / CGFloat(self.trackRenderer.viewMeta.columnWidthPx) 
			//self.trackRenderer.viewMeta.leftColumn = rightDragStart!.0.leftColumn + changex
			viewMeta.leftColumn = rightDragStart!.0.leftColumn + changex
		}
		else
		{
			rightDragStart = nil
		}
		
		if leftDragStart == nil && mouseState.leftDown
		{
			//	first click
			let clickCoord = viewMeta.PixelToCoord(mouseState.position)
			//print("Click \(clickCoord)")
			let clickedClip = self.GetClipAt(clickCoord)
			if let clickedClip
			{
				self.selectedClip = clickedClip.id
			}
			else
			{
				self.selectedClip = nil
				self.onClickedEmptySpace(clickCoord)
			}
			leftDragStart = (viewMeta,mouseState.position)
		}
		else if mouseState.leftDown
		{
			//	dragging
			let clickCoord = viewMeta.PixelToCoord(mouseState.position)
			self.onClickedEmptySpace(clickCoord)
		}
		else if leftDragStart != nil
		{
			//	dropped
			leftDragStart = nil
		}
		
		self.hoverCoord = self.viewMeta.PixelToCoord(mouseState.position.x, mouseState.position.y)
		self.hoveredClip = self.GetClipAt(self.hoverCoord)?.id
	}
	
	func OnMouseScroll(_ scroll:MouseScrollEvent)
	{
		let zoom = Float(scroll.scrollDelta) * 0.1
		var columnWidthPx = viewMeta.columnWidthPx + zoom
		columnWidthPx = clamp( columnWidthPx, min:TimelineViewMeta.minColumnWidthPx, max:TimelineViewMeta.maxColumnWidthPx )
		viewMeta.columnWidthPx = columnWidthPx
	}
	
	func GetClipAt(_ timelineCoord:TimelineCoord) -> Clip?
	{
		//	gr: bug here where the self.clips are out of date
		//		Im presuming this is because an OLD mousehandler on the view
		//		is not being freed and pointing at an old view
		let RendererCachedClips = self.trackRenderer.clipCache
		let clips = RendererCachedClips
		return clips.first(where:
		{
			$0.row == timelineCoord.y &&
			timelineCoord.x >= $0.column  && timelineCoord.x <= $0.lastColumn 
		})
	}
	
	func GetLargestClipRow() -> UInt32
	{
		var rowMax : UInt32 = 0
		for clip in clips
		{
			rowMax = Swift.max( rowMax, clip.row )
		}
		return rowMax
	}
}

func MakeFakeClips() -> [Clip]
{
	let colours : [Color] = 
	[
		.purple,.red,.orange,.yellow,.green,.cyan,.blue
	]
	
	var clips = Array(0..<6).map
	{
		t in
		Clip(id:ClipId(), column: t*10, width: 20, row: t % 5, colour: colours[Int(t)%colours.count])
	}
	let longClip = Clip(id: 12345, column: 3, width: 20000, row:6, colour: .indigo)
	clips.append(longClip)
	return clips
}

func MakeFakeMarkers() -> [Marker]
{
	return Array(0..<5).map
	{
		t in
		Marker(column: 4 + Int32(t) * 10, colour: .white)
	}
}



class RandomClipNotchProducer
{
	var notchFrames : [Notch] = []
	let frameMin = 0
	let frameMax = 20000
	var writeThread : Task<Void,Never>?
	var notchMeta : NotchMeta
	var notches : NotchBatch	{	NotchBatch(meta: notchMeta, notches: notchFrames )	}

	init(meta:NotchMeta,step:Int)
	{
		self.notchMeta = meta
		self.writeThread = Task
		{
			await self.NotchWritingThread(step:step)
		}
	}
	
	deinit
	{
		writeThread?.cancel()
	}
	
	func NotchWritingThread(step:Int) async
	{
		for i in 0..<2000
		{
			notchFrames.append( Notch(frame: Int32(i*step)) )
			await Task.sleep(milliseconds: 100)
		}
	}
}


#Preview 
{
	@Previewable @State var clips = MakeFakeClips()
	@Previewable @State var viewMeta = TimelineViewMeta(columnWidthPx: 0.7)
	@Previewable @State var selectedClip : ClipId? 
	@Previewable @State var hoveredClip : ClipId? 
	@Previewable @State var timeMarker = Marker(column: 10, colour: .cyan)
	//@Previewable @State var markers = MakeFakeMarkers()
	var markers : [Marker] { [timeMarker]	}
	var clipNotchProducer1 = RandomClipNotchProducer(meta:NotchMeta(notchRow: 0, colour: .red, minWidthPx: 5),step:15)
	var clipNotchProducer2 = RandomClipNotchProducer(meta:NotchMeta(notchRow: 3, colour: .blue, minWidthPx: 10),step:50)
	
	ClipTimelineView(clips: clips,markers:markers,viewMeta: $viewMeta,selectedClip: $selectedClip,hoveredClip: $hoveredClip)
	{
		clickCoord in
		timeMarker.column = clickCoord.x 
	}
	getClipNotches:
	{
		clipId in
		//print("Get notches for \(clipId)")
		return clipId == 12345 ? [clipNotchProducer1.notches,clipNotchProducer2.notches] : []
	}
		.overlay
	{
		VStack
		{
			let selectedName = selectedClip.map{ "\($0)" } ?? "none"
			let hoveredName = hoveredClip.map{ "\($0)" } ?? "none"
			Text("Selected clip: \(selectedName)")
				.foregroundStyle(.white)
				.padding(5)
				.background(.black)
			Text("hovered clip: \(hoveredName)")
				.foregroundStyle(.white)
				.padding(5)
				.background(.black)
		}
		.allowsHitTesting(false)
		.frame(maxWidth: .infinity,maxHeight: .infinity,alignment: .topLeading)
	}
	.frame(width:400,height: 500)
}
