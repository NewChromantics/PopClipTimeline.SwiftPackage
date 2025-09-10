#include <metal_stdlib>
using namespace metal;


bool4 IsPixelEdge(float2 ScreenPosition,float4 ScreenRect)
{
	//	we're expecting these as int's anyway
	int2 ScreenPx = int2(ScreenPosition);
	int2 TopLeftPx = int2(ScreenRect.xy);
	int2 BottomRightPx = int2(ScreenRect.xy+ScreenRect.zw) - int2(1,1);
	
	bool LeftEdge = ScreenPx.x == TopLeftPx.x; 
	bool RightEdge = ScreenPx.x == BottomRightPx.x;
	bool TopEdge = ScreenPx.y == TopLeftPx.y;
	bool BottomEdge = ScreenPx.y == BottomRightPx.y;
	
	return bool4(LeftEdge, TopEdge, RightEdge, BottomEdge);
}

typedef uint32_t ClipId;

struct Clip
{
	uint32_t column;
	uint32_t width;
	uint32_t row;
	float4 colour;
	ClipId id;
};

struct NotchMeta
{
	float4		colour;
	uint32_t	notchRow;
	uint32_t 	minWidthPx;
};

struct Notch
{
	//	todo: reduce to bits
	//		move type to batch info
	uint32_t frame;	//	inside clip so 0 = clip.column + 0
};


struct Marker
{
	uint32_t 	column;
	float4		colour;
};

struct TimelineViewMeta
{
	//	state
	int32_t leftColumn;
	
	//	design
	uint32_t rowHeightPx;
	uint32_t rowGapPx;
	float columnWidthPx;	//	zoom
};


struct QuadVertex 
{
	float x;
	float y;
};

struct ContentVertexOutput 
{
	float4 clipPosition [[position]];	//	clip space
	float2 screenPosition;				//	in screen space
	float2 boxPx;						//	pixel local to box
	float2 boxSizePx;					//	width/height of box in pixels (so we can do outline)
	float coordX;						//	y is always row so always 0
	float2 uv;							//	uv local to box
	Clip clip;							//	just send everything for now
};


float3 GetDebugColour(int Value)
{
	float hi = 0.9;
	float lo = 0.3;
	
	const int DebugColourCount = 6;
	float3 DebugColours[DebugColourCount] =
	{
		float3(hi,lo,lo),
		float3(hi,hi,lo),
		float3(lo,hi,lo),
		float3(lo,hi,hi),
		float3(lo,lo,hi),
		float3(hi,lo,hi),
	};
	return DebugColours[Value%DebugColourCount];
}



float4 GetClipColour(Clip content)
{
	//	todo: add selection tints here?
	return content.colour;
}


float4 GetMarkerColour(Clip content)
{
	return content.colour;
}

constant QuadVertex quadVertexes[] = 
{
	//	back
	QuadVertex{	0, 0	},
	QuadVertex{	0, 1	},
	QuadVertex{	1, 0	},
	QuadVertex{	1, 1	},
	
};

struct FragColourAndDepthOut 
{
	float4 colour[[color(0)]];
	float depth[[depth(any)]];
};


fragment float4 ClipNotchFrag(ContentVertexOutput in [[stage_in]],
							  constant NotchMeta& NotchMeta[[buffer(0)]]
							  )
{
	//	dodge edge
	auto Edges = IsPixelEdge( in.boxPx, float4(0,0,in.boxSizePx) );
	if ( Edges[1] || Edges[3] )
	{
		discard_fragment();
		return float4(1,0,1,1);
	}
	
	auto Colour = NotchMeta.colour;
	float NotchRowCount = 4;
	
	//	fill in box
	auto top_v = (NotchMeta.notchRow / NotchRowCount);
	auto bottom_v = top_v + (1.0 / NotchRowCount);
	
	if ( in.uv.y < top_v || in.uv.y > bottom_v )
	{
		discard_fragment();
	}
	return Colour;
}


fragment FragColourAndDepthOut ClipBoxFrag(ContentVertexOutput in [[stage_in]])
{
	float EdgeDepth = 1;
	float BoxDepth = 0;
	
	FragColourAndDepthOut EdgeColour = { .colour=float4(0,0,0,1), .depth=EdgeDepth };
	
	//	can we do pixel perfect edges?
	int DropShadowPx = 1;
	bool LeftEdge = int(in.boxPx.x) == 0;
	bool TopEdge = int(in.boxPx.y) == 0;
	bool RightEdge = int(in.boxPx.x) >= int(in.boxSizePx.x)-(1+DropShadowPx);
	bool BottomEdge = int(in.boxPx.y) >= int(in.boxSizePx.y)-(1+DropShadowPx);
	
	//	cut edge of drop shadow
	if ( TopEdge && RightEdge )	discard_fragment();
	if ( BottomEdge && LeftEdge )	discard_fragment();
	
	if ( LeftEdge || TopEdge || RightEdge || BottomEdge )
		return EdgeColour;
	
	//	use of int causes aliasing - should really use float and mix colours
	bool Odd = (int(in.coordX) % 2) == 1;
	auto Colour = GetClipColour(in.clip);
	if ( Odd )
		Colour = mix( Colour, 0.5, 0.2 );
	return { .colour = Colour, .depth=BoxDepth };
}



