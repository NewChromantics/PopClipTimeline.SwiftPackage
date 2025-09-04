#include <metal_stdlib>
using namespace metal;


struct Clip
{
	uint32_t column;
	uint32_t width;
	uint32_t row;
	uint32_t type;
	uint32_t id;
};

struct Marker
{
	uint32_t column;
	uint32_t type;
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



float3 GetClipColour(Clip content)
{
	return GetDebugColour(content.type);
}


float3 GetMarkerColour(Clip content)
{
	const int DebugColourCount = 1;
	float3 DebugColours[DebugColourCount] =
	{
		float3(1,1,1),
	};
	return DebugColours[content.type%DebugColourCount];
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

fragment FragColourAndDepthOut ColourFrag(ContentVertexOutput in [[stage_in]])
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
	float3 Colour = GetClipColour(in.clip);
	if ( Odd )
		Colour = mix( Colour, 0.5, 0.2 );
	return { .colour = float4( Colour, 1 ), .depth=BoxDepth };
}



fragment float4 MarkerFrag(ContentVertexOutput in [[stage_in]])
{
	float3 Colour = GetMarkerColour(in.clip);
	return float4( Colour, 0.8 );

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
	float coordX = mix( left, right, vert.x );
	float coordY = clip.row;
	
	out.screenPosition = CoordToScreenPx( float2(coordX,coordY), timelineViewMeta );
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
	ContentVertexOutput out;
	QuadVertex vert = quadVertexes[vertexId];
	auto clip = clips[instanceId];
	int RowsCovered = 1;
	
	return ClipBoxVertexImpl( vertexId, clip, RowsCovered, timelineViewMeta, ScreenSize );
	/*
	
	//	make pixel box
	float left = clip.column;
	float right = left + (clip.width);

	//	get coords
	float coordX = mix( left, right, vert.x );
	float coordY = clip.row;
	
	out.screenPosition = CoordToScreenPx( float2(coordX,coordY), timelineViewMeta );
	out.screenPosition.y += vert.y * timelineViewMeta.rowHeightPx;
	
	out.clipPosition = ScreenPxToClip( out.screenPosition, ScreenSize );
	out.uv = float2(vert.x,vert.y);
	out.boxSizePx = float2( clip.width * timelineViewMeta.columnWidthPx, timelineViewMeta.rowHeightPx );
	out.boxPx = out.uv * out.boxSizePx;
	out.coordX = coordX;
	out.clip = clip;
	
	return out;*/
}


vertex ContentVertexOutput MarkerVertex( uint vertexId [[vertex_id]],
										 uint instanceId [[instance_id]],
										 constant Marker* markers[[buffer(0)]],
										 constant TimelineViewMeta& timelineViewMeta[[buffer(1)]],
										 constant float2& ScreenSize[[buffer(2)]]
										 ) 
{
	ContentVertexOutput out;
	QuadVertex vert = quadVertexes[vertexId];
	auto marker = markers[instanceId];
	//auto clip = clips[instanceId];
	Clip clip;
	clip.column = marker.column;
	clip.width = 1;
	clip.row = 0;
	int RowsCovered = 100;

	return ClipBoxVertexImpl( vertexId, clip, RowsCovered, timelineViewMeta, ScreenSize );
}
