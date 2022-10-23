/*
BSD 3-Clause License

Copyright (c) 2022, Dylan N (Zeal)
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

// My github: https://github.com/bituq

// Thanks to Ehsan2077 for inspiring me to make this shader.
// Thanks to BlueSkyDefender for his support.

#include "ReShade.fxh"

namespace AdaptiveRim
{
	uniform float3 Color <
		ui_category = "Rim";
		ui_tooltip = "Adjust the rim's tint";
		ui_type = "color";
	> = float3(1, 1, 1);
	
	uniform float Strength <
		ui_category = "Rim";
		ui_tooltip = "Adjust the rim's strength";
		ui_type = "slider";
		ui_min = 0; ui_max = 5; ui_step = .1;
	> = 2;
	
	uniform float Offset <
		ui_category = "Rim";
		ui_tooltip = "Adjust the rim's offset";
		ui_type = "slider";
		ui_min = 0.1; ui_max = 10; ui_step = .1;
	> = 2.5;
	
	uniform float Detail <
		ui_category = "Rim";
		ui_tooltip = "Adjust the rim's details";
		ui_type = "slider";
		ui_min = 0; ui_max = 1; ui_step = .01;
	> = .4;
	
	uniform float RimBlurSize <
		ui_label = "Blur Amount";
		ui_category = "Rim";
		ui_type = "slider";
		ui_min = 1; ui_max = 10; ui_step = .1;
	> = 3.6;
	
	uniform uint Adaptive <
		ui_category = "Environment";
		ui_type = "combo";
		ui_items = "Non-Adaptive\0Adaptive\0Hybrid\0Crazy Mode\0";
		ui_tooltip = "Make the backlight adaptive to lighting in its environment";
	> = 2;
	
	uniform uint ColorBlurSize <
		ui_label = "Light Distance";
		ui_type = "slider";
		ui_category = "Environment";
		ui_min = 1; ui_max = 100;
	> = 80;
	
	uniform float Brightness <
		ui_type = "slider";
		ui_category = "Environment";
		ui_min = 1; ui_max = 20; ui_step = .1;
	> = 2;
	
	uniform float Saturation <
		ui_type = "slider";
		ui_category = "Environment";
		ui_min = 0;
		ui_max = 1; ui_step = .01; 
	> = .5;
	
	uniform float Threshold <
		ui_category = "Environment";
		ui_type = "slider";
		ui_min = 0; ui_max = 1; ui_step = .01;
	> = .2;
	
	uniform uint Blend <
		ui_type = "combo";
		ui_label = "Blending Mode";
		ui_items = "Color Dodge\0Add\0";
		ui_tooltip = "Adjust the blending mode of the rim light. DEFAULT = Color Dodge";
		ui_category = "Image";
	> = 0;
	
	uniform uint Debug <
		ui_type = "combo";
		ui_label = "Mode";
		ui_items = "Off\0Rim\0Final Rim\0Blur\0Normals\0Luma\0";
		ui_tooltip = "Adjust the debug mode. DEFAULT = Off";
		ui_category = "Debug Tools";
		ui_category_closed = true;
	> = 0;
	
	uniform bool DepthMapReversed <
		ui_label = "Reverse Depth Map";
		ui_tooltip = "Enable if the depth map is reversed.";
		ui_category = "Debug Tools";
	> = false;
	
	uniform bool DepthMapFlip <
		ui_label = "Flip Depth Map";
		ui_tooltip = "Enable if the depth map is flipped upside down.";
		ui_category = "Debug Tools";
	> = true;
	
	#ifndef CrazyModeSpeed
		#define CrazyModeSpeed 0.2 //[0 - 1.0] - What does this do? ;)
	#endif
	
	uniform float2 pingpong < source = "pingpong"; min = 0; max = 1; step = CrazyModeSpeed; smoothing = 0; >;
	
	texture TexNormals { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; };
	sampler sTexNormals { Texture = TexNormals; };
	
	texture TexHNormalBlur { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; };
	sampler sTexHNormalBlur { Texture = TexHNormalBlur; };
	
	texture TexNormalBlur { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; };
	sampler sTexNormalBlur { Texture = TexNormalBlur; };
	
	texture TexLuma { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; MipLevels = 5; };
	sampler sTexLuma {Texture = TexLuma; SRGBTexture = true; };	
	
	texture TexHColorBlur { Width = BUFFER_WIDTH / 4; Height = BUFFER_HEIGHT / 4; };
	sampler sTexHColorBlur {Texture = TexHColorBlur;};
	
	texture TexColorBlur { Width = BUFFER_WIDTH / 4; Height = BUFFER_HEIGHT / 4; MipLevels = 4; };
	sampler sTexColorBlur { Texture = TexColorBlur;};
	
	texture TexRim { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT;};
	sampler sTexRim {Texture = TexRim;};

	// https://www.chilliant.com/rgb2hsv.html
	float3 HueToRgb(in float H)
	{
		float R = abs(H * 6 - 3) - 1;
		float G = 2 - abs(H * 6 - 2);
		float B = 2 - abs(H * 6 - 4);
		return saturate(float3(R,G,B));
	}
	
	float GetDepth(in float2 tc)
	{
		float depth;
		if (!DepthMapFlip)
			tc.y = 1.0 - tc.y;
	
		depth = tex2Dlod(ReShade::DepthBuffer, float4(tc, 0, 0)).x;
	
		if (DepthMapReversed)
			depth = 1 - depth;
		
		return 1 - depth * .3;
	}
	
	float3 NormalVector(in float4 pos : SV_Position, in float2 tc: TexCoord) : SV_Target
	{
		float Depth = 1 - GetDepth(tc);
			
		// Rim becomes thinner farther away
		float3 offset = Offset / 1000; // Set to 100 for LSD shader ;)
		offset += float3(BUFFER_PIXEL_SIZE.xy, 0);
		
		const float2 posCenter = tc.xy;
		const float2 posNorth = posCenter - offset.zy;
		const float2 posEast = posCenter + offset.xz;
	
		const float3 vertCenter = float3(posCenter - .5, 1) * GetDepth(posCenter);
		const float3 vertNorth = float3(posNorth - 0.5, 1) * GetDepth(posNorth);
		const float3 vertEast = float3(posEast - 0.5, 1) * GetDepth(posEast);
	
		return normalize(cross(vertCenter - vertNorth, vertCenter - vertEast)) * 0.5;
	}
	
	int MapBlendingMode(int ComboOption)
	{
		if (ComboOption == 0) // Color Dodge
			return 7;
		else if (ComboOption == 1) // Overlay
			return 8;
		else
			return 1; // Normal
	}
	
	// Luma pass
	void Luma(in float4 pos : SV_Position, in float2 tc : TexCoord, out float4 color : SV_Target)
	{
		color = tex2D(ReShade::BackBuffer, tc).rgb;
		
		// Isolate bright luma
		float intensity = dot(color.rgb, float3(.2126, .7152, .0722));
		color.rgb /= max(intensity, 0.0001);
		color.a = GetDepth(tc);
		color.a *= max(0, intensity - Threshold);
		color.rgb *= color.a;
		
		color = float4(color.rgb, intensity);
	}
	
	// Backlight pixel shader
	float3 Rimlight(in float4 pos : SV_Position, in float2 tc : TexCoord): SV_Target
	{
		float3 color = cross(tex2D(sTexNormalBlur, tc).rgb, float3(0, lerp(1, 0, Detail), 1));
		return color.r * Color;
	}
	
	// Horizontal blur
	float3 HBlur(in float4 pos : SV_Position, in float2 tc : TexCoord, in sampler tex, in float bs, in float steps)
	{
		float3 color;
		for (int i = -bs; i <= bs; i++)
			color += (bs - abs(i))*tex2D( tex, tc + float2(( BUFFER_RCP_WIDTH * ( ( steps * i ) + 0.5)), 0)).rgb;	
		return color/((bs*bs));
	}
	
	// Vertical blur
	float3 VBlur(in float4 pos : SV_Position, in float2 tc : TexCoord, in sampler tex, in float bs, in float steps)
	{
		float3 color;
		for (int i = -bs; i <= bs; i++)
			color += (bs - abs(i))*tex2D( tex, tc + float2(0,( BUFFER_RCP_HEIGHT * ( ( steps * i ) + 0.5 )))).rgb;
		return color/(bs*bs);
	}
	
	// Horizontal color blur pass
	float3 HColorBlur(float4 pos : SV_Position, float2 tc : TexCoord) : SV_Target
	{
		float3 large = HBlur(pos, tc, sTexLuma, max(1, ColorBlurSize), 10);
		float3 small = HBlur(pos, tc, sTexLuma, max(1, ColorBlurSize / 8), 8);
		return small + large;
	}
	
	// Final color blur pass
	float3 ColorBlur(float4 pos : SV_Position, float2 tc: TexCoord) : SV_Target
	{
		float3 large = VBlur(pos, tc, sTexHColorBlur, max(1, ColorBlurSize / 4), 8);
		float3 small = VBlur(pos, tc, sTexLuma, max(1, ColorBlurSize / 8), 8);
		float3 color = small + large;
		
		float grayscale = dot(color, .333);
		color = saturate(lerp(grayscale, color, lerp(0, 2, Saturation)));
		
		return saturate(color * Brightness);
	}
	
	// Horizontal normals blur pass
	float3 HNormalBlur(float4 pos : SV_Position, float2 tc : TexCoord) : SV_Target
	{
		return HBlur(pos, tc, sTexNormals, RimBlurSize, 2);
	}
	
	float3 NormalBlur(float4 pos : SV_Position, float2 tc : TexCoord) : SV_Target
	{
		float3 result = VBlur(pos, tc, sTexHNormalBlur, RimBlurSize, 2);
		return result.g - result.b;
	}
	
	// Darken Blending
	float3 Darken(float3 a, float3 b)
	{
		return min(a, b);
	}
	
	// Color Dodge Blending
	float3 ColorDodge(float3 a, float3 b)
	{
		if (b.r < 1 && b.g < 1 && b.b < 1)
			return min(1.0, a / (1.0 - b));
		else
			return 1.0;
	}
	
	// Add Blending
	float3 Addition(float3 a, float3 b)
	{
		return min((a + b), 1);
	}
	
	float3 Result(float4 pos : SV_Position, float2 tc : TexCoord) : SV_Target
	{
		float3 backBuffer = tex2D(ReShade::BackBuffer, tc).rgb;
		float3 color = backBuffer;
		
		if (Adaptive == 1 || Adaptive == 2) // Adaptive
			color = tex2Dlod(sTexColorBlur, float4(tc, 0, 4)).rgb;
		if (Adaptive == 2) // Hybrid
			color = max(color, backBuffer / 3);
		if (Adaptive == 3) // Crazy Mode
			color *= HueToRgb(pingpong.x);
			
		float3 result = Darken(color, tex2D(sTexRim, tc).rgb);
		float brightness = tex2Dlod(sTexLuma, float4(tc, 0, 5)).a;
		brightness = smoothstep(1, -1, brightness);
		brightness *= Strength;
		result *= brightness * Strength;
		
		if (Debug == 1) // Rim
			result = tex2D(sTexRim, tc).rgb;
		else if (Debug == 2) // Final Rim
			return result;
		else if (Debug == 3) // Blur
			result = tex2Dlod(sTexColorBlur, float4(tc, 0, 2)).rgb;
		else if (Debug == 4) // Normals
			result = tex2D(sTexNormalBlur, tc).rgb;
		else if (Debug == 5) // Luma
			result = brightness;
		else
		{
			if (Blend == 0) // Color Dodge
				result = ColorDodge(tex2D(ReShade::BackBuffer, tc).rgb, result);
			else if (Blend == 1) // Addition
				result = Addition(tex2D(ReShade::BackBuffer, tc).rgb, result);
		}
		
		return result;
	}
	
	technique RimLight < ui_label = "Adaptive Rimlight"; ui_tooltip = "Adaptive rim lighting // By Zeal //"; >
	{
		pass Normals
		{
			VertexShader = PostProcessVS;
			PixelShader = NormalVector;
			RenderTarget = TexNormals;
		}
		pass Luma
		{
			VertexShader = PostProcessVS;
			PixelShader = Luma;
			RenderTarget = TexLuma;
		}
		pass HColorBlur
		{
			VertexShader = PostProcessVS;
			PixelShader = HColorBlur;
			RenderTarget = TexHColorBlur;
		}
		pass ColorBlur
		{
			VertexShader = PostProcessVS;
			PixelShader = ColorBlur;
			RenderTarget = TexColorBlur;
		}
		pass Rim
		{
			VertexShader = PostProcessVS;
			PixelShader = Rimlight;
			RenderTarget = TexRim;
		}
		pass HNormalBlur
		{
			VertexShader = PostProcessVS;
			PixelShader = HNormalBlur;
			RenderTarget = TexHNormalBlur;
		}
		pass NormalBlur
		{
			VertexShader = PostProcessVS;
			PixelShader = NormalBlur;
			RenderTarget = TexNormalBlur;
		}
		pass Result
		{
			VertexShader = PostProcessVS;
			PixelShader = Result;
		}
	}
}