fragment float4 MarkerFrag(ContentVertexOutput in [[stage_in]])
{
	auto Colour = GetMarkerColour(in.clip);
	return Colour;
}


float range(float Min,float Max,float Value)
{
	return (Value-Min) / (Max-Min);
}

float2 range(float2 Min,float2 Max,float2 Value)
{
	return float2( range(Min.x,Max.x,Value.x), range(Min.y,Max.y,Value.y) );
}


float2 CoordToScreenPx(float2 Coord,TimelineViewMeta trackViewMeta)
{
	Coord.x -= trackViewMeta.leftColumn;
	float2 px = Coord * float2( trackViewMeta.columnWidthPx, trackViewMeta.rowHeightPx + trackViewMeta.rowGapPx );
	return px;
}

float4 ScreenPxToClip(float2 px,float2 ScreenSize)
{
	float2 uv = range( float2(0), ScreenSize, px );
	//	flip
	uv.y = 1 - uv.y;
	//	0..1 -> -1...1
	uv = (uv - 0.5) * 2;
	
	return float4( uv, 0, 1 );
}


ContentVertexOutput ClipBoxVertexImpl( uint vertexId,
										Clip clip,
									  int MinPixelWidth,
									  int RowsCovered,
										 constant TimelineViewMeta& timelineViewMeta,
										 constant float2& ScreenSize
										 ) 
{
	ContentVertexOutput out;
	QuadVertex vert = quadVertexes[vertexId];
	
	//	make pixel box
	float left = clip.column;
	float right = left + max(uint32_t(1),clip.width);	//	clips with 0 duration need to be visible for at least one unit
	
	//	get coords
	//float coordX = mix( left, right, vert.x );
	float coordY = clip.row;

	auto LeftScreenPosition = CoordToScreenPx( float2(left,coordY), timelineViewMeta );
	auto RightScreenPosition = CoordToScreenPx( float2(right,coordY), timelineViewMeta );
	float coordX = mix( left, right, vert.x );
	
	if ( RightScreenPosition.x - LeftScreenPosition.x < MinPixelWidth )
	{
		RightScreenPosition.x = LeftScreenPosition.x + MinPixelWidth;
	}
	
	out.screenPosition = mix( LeftScreenPosition, RightScreenPosition, vert.x );
	out.screenPosition.y += vert.y * RowsCovered * timelineViewMeta.rowHeightPx;
	
	out.clipPosition = ScreenPxToClip( out.screenPosition, ScreenSize );
	out.uv = float2(vert.x,vert.y);
	out.boxSizePx = float2( clip.width * timelineViewMeta.columnWidthPx, timelineViewMeta.rowHeightPx );
	out.boxPx = out.uv * out.boxSizePx;
	out.coordX = coordX;
	out.clip = clip;

	return out;
}

vertex ContentVertexOutput ClipBoxVertex( uint vertexId [[vertex_id]],
												uint instanceId [[instance_id]],
												constant Clip* clips[[buffer(0)]],
												constant TimelineViewMeta& timelineViewMeta[[buffer(1)]],
												constant float2& ScreenSize[[buffer(2)]]
) 
{
	auto clip = clips[instanceId];
	int RowsCovered = 1;
	int MinPixelWidth = 0;
	
	return ClipBoxVertexImpl( vertexId, clip, MinPixelWidth, RowsCovered, timelineViewMeta, ScreenSize );
}


vertex ContentVertexOutput NotchVertex( uint vertexId [[vertex_id]],
										 uint instanceId [[instance_id]],
									   constant Notch* notchs[[buffer(0)]],
									   constant NotchMeta& NotchMeta[[buffer(1)]],
									   constant Clip& clip[[buffer(2)]],
										 constant TimelineViewMeta& timelineViewMeta[[buffer(3)]],
										 constant float2& ScreenSize[[buffer(4)]]
										 ) 
{
	auto Notch = notchs[instanceId];
	int RowsCovered = 1;
	
	Clip NotchClip;
	NotchClip.column = clip.column + Notch.frame;
	NotchClip.width = 1;
	NotchClip.row = clip.row;
	NotchClip.colour = NotchMeta.colour;

	int MinPixelWidth = NotchMeta.minWidthPx;
	
	return ClipBoxVertexImpl( vertexId, NotchClip, MinPixelWidth, RowsCovered, timelineViewMeta, ScreenSize );
}

vertex ContentVertexOutput MarkerVertex( uint vertexId [[vertex_id]],
										 uint instanceId [[instance_id]],
										 constant Marker* markers[[buffer(0)]],
										 constant TimelineViewMeta& timelineViewMeta[[buffer(1)]],
										 constant float2& ScreenSize[[buffer(2)]]
										 ) 
{
	auto marker = markers[instanceId];
	//auto clip = clips[instanceId];
	Clip clip;
	clip.column = marker.column;
	clip.width = 1;
	clip.row = 0;
	clip.colour = marker.colour;
	int RowsCovered = 100;
	int MinPixelWidth = 1;
	
	return ClipBoxVertexImpl( vertexId, clip, MinPixelWidth, RowsCovered, timelineViewMeta, ScreenSize );
}
